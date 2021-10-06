#!/bin/sh
. /etc/profile.d/hosts.sh
systemctl restart systemd-networkd
systemctl restart systemd-resolved
machinectl list
router=$rth0
route del -net 0 gw $router dev eth0
route del -host 0 gw $router dev eth0
#route add -host 192.168.0.254 gw $router dev eth0
route add -host 192.168.1.254 gw $router dev eth0
route add -net $angl3 gw $router dev eth0
route add -net $gyth7 gw $router dev eth0
route del default gw $router
route add default gw $router
