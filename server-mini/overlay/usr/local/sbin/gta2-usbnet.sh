#!/bin/sh
# gta2: USB networking for the laptop. android_usb RNDIS (0525:a4a2, Windows built-in driver), tablet = 10.15.19.82, DHCP for the PC
A=/sys/class/android_usb/android0
if [ ! -d $A ]; then
  # mainline kernel: configfs RNDIS gadget (same IDs, Windows built-in driver via MS OS descriptors)
  G=/sys/kernel/config/usb_gadget/gta2; mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
  if [ ! -d $G ]; then
    mkdir -p $G/strings/0x409 $G/configs/c.1/strings/0x409 $G/functions/rndis.usb0
    echo 0x0525 > $G/idVendor; echo 0xa4a2 > $G/idProduct; echo gta2srv > $G/strings/0x409/product
    echo RNDIS > $G/configs/c.1/strings/0x409/configuration
    echo 1 > $G/os_desc/use; echo 0xcd > $G/os_desc/b_vendor_code; echo MSFT100 > $G/os_desc/qw_sign
    echo RNDIS > $G/functions/rndis.usb0/os_desc/interface.rndis/compatible_id
    echo 5162001 > $G/functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id
    ln -s $G/functions/rndis.usb0 $G/configs/c.1/; ln -s $G/configs/c.1 $G/os_desc/
    ls /sys/class/udc | head -1 > $G/UDC
  fi
  IF=$(cat $G/functions/rndis.usb0/ifname); ip link set $IF up; ip addr add 10.15.19.82/24 dev $IF 2>/dev/null
  exec dnsmasq -k --interface=$IF --bind-interfaces --port=0 --dhcp-range=10.15.19.100,10.15.19.110,255.255.255.0,1h --dhcp-option=3 --dhcp-option=6 --dhcp-leasefile=/run/gta2-usb.leases
fi
echo 0 > $A/enable; sleep 1
echo 0525 > $A/idVendor; echo a4a2 > $A/idProduct; echo 1 > $A/f_rndis/wceis; echo rndis > $A/functions; echo 1 > $A/enable
i=0; while [ "$(cat $A/state)" != CONFIGURED ] && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
if [ "$(cat $A/state)" != CONFIGURED ]; then echo 0 > $A/enable; echo 0 > $A/f_rndis/wceis; echo 1 > $A/enable; sleep 5; fi
for i in $(seq 1 20); do [ -e /sys/class/net/rndis0 ] && break; sleep 0.5; done
ip link set rndis0 up; ip addr add 10.15.19.82/24 dev rndis0 2>/dev/null
exec dnsmasq -k --interface=rndis0 --bind-interfaces --port=0 --dhcp-range=10.15.19.100,10.15.19.110,255.255.255.0,1h --dhcp-option=3 --dhcp-option=6 --dhcp-leasefile=/run/gta2-usb.leases
