#!/bin/bash

# Client-side script for OpenVPN over Obfsproxy for Tcx Darknet
# Inspired from PPPoSSL script

. functions.sh

function start_obfsproxy
{
    local mypidfile="$1"
    
    $OBFS --log-file=$obfslog --log-min-severity=info obfs2 --dest=$host:$port client 127.0.0.1:5050 &

    echo $! >"$mypidfile"
}

function print_log {
    echo "-------- OpenVPN LOG --------"
    cat $logfile
    echo "-----------------------------"
    echo "------- Obfsproxy LOG -------"
    cat $obfslog
    echo "-----------------------------"
    return 0
}

host=$1
port=$2
pwd=$(pwd)

[ -z "$host" -o -z "$port" ] && echo Syntax: $0 host port "[OpenVPN options]" && exit

if [ -z "$(echo $host | egrep '^([0-9]{1,3}\.){3}[0-9]{1,3}')" ]; then
    echo -n "You did not give an IP address, should I do a DNS lookup? [y/n] "
    read lkp;
    if [ "$lkp" = y ]; then
	host=$(dig +short $host | head -n 1);
    else
	host=""
    fi
fi
if [ -z "$host" ]; then print_error "Unable to resolve hostname"; exit; fi

# Look for various required commands...
which sha1sum >/dev/null 2>&1 || (print_error "Could not find sha1sum" && kill $$)
which uuidgen >/dev/null 2>&1 || (print_error "Could not find uuidgen" && kill $$)

OBFS=$(which obfsproxy 2>/dev/null)
[ -z "$OBFS" ] && print_error "Could not find obfsproxy executable" && exit

OVPN=$(which openvpn 2>/dev/null)
[ -z "$OVPN" ] && print_error "Could not find openvpn" && exit

IP=$(which ip 2>/dev/null)
[ -z "$IP" ] && print_error "Could not find 'ip' executable" && exit

IPT=$(which iptables 2>/dev/null)
[ -z "$IPT" ] && print_error "Could not find iptables" && exit

IP6T=$(which ip6tables 2>/dev/null)
[ -z "$IP6T" ] && print_error "Could not find ip6tables" && exit

[ ! -r "$pwd/wnh-ca.crt" ] && print_error "SSL CA certificate file 'wnh-ca.crt' not found" && exit

gateway=$($IP route | awk '/default/ { print $3 }')
[ -z "$gateway" ] && print_error "Could not get current gateway. Are you connected to the Internet?" && exit
dev=$($IP route | awk '/default/ { print $5 }')

# Pre-set config
id=$(uuidgen)
shortid=$(echo $id | cut -d - -f 1)
iptpfx="OBOVTCX-"$shortid
resolvconf="nameserver 10.8.49.1
nameserver 8.8.8.8
nameserver 8.8.4.4"

iptlogfile=""
obfspidfile=/tmp/obfs.pid-$id
obfslog=/tmp/obfs.log-$id
pidfile=/tmp/openvpn.pid-$id
logfile=/tmp/openvpn.log-$id

shift
shift

print_center "$(datestamp)"
print_center "OpenVPN over Obfsproxy client starting"

echo -----------
echo Host: $host
echo Port: $port
echo Current gateway: $gateway "($dev)"
echo -----------

# 0. Find where iptables messages will be logged to
echo -n "Looking for iptables logging... "
iptlogfile=$(search_iptables_log "testTCX-$shortid")
if [ -n "$iptlogfile" ]; then echo $(print_right "$iptlogfile"); else echo $(print_right "Not found!"); fi

# 1. Retrieve interface list before pppd startup
oldiflist="("$($IP addr | awk -F ': ' '/^[0-9]/ { print $2 }' | xargs | sed 's/ /|/g')")"

full=n
echo -n "Do you want to activate full redirection of your traffic (i.e. change default route)? [y/n] "
read full

# 2. Start Obfsproxy
echo -n "Starting obfsproxy... "
start_obfsproxy $obfspidfile
sleep 5
kill -0 $(cat $obfspidfile) 2>/dev/null
if [ $? = 0 ]; then
    echo $(print_right ok)
else
    echo $(print_right error)
    exit
fi
obfspid=$(cat $obfspidfile)

