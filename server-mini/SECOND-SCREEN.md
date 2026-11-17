# Second screen for your laptop (Sunshine + Moonlight)

The tablet runs **Moonlight** (client). The laptop runs **Sunshine** (host) plus a **virtual display**,
so Windows sees a real extra monitor and streams it to the tablet.

The USB cable gives the lowest latency (no Wi-Fi involved). Wi-Fi works too, 5 GHz recommended.

## 1. Laptop (Windows)

1. Install **Sunshine**: <https://github.com/LizardByte/Sunshine/releases> (the Windows installer).
2. Install a **virtual display driver** so Windows gets an extra monitor, e.g.
   *Virtual Display Driver* (<https://github.com/VirtualDrivers/Virtual-Display-Driver>).
   Add a custom resolution of **800 x 1280** (portrait) at 60 Hz in its settings, then in
   *Windows Settings > Display* place the new screen next to your laptop screen.
3. Open Sunshine's web UI: <https://localhost:47990>, set a user/password.
   In *Configuration > Audio/Video* select the virtual display as the output (`output_name`),
   so Sunshine streams that screen and not your main one.

## 2. Tablet

1. Plug the USB cable in (or be on the same Wi-Fi).
2. Launcher > **Second screen**. Over USB the laptop's IP is filled in automatically (`10.15.19.10x`).
   Over Wi-Fi type the laptop's IP.
3. Tap **Pair**. A 4-digit PIN appears. Enter it in Sunshine's web UI > **PIN**.
4. Tap **Start**. Press **Home** on the tablet to go back to the launcher.

Defaults: 800x1280, 60 fps, 12 Mbit/s, H.264, sound stays on the laptop.
Touch on the tablet acts as the mouse on that screen.

## What to expect

There is no GPU driver on this kernel without Android, so video is decoded by the 8 CPU cores
(ffmpeg, software). Expect 30-60 fps at 800x1280 and roughly 30-50 ms extra latency over USB.
Good for docs, chat, monitoring, music players. Not for gaming.

## Troubleshooting

* "pair failed": check the laptop firewall allows Sunshine (TCP 47984-47990, UDP 47998-48010).
* Black screen: in Sunshine select the virtual display as output, and make sure it is enabled in Windows.
* Choppy: lower FPS to 30 or bitrate to 6000 on the Second screen page.
