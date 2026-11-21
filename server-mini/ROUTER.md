# gta2-router: Zyxel router stats on the gta2srv dashboards

Status as of 2026-11-21: running on gta2srv. The data was checked against real router traffic: a speed test showed 863.8 Mbit/s.

## 1. What it does

A root daemon logs in to the Zyxel EX3501-T1 router web UI (DAL API, encrypted). It polls the router and writes `/run/gta2/router.json`. Both dashboards read this file through the status page's `/api`.

| Data | Source | Interval |
|---|---|---|
| WAN rx/tx bytes, live Mbit/s, 1m/1h/24h averages and peaks | router `Traffic_Status` → `pppIfaceSt` | 5 s |
| Data volume today / month (persisted), since router boot | computed from byte deltas | 5 s |
| Uptime, firmware, WAN up/down, line rate | router `cardpage_status` | 60 s |
| Clients online | router `lanhosts` (entries with `Active` true) | 60 s |
| Latency to 1.1.1.1, router hop, packet loss | `ping` from the tablet, through the router | 15 s |

The router keeps no passive latency figure. Its ping diagnostic runs only on demand, so latency comes from the tablet's own pings.

## 2. Files

| Repo file (server-mini/overlay) | Installed to | Notes |
|---|---|---|
| `gta2-router` | `/usr/local/sbin/gta2-router` (755) | Python 3.12 daemon. Needs `python3-cryptography` and `python3-requests` (apt). |
| `gta2-router.service` | `/etc/systemd/system/gta2-router.service` | `Restart=always`, `RestartSec=30`, root, `After=network-online.target`, enabled. |
| `router-cards.js` | `/usr/share/gta2/panel/router-cards.js`, inlined in `gta2-dash` | Self-contained add-on that draws the router cards. |

Runtime files:
- `/etc/gta2/router.conf`: `ROUTER=`, `USER=`, `PASS=`. Mode 600, root only, created by `sudo gta2-router-setup`. **Never print, log or commit `PASS`.**
- `/run/gta2/router.json`: world-readable output, no secrets.
- `/var/lib/gta2/router-usage.json`: persisted day/month byte totals.
- `/root/gta2-router-probe.txt`: dump of the router OIDs, with secret fields redacted, from `gta2-router --probe`.

## 3. Router API (verified on EX3501-T1, fw `EX3501-T1-V0.10-260928`)

The login works the same way as `github.com/warlo/hass-wx3401`:
1. `GET /getRSAPublickKey` returns `{"RSAPublicKey": "<PEM>"}`.
2. The client generates an AES key (32 random bytes) and an IV (32 random bytes; AES-CBC uses only the first 16).
3. The login JSON `{"Input_Account":USER,"Input_Passwd":base64(PASS),"currLang":"en","RememberPassword":0,"SHA512_password":false}` is encrypted with AES-256-CBC and PKCS7 padding.
4. `POST /UserLogin` sends `{"content":b64(ciphertext),"key":b64(RSA_PKCS1v15(b64(aeskey))),"iv":b64(iv)}`.
5. The response is `{"iv","content"}`, encrypted with the same AES key. Decrypted, it holds `result: "ZCFG_SUCCESS"` and `sessionkey`.
6. Data calls are `GET /cgi-bin/DAL?oid=<name>` with header `CSRFToken: <sessionkey>`. Responses are encrypted the same way: `{"result","Object":[{...}]}`.
7. Logout is `POST /cgi-bin/UserLogout`. The daemon reuses one session and logs in again after a 401/403.

Facts about this router's data, learned the hard way:
- **The WAN is PPPoE.** The real internet counters are in `Traffic_Status.pppIfaceSt[]`; the busiest entry is the WAN, `[1]` here. `ipIfaceSt` / `ethIfaceSt` / `bridgingStatus` count LAN-side traffic: `br0` "sent" is your download. Do not use them.
- `ipIface[]` and `ipIfaceSt[]` are not in the same order. Pairing them by list position picks the wrong interface. If you ever need them, pair by the `idx` field.
- `cardpage_status.WanLanInfo[]` has entries of `X_ZYXEL_Type` LAN/WAN. The live WAN entry is `X_ZYXEL_SrvName='Internet_ETHWAN'`, `Status='Up'`, `pppConnectionStatus='Connected'`. A second WAN entry, `WWAN` (USB, down), exists too.
- `lanhosts.lanhosts[]` has `PhysAddress`, `Active` and `X_ZYXEL_BytesSent/Received` for each host. That could feed a per-device usage card later.
- **The router allows few sessions.** A lockout also blocks the user's own admin login. The daemon backs off on errors: 30 s doubling up to 15 min, and 30 min after 3 failed logins. Never poll faster than 5 s.

## 4. Dashboard integration

- **Status page** `gta2-dash` (:8088, socket-activated): `api()` returns `'router'` (contents of `/run/gta2/router.json`, or `None`). The router cards add-on (same code as `panel/router-cards.js`) is inlined as a second `<script>` in the page.
- **Panel** (:80): `index.html` loads `/router-cards.js` after `app.js`; it fetches `http://<host>:8088/api` (CORS allowed) and draws its cards under the "Internet" section.
- Cards: Home traffic (router) `#22d3ee`, Data today `#f472b6`, Latency (via router) green/amber/red, Devices online `#a78bfa`, Router uptime `#8e9aaf`, Line rate `#34d399`.

## 5. Setup

```
sudo gta2-router-setup            # once: router address, admin user, password -> /etc/gta2/router.conf (600)
sudo systemctl restart gta2-router
python3 -m json.tool /run/gta2/router.json
sudo /usr/local/sbin/gta2-router --probe | less   # one login, dumps OIDs (secrets redacted)
```
`gta2-router.service` only starts when `/etc/gta2/router.conf` exists. Needs `python3-cryptography`, `python3-requests` (in the build).

## 6. Open items

- The user wants the tablet's own speed test and latency cards replaced by the router data. Their code has not been inspected yet. Find it with:
  `grep -n -i -E "speed|latency|ping" /usr/local/sbin/gta2-dash /usr/share/gta2/panel/app.js | grep -v gta2-router-cards`
- The 1 h and 24 h averages and peaks are kept in memory only, so they reset when the daemon restarts. Day and month totals persist.
- The daemon's own ping hits 1.1.1.1 every 15 s (3 packets). Change `PING_HOST` / `PING_EVERY` in `gta2-router` if needed.
- Do not touch `/userdata/extlinux/*`, kernels, Wi-Fi config or `/etc/modprobe.d`.
