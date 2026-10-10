xrdb -merge ~/.Xresources

# Make sure ~/.local/bin (my launcher wrappers, e.g. keepassxc) comes before /usr/bin.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# Every monitor at the fastest refresh rate of its native (first listed) resolution. X otherwise
# uses the monitor's "preferred" mode, which is often 60 Hz even on a 240 Hz panel, and fullscreen
# games then only offer 60 Hz.
xrandr | awk '/ connected/ { out = $1; getline; max = 0
	for (i = 2; i <= NF; i++) if ($i + 0 > max) max = $i + 0
	print out, $1, max }' |
while read -r out res rate; do xrandr --output "$out" --mode "$res" --rate "$rate"; done

# G-SYNC on NVIDIA. The driver lists this monitor as "G-SYNC Compatible (unvalidated)" and leaves
# VRR off for those unless the metamode asks for it. Fullscreen games then sync to the frame rate.
command -v nvidia-settings >/dev/null &&
	nvidia-settings --assign CurrentMetaMode="$(nvidia-settings -q CurrentMetaMode -t |
		sed 's/.*:: //; s/{/{AllowGSYNCCompatible=On, /g')" >/dev/null

# Idle screen-off WITHOUT DPMS. Cutting the video signal (DPMS) can leave some monitors unable to bring
# the picture back on NVIDIA + DisplayPort with a compressed 4K 240 Hz mode (a long sleep, then "monitor
# on, no picture"). So: DPMS off, and dwm-blank turns the brightness to 0 (signal keeps flowing) while
# the X screen saver is active, i.e. after 10 minutes idle; any key or mouse press restores it instantly.
xset -dpms
xset s 600 600                   # the screen saver "activates" after 10 minutes idle...
xset s noblank
xset s noexpose                  # ...but the X server itself must not blank (that could cut the signal too)
"$HOME/.local/bin/dwm-blank" &   # ...and dwm-blank turns the brightness to 0 while it is active

# Mouse speed / acceleration profile saved from Mod+Shift+M (no-op until something is saved).
"$HOME/.local/bin/dwm-mouse" apply

# Route Qt apps (KeePassXC, etc.) through qt6ct/qt5ct so they pick up the
# dark palette configured there, instead of Qt's undecorated default style.
# Both names are listed because Qt5 apps (KeePassXC) only load the qt5ct
# plugin and Qt6 apps (OpenRGB) only load qt6ct; each skips the one it can't.
export QT_QPA_PLATFORMTHEME="qt5ct:qt6ct"

# Fullscreen SDL games (Garry's Mod, Source games, ...) minimize or leave fullscreen when they
# lose focus, and under dwm every tag switch takes focus away, so they came back as a tiny
# window. Tell SDL not to do that.
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0

# Make DISPLAY/XAUTHORITY visible to D-Bus-activated and systemd --user
# services (xdg-desktop-portal in particular) -- a bare startx session has
# no display manager to do this automatically.
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY

# Tray host: lets apps that minimize to the tray (Discord, Steam...) register, so
# Mod+Shift+T lists them in dmenu. Started first so apps find it when they launch.
~/.local/bin/dwm-tray daemon &

# Canvas/Schoology assignments, todo.txt and daily pushups: bar text, reminders, daily summary. Menu is Mod+a.
~/.local/bin/dwm-todo daemon &

~/.local/bin/dwm-status.sh &
exec dwm
