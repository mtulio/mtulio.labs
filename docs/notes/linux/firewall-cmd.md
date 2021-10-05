# firewall-cmd


## Zones

* List all zones

`firewall-cmd --list-all-zones`

* Get zone from a given interface

`firewall-cmd --get-zone-of-interface=tun0`

* Create NEW Zone

`firewall-cmd --new-zone=vpn --permanent`
