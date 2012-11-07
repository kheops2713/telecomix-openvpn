#!/bin/bash

# support functions for firewall & config watchdog
######
# NOTE: THE $IP VARIABLE NEEDS TO BE SET WITH PATH TO ip COMMAND
######

function datestamp {
    echo -n $(date +"%Y-%m-%d %H:%M:%S")
}

function print_error {
    echo -e "[$(date +'%H:%M:%S')] \E[1m\E[31mERR: $1\E[0m"
    return 0
}

function print_warning {
    echo -e "[$(date +'%H:%M:%S')] \E[1m\E[33mWARN: $1\E[0m"
    return 0
}

function print_right {
    local len=$(echo $1 | wc -m)
    echo -en "\E[$(($(tput cols) - 1 - $len))G\E[1m$1\E[0m"
    return 0
}

function print_center {
    local len=$(echo "$1" | wc -m)
    local leftcol=$(( ($(tput cols) - $len) / 2))
    echo -e "\E[${leftcol}G$1\E[0m"
}

# This function watches every second the status of /etc/resolv.conf and routing
# It sets them back to the right value if they were changed (in general this is
# due to NetworkManager)
function watchconfig {
    local terminate=no
    local pidfile="$1"
    local good_resolvconf="$2"
    local watchgw="$3"
    local watchif="$4"
 
    local sha1_resolvconf=$(echo "$good_resolvconf" | sha1sum | awk {'print $1'})

    local checkpid=$(cat "$pidfile")

    while [ $terminate = no ]; do
	kill -0 $checkpid 2>/dev/null
	if [ $? != 0 ]; then
	    terminate=yes
	else
	    if [ $(sha1sum /etc/resolv.conf | awk {'print $1'}) != $sha1_resolvconf ]; then
		print_warning "/etc/resolv.conf changed, putting ours back in place."
		echo "$good_resolvconf" >/etc/resolv.conf
	    fi
	    if [ -n "$watchgw" -a -n "$watchif" ]; then
		local curgw=$($IP route | awk '/default/ { print $3 }')
		local curif=$($IP route | awk '/default/ { print $5 }')

		if [ "$curgw" != "$watchgw" ]; then
		    print_warning "Gateway was changed externally to $curgw. Setting it (back) to $watchgw."
		    $IP route del default || terminate=yes
		    $IP route add default via $watchgw dev $watchif || terminate=yes
		fi
	    fi
	fi

	sleep 1
    done

    if [ -r $pidfile ]; then
	kill $pid 2>/dev/null
    fi
}

# This function watches logs for iptables traces reporting blocked packets.
function watchfirewall {
    local packetcount=0
    local pidfile="$1"
    local iptlogfile="$2"
    local iptpfx="$3"

    local checkpid=$(cat $pidfile)

    tail -n 0 -f "$iptlogfile" | while read -r line; do
	if [ -n "$(echo $line | grep $iptpfx)" ]; then
	    packetcount=$(($packetcount + 1))
	    local msg=$(echo $line | sed s/'.*'"$iptpfx"'.* SRC=\([^ ]*\) DST=\([^ ]*\) .*PROTO=\([^ ]*\).*'/"Blocked packet ($packetcount): "'\1 > \2 (protocol: \3)'/);
	    print_warning "$msg"
	fi

	kill -0 $checkpid 2>/dev/null
	if [ $? != 0 ]; then
	    exit
	fi
    done
}

function search_iptables_log
{
    local pfx=${1:0:29}
    $IPT -I OUTPUT 1 -o lo -j LOG --log-level 4 --log-prefix "$pfx" --log-ip-options --log-uid
    ping -c 1 127.0.0.1 >/dev/null 2>&1
    $IPT -D OUTPUT -o lo -j LOG --log-level 4 --log-prefix "$pfx" --log-ip-options --log-uid
    echo $(grep -HZr "$pfx" /var/log/ | awk -F '\0' {'print $1'} | head -n 1)
}

function dns_firewall
{
    local interface=$1
    local logpfx="$2"
    local action=$3

    local dnsfw_udp="-o $interface -p udp --dport 53 -j DROP"
    local dnsfw_tcp="-o $interface -p tcp --dport 53 -j DROP"
    local dnslog_udp="-o $interface -p udp --dport 53 -j LOG --log-level 4 --log-prefix $logpfx --log-ip-options --log-uid"
    local dnslog_tcp="-o $interface -p tcp --dport 53 -j LOG --log-level 4 --log-prefix $logpfx --log-ip-options --log-uid"
   
    local what=""

    if [ $action = "block" ]; then
	what="-I OUTPUT 1"
    elif [ $action = "unblock" ]; then
	what="-D OUTPUT"
    else
	exit
    fi

    $IPT $what $dnsfw_udp
    $IPT $what $dnslog_udp
    $IPT $what $dnsfw_tcp
    $IPT $what $dnslog_tcp

    $IP6T $what $dnsfw_udp
    $IP6T $what $dnslog_udp
    $IP6T $what $dnsfw_udp
    $IP6T $what $dnslog_udp
}

function global_firewall
{
    local interface=$1
    local endpoint=$2
    local logpfx="$3"
    local action=$4
    
    local what=""

    local routelog4="-o $interface ! -d $endpoint -j LOG --log-level 4 --log-prefix $logpfx --log-ip-options --log-uid"
    local routelog6="-o $interface -j LOG --log-level 4 --log-prefix $logpfx --log-ip-options --log-uid"
    local routefw4="-o $interface ! -d $endpoint -j DROP"
    local routefw6="-o $interface -j DROP"
    
    if [ $action = "block" ]; then
	what="-I OUTPUT 1"
    elif [ $action = "unblock" ]; then
	what="-D OUTPUT"
    else
	exit
    fi

    $IPT $what $routefw4
    $IPT $what $routelog4

    $IP6T $what $routefw6
    $IP6T $what $routelog6
}
