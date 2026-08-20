# Dori

An Android phone is a good camera and a spare screen that you already own. Dori
puts both on the Omarchy bar: one icon, one panel, everything over the USB cable
you charge with.

![Dori: the phone's screen mirrored on the desktop, next to the Dori panel](preview.png)

- **Camera** — the phone's back or front camera appears as an ordinary webcam at
  `/dev/video10`, so Meet, Zoom, Discord, OBS and anything else that opens a
  `/dev/video*` node can use it without knowing where the picture comes from.
- **Screen** — the phone's display mirrored in a window, with audio and
  keyboard, at a bitrate and codec you choose.
- **Screenshot** — one click puts the phone's screen on your clipboard and in
  `~/Pictures/dori`, because the reason you took it is usually to paste it.
- **Record** — the phone's screen to an mp4 in the background, with no mirror
  window in the way, while you keep using the phone.
- **No cable** — switch the connection to Wi-Fi and unplug. Everything above
  keeps working.
- **It tells you what is wrong.** A phone that is plugged in but not authorised
  looks exactly like a working one from the bar. Dori says which it is.

Everything the panel does, the scripts in [`bin/`](bin) also do from a
terminal, so a phone that will not cooperate can be debugged without the shell
in the way.

## Requirements

| | |
|---|---|
| Omarchy | Quattro (the Quickshell bar) |
| Phone | Android 12 or newer for the camera; any adb-capable Android for the mirror |
| Packages | `scrcpy`, `android-tools`, `v4l-utils`, `v4l2loopback-dkms` |
| Optional | `wl-clipboard`, so a screenshot lands on the clipboard as well as on disk |
| On the phone | USB debugging enabled in Developer options |

`bin/dori-setup` installs the packages for you on Arch and Omarchy.

## Install

```bash
omarchy plugin add https://github.com/infiniV/omarchy-dori --enable
```

Then run the one-time host setup, in a terminal, once per machine:

```bash
~/.config/omarchy/plugins/io.github.infiniv.dori/bin/dori-setup
```

It installs the missing packages, writes the two `/etc` files that make the
loopback webcam exist after every reboot, and loads the module now. It asks for
your sudo password when it needs it and never installs a passwordless sudo rule.
The screen mirror works without any of this; only the webcam needs the module.

Finally, enable USB debugging on the phone (Settings › Developer options), plug
it in, and accept the prompt it shows. The bar icon lights up when a stream is
live.

## Use

| Where | Action |
|---|---|
| Left click the icon | open the panel |
| Right click | cycle the camera: off → back → front → off |
| Middle click | start or focus the screen mirror |
| Panel | all of it, plus screenshot, recording, codec, bitrate, and Wi-Fi |

**Working without the cable.** Plug the phone in, open the panel, and turn on
*Work without the cable*. Dori switches the phone's adb to Wi-Fi and reconnects
over the network; the cable can then come out and the camera, the mirror and
everything else keep working. Turning it back off closes the network connection
and puts the phone's daemon back on USB, so it is not left listening.

The icon stays on the bar, dimmed, when no phone is attached. Turn on **Hide the
bar icon when no phone is attached** in the plugin's settings if you would rather
it disappeared.

## Settings

Omarchy renders these from the manifest, under the plugin's own settings.

| Setting | Default | What it is for |
|---|---|---|
| Webcam device | `/dev/video10` | must match the `video_nr` the module was loaded with |
| Back / front camera id | `0` / `1` | run `scrcpy --list-cameras` if the two buttons are swapped |
| Front camera rotation | `0` | some phones deliver the front sensor upside down; set `180` |
| Mirror codec | `h264` | `h265` is smaller at the same quality and needs a phone that encodes it |
| Mirror bitrate | `20 Mbps` | 4 is unwatchable, 60 saturates USB 2 |
| Mirror frame rate | `60` | |
| Blank the phone screen | off | turns the phone's own display off while mirroring |

Dori asks the phone which hardware encoder it has rather than pinning a vendor
name, so h265 works on a Samsung, a Pixel, and a OnePlus without being told
which is which.

## From a terminal

```bash
bin/dori-status [--full]        # one JSON blob: device, battery, camera, mirror
bin/dori-camera back|front|off|cycle
bin/dori-mirror start|toggle|focus|stop|restart [--codec h265] [--bitrate 30M]
bin/dori-shot                   # screenshot to ~/Pictures/dori and the clipboard
bin/dori-record start|stop|toggle|status
bin/dori-wireless on|off|status
bin/dori-setup [--uninstall]
```

Every script takes `--help`. Logs go to `$XDG_RUNTIME_DIR/dori/`, never to a
shared `/tmp` path.

## When it does not work

| What you see | What it means |
|---|---|
| "Accept the USB debugging prompt" | the phone is attached but has not trusted this machine; unlock it and look for the dialog |
| "No webcam device at /dev/video10" | `v4l2loopback` is not loaded — run `bin/dori-setup` |
| Back and front buttons are swapped | set the camera ids in settings, from `scrcpy --list-cameras` |
| Front camera is upside down | set front camera rotation to `180` |
| Camera buttons do nothing on an older phone | camera capture needs Android 12; the mirror still works |
| Mirror opens then dies | see `$XDG_RUNTIME_DIR/dori/mirror.log` |
| "Work without the cable" is greyed out | it needs the phone on the cable once, to switch it over |
| Wi-Fi connects, then drops later | phones reset adb over TCP on reboot and on some Wi-Fi changes; plug in and switch again |
| A recording will not play | it was killed rather than stopped; use the panel or `dori-record stop`, which lets scrcpy finalise the file |

## What it runs on your machine

Dori is a QML panel plus a handful of bash scripts. It starts `scrcpy`, reads
`adb`, and that is the whole of it.

- `bin/dori-setup` is the only part that uses `sudo`, only when you run it
  yourself in a terminal. It installs packages with `pacman`, writes
  `/etc/modprobe.d/dori-v4l2loopback.conf` and
  `/etc/modules-load.d/dori-v4l2loopback.conf`, and loads the module.
  `--uninstall` removes exactly those two files and unloads the module.
- No sudoers rule, passwordless or otherwise, is ever installed.
- Nothing is downloaded and executed. Nothing is sent anywhere.
- `dori-wireless` is the only part that puts anything on the network: it is
  Android's own adb-over-TCP, off by default, switched on by you, and closed
  again by the same toggle.

## Uninstall

```bash
~/.config/omarchy/plugins/io.github.infiniv.dori/bin/dori-setup --uninstall
omarchy plugin remove io.github.infiniv.dori
```

The first line removes the two `/etc` files and unloads the module; the second
removes the plugin. Packages installed by the setup are left alone.

## Credits

Built on [scrcpy](https://github.com/Genymobile/scrcpy) by Genymobile, which does
all of the hard work, and [v4l2loopback](https://github.com/umlaeute/v4l2loopback).

## License

[MIT](LICENSE)
