- Telecomix International -


This small package contains three OpenVPN sample config files,
one Stunnel sample config file and a root certificate used on
the WNH darknet.

OpenVPN config files are respectively designed for the
following type of connection:
- direct connection to an OpenVPN server
- connection through stunnel (provides SSL encapsulation)
- connection through Obfsproxy (obfsuscates the traffic), or
  any other locally installed SOCKS proxy (can be Tor as well)



0. Required software
Select the versions that fit with your Operating System.

- OpenVPN: http://openvpn.net/index.php/download.html
- Stunnel: http://stunnel.cybermirror.org/
- Obfsproxy: http://telecomix.ceops.eu/software/obfsproxy.exe
  Source code is on https://torproject.org

The 'stunnel', 'obfsproxy' and 'openvpn' commands should all
be available for execution from the command line.



1. Direct connection
i. Edit openvpn-direct.conf and put your endpoint's IP and 
   port in the 'remote' parameter.

ii. Issue the command:
    openvpn --config openvpn-direct.conf




2. Connection through stunnel
i. Edit stunnel.conf and put your endpoint's stunnel IP and
   port in the 'connect' parameter.

ii. Edit openvpn-stunnel.conf and put your endpoint's IP in the
    'route' line.

iii. Issue:
     stunnel stunnel.conf

iv. Issue:
    openvpn --config openvpn-stunnel.conf




3. Connection through Obfsproxy
i. Edit openvpn-obfsproxy.conf and put your endpoint's IP and
   Obfsproxy port in the 'remote' line and its IP in the 'route'
   line.

ii. Issue:
    obfsproxy obfs2 socks 127.0.0.1:5050

iii. Issue:
     openvpn --config openvpn-obfsproxy.conf
