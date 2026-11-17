#!/bin/sh
# gta2srv headless setup from /userdata/gta2srv (writable from TWRP / USB without a screen):
#   authorized_keys      -> appended to /home/gta2/.ssh/authorized_keys
#   wifi/*.nmconnection  -> NetworkManager connections
# Imported files are renamed *.imported so they apply once.
S=/userdata/gta2srv
if [ -f $S/authorized_keys ]; then
  install -d -m 700 -o gta2 -g gta2 /home/gta2/.ssh
  touch /home/gta2/.ssh/authorized_keys
  while read -r k; do [ -n "$k" ] && ! grep -qxF "$k" /home/gta2/.ssh/authorized_keys && echo "$k" >> /home/gta2/.ssh/authorized_keys; done < $S/authorized_keys
  chown gta2:gta2 /home/gta2/.ssh/authorized_keys; chmod 600 /home/gta2/.ssh/authorized_keys
  mv $S/authorized_keys $S/authorized_keys.imported
fi
for f in $S/wifi/*.nmconnection; do
  [ -f "$f" ] || continue
  install -m 600 "$f" /etc/NetworkManager/system-connections/; mv "$f" "$f.imported"
done
exit 0
