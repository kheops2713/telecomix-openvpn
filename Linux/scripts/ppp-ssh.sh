#!/bin/bash

# Client-side script for PPP-over-SSH for Tcx Darknet
. functions.sh

function print_log  {
    echo "------------ LOG ------------"
    cat /tmp/pppd.log-$id
    echo "-----------------------------"
    return 0
}

host=$1
port=$2
login=$3
privkey=$4
pwd=$(pwd)

[ -z "$host" -o -z "$port" ] && echo Syntax: $0 host port \[remote_login\] \[private_key_file\] && exit
if [ -z "$privkey" ]; then
    print_warning "No private key specified, will use password authentication"
fi
if [ -z "$login" ]; then
    print_warning "No login specified, will use 'root'"
    login=root
fi

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

SSH=$(which ssh 2>/dev/null)
[ -z "$SSH" ] && print_error "Could not find ssh" && exit

PPP=$(which pppd 2>/dev/null)
[ -z "$PPP" ] && print_error "Could not find pppd" && exit

IP=$(which ip 2>/dev/null)
[ -z "$IP" ] && print_error "Could not find 'ip' executable" && exit

IPT=$(which iptables 2>/dev/null)
[ -z "$IPT" ] && print_error "Could not find iptables" && exit

IP6T=$(which ip6tables 2>/dev/null)
[ -z "$IP6T" ] && print_error "Could not find ip6tables" && exit

gateway=$($IP route | awk '/default/ { print $3 }')
[ -z "$gateway" ] && print_error "Could not get current gateway. Are you connected to the Internet?" && exit
dev=$($IP route | awk '/default/ { print $5 }')

# Pre-set config
id=$(uuidgen)
shortid=$(echo $id | cut -d - -f 1)
iptpfx="PPSHTCX-"$shortid
resolvconf="nameserver 10.8.49.1
nameserver 8.8.8.8
nameserver 8.8.4.4"

iptlogfile=""

shift
shift
if [ -n "$1" ]; then
    shift
fi
if [ -n "$1" ]; then
    shift
fi

print_center "$(datestamp)"
print_center "PPP over SSH VPN client starting"

echo -----------
echo Host: $host
echo Port: $port
echo Login: $login
echo Private key file: $privkey
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

# 3. Start pppd
if [ -n "$privkey" ]; then
    if [ "${privkey:0:1}" != "/" ]; then
	privkey=$pwd/$privkey
    fi

    ssh_opt_pk="-i $privkey"
fi
echo -n "Starting pppd... "
$PPP \
    noauth \
    pty "$SSH -p $port -T -e none $ssh_opt_pk $login@$host" \
    linkname $id \
    logfile "/tmp/pppd.log-$id" \
    $@

echo $(print_right ok)

# 4. Wait a bit for interface to come up
maxwait=120
echo -n "Waiting for PPP interface (max: $maxwait seconds)... "

start=$(date +%s)
end=$(($start + $maxwait))

# 5. check interface has come up
while [ -z "$newif" ]; do
    newif=$($IP addr | awk -F ': ' '/^[0-9]/ { print $2 }' | grep ppp | egrep -v "$oldiflist")

    [ -z "$newif" -a $(date +%s) -gt $end ] && \
	echo "Time up!"$(print_right error) && \
	print_log && \
	rm -f /tmp/*-$id && \
	exit

    sleep 1
done

echo $newif$(print_right ok)

pidfile=/var/run/ppp-$id.pid
pid=$(head -n 1 $pidfile)

# 6. Set routing to DN
maxwaitgw=240
start=$(date +%s)
end=$(($start + $maxwaitgw))

echo -n "Waiting for an IP address (max: $maxwaitgw seconds)... "
while [ -z "$gw" ]; do
    check_if=$(cat /proc/net/dev | egrep "^ *$newif:")

    [ -z "$check_if" ] && echo "Network interface '$newif' is down!"$(print_right error) && (kill $pid 2>/dev/null; print_log) && exit

    gw=$($IP route show dev $newif 2>/dev/null | awk {'print $1'})
    dnip=$($IP route show dev $newif 2>/dev/null | awk {'print $7'})

    [ -z "$gw" -a $(date +%s) -gt $end ] && echo "Gateway was not set!$(print_right error)" && kill $pid && print_log && exit

    sleep 1
done

echo "local IP: $dnip <-> gateway: $gw"$(print_right ok)
echo "Adding routes to darknet"
$IP route add 10.7.0.0/16 via $gw dev $newif
$IP route add 10.8.0.0/16 via $gw dev $newif

echo "Changing DNS servers in /etc/resolv.conf"

mv -f /etc/resolv.conf /tmp/resolv.conf-$id
echo "$resolvconf" >/etc/resolv.conf

if [ "$full" = "y" ]; then
    $IP route add $host/32 via $gateway
    $IP route del default
    $IP route add default via $gw dev $newif
    watchconfig $pidfile "$resolvconf" $gw $newif &
    echo "Blocking any traffic of $dev not going to $host"
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

trap "echo Received SIGINT, shutting down && kill $pid" SIGINT

while [ -r $pidfile ]; do
    sleep 1
done

echo Terminated - restoring configuration.
print_log

if [ "$full" = y ]; then
    global_firewall $dev $host $iptpfx unblock
else
    dns_firewall $dev $iptpfx unblock
fi

mv -f /tmp/resolv.conf-$id /etc/resolv.conf
rm -f /tmp/*-$id

if [ "$full" = "y" ]; then
    $IP route add default via $gateway
    $IP route del $host/32 via $gateway
fi

print_center "$(datestamp)"
print_center "VPN session terminating"
