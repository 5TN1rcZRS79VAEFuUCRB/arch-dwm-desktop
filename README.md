# arch-dwm-desktop

A one-command setup for my Arch Linux desktop: dwm, st and dmenu with my configs, a status
bar with CPU/GPU/RAM/volume/mic, mouse-clickable audio device pickers, dark mode everywhere,
and Firefox/KeePassXC settings. Desktop only: nothing from the media server is in here.

## Quick start

On an Arch machine with a normal user that has `sudo`, and a network connection:

```sh
sudo pacman -S --needed git        # if you don't have it yet
git clone https://github.com/5TN1rcZRS79VAEFuUCRB/arch-dwm-desktop.git
cd arch-dwm-desktop
./install.sh
```

Then log in on the first **text console** (Ctrl+Alt+F1). X starts automatically after login. If it
doesn't (other console, or you exited X), run `startx`.

### Options

| Option | What it does |
| --- | --- |
| `--dpi N` | Display scaling: `96` (100%), `120`, `144` (150%), `168`, `192` (200%). By default a re-run keeps the value already in `~/.Xresources`, so scaling you picked stays put; a first install works it out from your monitor's physical size (read from the kernel if X isn't running yet; a laptop's built-in panel is scaled down a quarter since you sit closer to it, so a 14" 1920×1200 laptop gets 120), otherwise 96. |
| `--steam` | Also install Steam plus the matching 32-bit graphics libraries. Needs `[multilib]` enabled in `/etc/pacman.conf`. |
| `--no-packages` | Skip the pacman step. |
| `--no-build` | Skip compiling and installing dwm/st/dmenu. |

Re-running the installer is safe. Anything it would overwrite is copied to
`~/.desktop-backup/<timestamp>/` first.

