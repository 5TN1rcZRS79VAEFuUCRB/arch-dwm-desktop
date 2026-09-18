xrdb -merge ~/.Xresources

# Make sure ~/.local/bin (my launcher wrappers, e.g. keepassxc) comes before /usr/bin.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# Optional and machine specific: set your monitor's refresh rate (output names are in `xrandr`).
# xrandr --output DP-0 --mode 3840x2160 --rate 240

# Power down the monitor after 10 minutes idle (DPMS); any key/mouse
# activity wakes it again automatically -- that's DPMS's default behavior.
xset s 600 600
xset dpms 600 600 600

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

~/.local/bin/dwm-status.sh &
exec dwm
