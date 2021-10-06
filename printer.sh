#!/bin/sh
#systemctl restart systemd-networkd
#killall dhcpd
#dhcpd -4 eth0
arp -s print.lan.local 00:1b:a9:98:a1:5e
ping print.lan.local -c1