If it guessed the scaling wrong (it can't see your monitor when run from a text console), fix it
without reinstalling anything: `./install.sh --no-packages --no-build --dpi 144`, then log out
of X and run `startx` again.

## What gets installed

| Piece | Where it goes |
| --- | --- |
| dwm, st, dmenu (built from the sources in `suckless/`) | `~/.local/src/` and `/usr/local/bin/` |
| `.xinitrc`, `.Xresources` (scaling, cursor), `.bash_profile` (starts X when you log in on tty1) | `~/` |
| Bar, audio, tray, network (`dwm-net`), battery (`dwm-power`) and screenshot scripts, the idle screen-off (`dwm-blank`), plus a `keepassxc` launcher (slightly smaller text at high DPI) | `~/.local/bin/` |
| GTK 3/4, Qt 5/6 and xdg-portal dark-mode config | `~/.config/` |
| Firefox settings: dark mode, privacy, no AI or sponsored content (`user.js`) | your Firefox profile directory |
| Firefox extension: uBlock Origin, installed by a policy (`policies.json`) | `/etc/firefox/policies/` (needs sudo) |
| Xorg: touchpad tap-to-click (one finger left, two right, three middle); on AMD GPUs only, AMD's driver (`xf86-video-amdgpu`) with TearFree | `/etc/X11/xorg.conf.d/` (needs sudo) |
| `.local` hostnames over mDNS (`ssh user@machine.local`): Avahi enabled, `mdns_minimal` added to the `hosts:` line | `/etc/nsswitch.conf` (needs sudo) |
| KeePassXC dark theme | `~/.config/keepassxc/keepassxc.ini` (only that one setting) |
| Syncthing (keeps the KeePassXC database in sync), started now and at every login | `systemctl --user enable syncthing`. Pair devices and share the folder yourself at http://127.0.0.1:8384; keys are never in this repo |
| Desktop-wide "prefer dark" | dconf (`org.gnome.desktop.interface`) |
| git commit name and email (GitHub noreply address) | `~/.gitconfig` (only `user.name` and `user.email`) |
| Claude Code: ponytail + caveman plugins, caveman proxy started with every session (only if `claude` is installed; undo with `caveman disable claude`) | `~/.claude/settings.json`, `~/.claude.json`, `~/.caveman/` |

Packages are listed in `packages.txt`.

## Keys and mouse

`Mod` is the Super (Windows) key.

| Action | Keys |
| --- | --- |
| Terminal / launcher | `Mod+Shift+Enter` / `Mod+P` |
| Focus next / previous window | `Mod+J` / `Mod+K` |
| Resize the main area | `Mod+H` / `Mod+L` |
| Swap window with the main area | `Mod+Enter` |
| Tiling / floating / monocle layout | `Mod+T` / `Mod+F` / `Mod+M` |
| Close window | `Mod+Shift+C` |
| Go to workspace 1-9 / move window there | `Mod+1..9` / `Mod+Shift+1..9` |
| Hide the bar | `Mod+B` |
| Quit dwm | `Mod+Shift+Q` |
| **Volume up / down / mute** | `Mod+F12` / `Mod+F11` / `Mod+F10` (or the keyboard's media keys) |
| **Mic up / down / mute** | `Mod+Shift+F12` / `Mod+Shift+F11` / `Mod+Shift+F10` |
| **Laptop screen brightness up / down** | The keyboard's brightness keys (5% steps) |
| **Output device picker / input device picker** | `Mod+O` / `Mod+Shift+O` |
| **Tray apps menu** | `Mod+Shift+T`, or right-click the window title in the bar |
| **Network picker** | `Mod+N` |
| **Battery details / power profile** | `Mod+Shift+P` |
| **Screenshot: whole screen / drag an area** | `Print` / `Shift+Print` |

On the status bar text itself:

| Mouse | Action |
| --- | --- |
| Scroll up / down | Output volume up / down |
| `Shift` + scroll | Mic volume up / down |
| Left click | Output device picker |
| Right click | Input device picker |
| Middle click | Mute output |

Inside a picker menu, click an entry to select it, scroll to move the highlight, and right-click
or click outside to cancel. The bottom entry jumps between the output and input pickers.

## System tray

dwm has no tray, so apps that "minimize to tray" (Discord, Steam, ...) would just vanish. `dwm-tray`
runs a small StatusNotifier service (started from `.xinitrc`) that those apps register with.
Press `Mod+Shift+T` (or right-click the window title in the bar) to get a dmenu list of the apps
in the tray; choosing one brings it back. Every app is also listed as `quit: <app>`: choosing that
closes it for real (an app's window close button usually just hides it back to the tray). It clicks the
Quit/Exit entry in the app's tray menu, or sends the app a normal terminate signal if it has none.

Apps register when they start, so launch them after logging in to X. An app that was already
running before the tray service started may not appear until it is restarted. Apps that only
support the old-style tray (not StatusNotifier) will not show up.

## Network picker

`Mod+N` opens a dmenu list of the Wi-Fi networks in range (strongest first, with signal, security and
`saved`/`connected` tags), your wired and VPN connections, and a few actions: turn Wi-Fi on or off,
rescan, forget a saved network, and `nmtui` for anything unusual such as a hidden network.
Choose a network to connect. A new network that needs a password opens a small terminal that asks for
it, so the password is never shown on screen. The bar does not show the network name; the picker's
first line says what you are connected to.

This needs **NetworkManager**. When installing Arch with `archinstall`, choose *NetworkManager* under
network configuration (the installer adds the package but does not switch your network setup over).
Turn it on with `sudo systemctl enable --now NetworkManager`; join Wi-Fi the first time with
`nmtui` if you have no other way online.

## Battery (laptops)

On a machine with a battery the bar shows `BAT 87%`, with `+` while charging, `=` when the charge
limit is holding it, and `!` when it is at 15% or below. Nothing is shown on a desktop.
`Mod+Shift+P` opens a dmenu list with the time left (or until full), power draw, battery health,
any charge limit and, if `power-profiles-daemon` is installed, the power profile, which you can
switch by choosing one.

## Screenshots

`Print` saves a screenshot of the whole screen and `Shift+Print` lets you drag a rectangle (click a
window to grab just it, `Esc` cancels). Both write a PNG to `~/Pictures/Screenshots/` and copy it
to the clipboard, so you can paste it straight into a chat. It is the `dwm-shot` script, which uses
`maim`, `slop` and `xclip`. The keys are part of dwm, so they work after dwm is rebuilt and restarted;
until then, run `dwm-shot` from dmenu (`Mod+P`).

## Idle screen-off (no DPMS)

After 10 minutes idle the screen goes black, but the monitor is **not** put to sleep: `dwm-blank` sets every
output's brightness to 0 while the X screen saver is active and restores it the instant you touch a key or the
mouse. DPMS is switched off in `.xinitrc` on purpose. With some monitors on NVIDIA + DisplayPort (seen with a
Samsung Odyssey G8 at 4K 240 Hz, whose compressed DSC link does not re-train after a long sleep), waking from
DPMS sleep can leave "monitor on, no picture" until you reboot. Not cutting the signal avoids that. If your setup
has no such problem and you want real monitor sleep, replace the `xset -dpms` block in `.xinitrc` with
`xset s 600 600` and `xset dpms 600 600 600`, and stop starting `dwm-blank`. Video players that suppress the
screen saver are honoured, because `dwm-blank` follows the X server's own saver state.

## Not included on purpose

* **NVIDIA drivers.** The right package depends on your GPU and kernel: install it yourself
  (for example `sudo pacman -S nvidia-open`). The bar shows GPU load and temperature by itself once
  `nvidia-smi` works (it uses one long-running `nvidia-smi`, not a new one every second).
* **GPU/RGB lighting control** (hardware specific).
* **Monitor refresh rate and G-SYNC.** These depend on the monitor and output name, so `.xinitrc`
  only has a commented-out `xrandr` example to edit.
* **All server software** (Jellyfin, Radarr/Sonarr, Docker, Cloudflare and so on) and any
  passwords or API keys.

## Updating this repo

The installer copies files *from* this repo *to* your home directory. To keep the repo current
after changing your live setup, copy the changed file back into the matching path under
`home/`, `firefox/` or `suckless/` and commit it.

`suckless/UPSTREAM.txt` records which upstream commits the vendored dwm/st/dmenu are based on
and what was changed. Those tools keep their own licenses (see the `LICENSE` files inside).

## License

The scripts, configuration and installer in this repository are under the MIT license (see `LICENSE`).
dwm, st and dmenu in `suckless/` are the suckless.org projects and keep their own licenses
(see the `LICENSE` file in each folder).
