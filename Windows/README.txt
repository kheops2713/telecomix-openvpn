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
i. Edit stunnel.conf and put your endpoint's stunnel IP and port in the 'connect' parameter. Then place stunnel.conf file in: 
    Program Files\stunnel

ii. Edit openvpn-stunnel.conf and put your endpoint's IP in the 'route' line. Then place openvpn-stunnel.conf in:
    Program Files/OpenVPN Technologies/OpenVPN Client/core

iii. You will also need to have wnh-ca.crt in:
    Program Files/OpenVPN Technologies/OpenVPN Client/core

iv.  As administrator, open two Command Prompt windows. In Windows 7/Vista  you are able to do this by right clicking on the icon and choosing "Run as administrator". Issue in each window the next: (Or you can start "stunnel.cmd" then "openvpn-stunnel.cmd" as administrator too. These files is in this repository too)

    A:
        cd /
        cd "Program Files\stunnel"
        stunnel stunnel.conf
    B:
        cd /
        cd "Program Files\OpenVPN Technologies\OpenVPN Client\core"
        openvpn --config openvpn-stunnel.conf



3. Connection through Obfsproxy
i. Edit openvpn-obfsproxy.conf and put your endpoint's IP and Obfsproxy port in the 'remote' line and its IP in the 'route' line. Place it in:
    Program Files/OpenVPN Technologies/OpenVPN Client/core

ii. You will need to have both obfsproxy.exe and wnh-ca.crt in:
    Program Files/OpenVPN Technologies/OpenVPN Client/core

iii.  As administrator, open two Command Prompt windows. In Windows 7/Vista  you will be able to do this by right clicking on the icon and choosing  "Run as administrator". Issue in each window the next: (Or you can just start "obfsproxy.cmd" then "openvpn-obfsproxy.cmd" as administrator too. These files is in this repository too)
   
    A:
        cd /
        cd "Program Files\OpenVPN Technologies\OpenVPN Client\core"
        obfsproxy obfs2 socks 127.0.0.1:5050
    B:
        cd /
        cd "Program Files\OpenVPN Technologies\OpenVPN Client\core"
        openvpn --config openvpn-obfsproxy.conf

Note:
Paths may differ from those explained above if you didn't install any of the required softwares in the default path, or if you had an x64 system. In the last case, the paths will be:
    Program Files (x86)\...
That's of course if you installed them in the default path.
