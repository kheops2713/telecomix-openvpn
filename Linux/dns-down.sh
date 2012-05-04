#!/bin/bash

if [ -z "$dev" -o -z "$foreign_option_1" ]; then
    echo This script should only be called by OpenVPN
fi

lookfor="## AUTOMATIC BOUNDARY $dev ##"

line=1
while [ "$(head -n $line /etc/resolv.conf | tail -n 1)" != "$lookfor" ]; do
    line=$(($line+1))
done
sed -i ${line}d /etc/resolv.conf

while [ "$(head -n $line /etc/resolv.conf | tail -n 1)" != "$lookfor" ]; do
    sed -i ${line}d /etc/resolv.conf
done
sed -i ${line}d /etc/resolv.conf

sed -i "s/^#auto:${dev}# //" /etc/resolv.conf

echo -e "\E[31;1mINFO: DNS information in /etc/resolv.conf restored\E[0m"