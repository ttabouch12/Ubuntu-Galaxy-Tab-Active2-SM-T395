#!/bin/sh
# gta2: USB networking for the laptop. android_usb RNDIS (0525:a4a2, Windows built-in driver), tablet = 10.15.19.82, DHCP for the PC
A=/sys/class/android_usb/android0
echo 0 > $A/enable; sleep 1
echo 0525 > $A/idVendor; echo a4a2 > $A/idProduct; echo 1 > $A/f_rndis/wceis; echo rndis > $A/functions; echo 1 > $A/enable
i=0; while [ "$(cat $A/state)" != CONFIGURED ] && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
if [ "$(cat $A/state)" != CONFIGURED ]; then echo 0 > $A/enable; echo 0 > $A/f_rndis/wceis; echo 1 > $A/enable; sleep 5; fi
for i in $(seq 1 20); do [ -e /sys/class/net/rndis0 ] && break; sleep 0.5; done
ip link set rndis0 up; ip addr add 10.15.19.82/24 dev rndis0 2>/dev/null
exec dnsmasq -k --interface=rndis0 --bind-interfaces --port=0 --dhcp-range=10.15.19.100,10.15.19.110,255.255.255.0,1h --dhcp-option=3 --dhcp-option=6 --dhcp-leasefile=/run/gta2-usb.leases
