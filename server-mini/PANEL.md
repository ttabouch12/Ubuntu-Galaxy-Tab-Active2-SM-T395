## Web panel (http://&lt;tablet-ip&gt;/)

The tablet has a built-in control panel you can open from any phone or PC on the same network. It is a small home-server dashboard in the style of ZimaOS or CasaOS, built to use as little memory and CPU as possible.

**Sign in** with the tablet's `gta2` password (the default is `gta2`; change it under *Settings → Device*).

| Page | What it does |
|---|---|
| **Home** | Live CPU, memory, temperature, battery (with charging state), storage and IP addresses. Every Docker app shows as a tile with links to its web ports and Start / Stop / Restart / Logs buttons. |
| **App store** | One-click installs of small arm64 apps: File Browser, Uptime Kuma, AdGuard Home, Pi-hole, Home Assistant, Jellyfin, Navidrome, Syncthing, Transmission, qBittorrent, Vaultwarden, Gitea, Node-RED, Mosquitto, Homepage, Dozzle, Nginx Proxy Manager and Nextcloud. Each app shows its approximate RAM use, and the store warns you when free memory is low. App data goes in `/userdata/gta2srv/apps/<app>`. Uninstalling keeps the data unless you tick *delete data*. You can edit the catalog in `/usr/share/gta2/panel/apps.json`. |
| **Files** | Browse the share folder (the same one as `\\tablet\share`) and the SD card when one is inserted. You can upload (drag and drop, large files are fine), download, create folders, rename and delete. |
| **Screen** | Shows the tablet's touchscreen live, at about 2 fps. Click the picture to tap the tablet. There are also Home, Back and Keyboard buttons, a box for typing text, and arrow, Enter, Tab and Backspace keys. |
| **Settings** | Everything the tablet's Settings app does: Wi-Fi, display (brightness, rotation, screen timeout, keyboard size), screensaver, battery charge limit, CPU and thermal, Bluetooth, SMB sharing, Docker service, SSH, VPN (Tailscale, WireGuard), hotspot and USB tether, date and time, device name and password, updates and cleanup, and power (reboot, shut down, TWRP, download mode). |

**Light on memory.** systemd only starts the panel when someone opens the page (socket activation on port 80). The panel exits after 10 minutes without requests, so it uses 0 MB of RAM when nobody is looking. Sessions survive these restarts and last 7 days.

**Security.** The panel listens only on your local network and is not exposed to the internet. Sign-in checks the real `gta2` password from `/etc/shadow`, and failed sign-ins are rate-limited. The session cookie is HttpOnly and SameSite=Strict, and every action requires a custom request header, which blocks CSRF. Commands never go through a shell: they run as argument lists, and the panel validates every name, path and SSID. There is no web terminal; use `ssh gta2@<tablet>`. To reach the panel from outside your home, use Tailscale (*Settings → VPN*) rather than port forwarding.

**Opening it by name.** Run `sudo apt install avahi-daemon` to also reach the panel as `http://<device-name>.local`.

The old status page on port 8088 (no sign-in, for kiosk screens) is unchanged.

### Install (overlay)

```
sudo cp -r usr etc /                      # from this webpanel/ folder
sudo chmod 755 /usr/local/sbin/gta2-panel
sudo systemctl daemon-reload
sudo systemctl enable --now gta2-panel.socket
```
