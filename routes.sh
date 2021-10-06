#!/bin/sh
route del default gw openwrt.lan
route add -net 192.168.0.0/24 gw openwrt.lan dev enp4s0
route add default gw 192.168.0.1 dev enp4s0