# 3. Start OpenVPN
echo -e 'a\nb' >/tmp/auth-$id
options="--daemon --client --dev tun --proto tcp --remote 127.0.0.1 5050 --route $host 255.255.255.255 net_gateway --persist-tun --script-security 3 --auth-user-pass /tmp/auth-$id --writepid $pidfile --log $logfile --comp-lzo --ping 5 --verb 3 --ca $pwd/wnh-ca.crt --pull"
if [ "$full" != y ]; then
    options="$options --route-nopull --route 10.8.0.0 255.255.0.0 --route 10.7.0.0 255.255.0.0"
fi
options="$options $@"
echo -n "Starting OpenVPN... "
$OVPN $options
sleep 5
kill -0 $(cat $pidfile)
if [ $? = 0 ]; then
    echo $(print_right ok)
else
    echo $(print_right error)
    print_log
    kill $obfspid
    exit
fi
pid=$(cat $pidfile)

# 4. Wait a bit for interface to come up
maxwait=120
echo -n "Waiting for TUN interface (max: $maxwait seconds)... "

start=$(date +%s)
end=$(($start + $maxwait))

# 5. check interface has come up
while [ -z "$newif" ]; do
    newif=$($IP addr | awk -F ': ' '/^[0-9]/ { print $2 }' | grep tun | egrep -v "$oldiflist")

    if [ -z "$newif" -a $(date +%s) -gt $end ];then
	echo "Time up!"$(print_right error)
	kill $pid
	kill $obfspid
	print_log
	rm -f /tmp/*-$id
	exit
    fi

    sleep 1
done

echo $newif$(print_right ok)


# 6. Set routing to DN
maxwaitgw=240
start=$(date +%s)
end=$(($start + $maxwaitgw))

echo -n "Waiting for an IP address (max: $maxwaitgw seconds)... "
while [ -z "$gw" ]; do
    check_if=$(cat /proc/net/dev | egrep "^ *$newif:")

    if [ -z "$check_if" ]; then
	echo "Network interface '$newif' is down!$(print_right error)"
	kill $pid 2>/dev/null
	kill $obfspid 2>/dev/null
	print_log
	exit
    fi

    gw=$($IP addr show dev $newif 2>/dev/null | awk '/inet / {print $4}' | sed 's-/.*--')
    dnip=$($IP addr show dev $newif 2>/dev/null | awk '/inet / {print $2}' | sed 's-/.*--')

    if [ -z "$gw" -a $(date +%s) -gt $end ]; then
	echo "Gateway was not set!$(print_right error)"
	kill $pid
	kill $obfspid
	print_log
	exit
    fi

    sleep 1
done

echo "local IP: $dnip <-> gateway: $gw"$(print_right ok)

echo "Changing DNS servers in /etc/resolv.conf"
mv -f /etc/resolv.conf /tmp/resolv.conf-$id
echo "$resolvconf" >/etc/resolv.conf

if [ "$full" = "y" ]; then
    watchconfig $pidfile "$resolvconf" $gw $newif &
    echo "Blocking any traffic of interface $dev not going to $host"
    global_firewall $dev $host $iptpfx block
else
    watchconfig $pidfile "$resolvconf" &
    echo "Blocking outbound traffic on port 53 (DNS) to interface $dev"
    dns_firewall $dev $iptpfx block
fi

if [ -n "$iptlogfile" ]; then
    watchfirewall $pidfile "$iptlogfile" "$iptpfx" &
fi

echo VPN is running - Hit CTRL+C to terminate it.

trap "echo Received SIGINT, shutting down && kill $pid && rm -f $pidfile" SIGINT

running=yes
while [ $running = yes ]; do
    kill -0 $pid 2>/dev/null
    if [ $? != 0 ]; then
	running=no
    else
	sleep 1
    fi
done

echo Terminated - restoring configuration.
print_log

if [ "$full" = y ]; then
    global_firewall $dev $host $iptpfx unblock
else
    dns_firewall $dev $iptpfx unblock
fi

kill $obfspid
mv -f /tmp/resolv.conf-$id /etc/resolv.conf
rm -f /tmp/*-$id

print_center "$(datestamp)"
print_center "VPN session terminating"
