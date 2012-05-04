#!/bin/bash

if [ -z "$dev" -o -z "$foreign_option_1" ]; then
    echo This script should only be called by OpenVPN
fi

prepend="## AUTOMATIC BOUNDARY $dev ##\\n"
srvlist=""

for optionname in ${!foreign_option_*} ; do
    option="${!optionname}"

    param1=$(echo "$option" | cut -d ' ' -f 1)
    param2=$(echo "$option" | cut -d ' ' -f 2)
    param3=$(echo "$option" | cut -d ' ' -f 3)

    if [ "$param1" = "dhcp-option" -a "$param2" = DNS ]; then
	prepend="${prepend}nameserver $param3\\n"
	srvlist="${srvlist}$param3 "
    fi
    
done

if [ -n "$prepend" ]; then
    sed -i "s/^/#auto:${dev}# /" /etc/resolv.conf
fi

prepend="${prepend}## AUTOMATIC BOUNDARY $dev ##"
sed -i "1i$prepend" /etc/resolv.conf

echo -e "\E[31;1mINFO: active DNS servers in /etc/resolv.conf are now: $srvlist\E[0m"