#!/usr/bin/env bash
#
# Recreates this dwm desktop on an Arch Linux machine.
# Run as your normal user (it calls sudo where it needs root):  ./install.sh
# Safe to re-run; anything it would overwrite is backed up first.

set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

DPI="${DPI:-}"
DO_PACKAGES=1
DO_BUILD=1
WITH_STEAM=0

usage() {
	cat <<'EOF'
Usage: ./install.sh [options]

  --dpi N         display scaling: 96 (100%), 120, 144 (150%), 168, 192 (200%).
                  Default: worked out from your monitor's size (needs a running X
                  session), otherwise 96.
  --steam         also install Steam (needs the [multilib] repo enabled in
                  /etc/pacman.conf) and the matching 32-bit graphics libraries
  --no-packages   skip the pacman step
  --no-build      skip compiling/installing dwm, st and dmenu
  -h, --help      this text
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	--dpi)         DPI="${2:?--dpi needs a number}"; shift ;;
	--steam)       WITH_STEAM=1 ;;
	--no-packages) DO_PACKAGES=0 ;;
	--no-build)    DO_BUILD=0 ;;
	-h|--help)     usage; exit 0 ;;
	*)             echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
	esac
	shift
done

say()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root (it uses sudo where needed)"
command -v pacman >/dev/null || die "this installer is for Arch Linux (pacman not found)"
command -v sudo   >/dev/null || die "sudo is required"

BACKUP="$HOME/.desktop-backup/$(date +%Y%m%d-%H%M%S)"
BACKED_UP=0

backup_if_different() { # dest src
	local dest=$1 src=$2 rel
	if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
		rel=${dest#"$HOME"/}
		mkdir -p "$BACKUP/$(dirname "$rel")"
		cp -a "$dest" "$BACKUP/$rel"
		BACKED_UP=1
	fi
}

place() { # src dest
	local src=$1 dest=$2 mode=644
	[ -x "$src" ] && mode=755
	backup_if_different "$dest" "$src"
	install -Dm"$mode" "$src" "$dest"
}

# ---------------------------------------------------------------- packages
if [ "$DO_PACKAGES" -eq 1 ]; then
	say "Installing packages (sudo password may be requested)"
	mapfile -t PKGS < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' packages.txt | grep -v '^$')
	sudo pacman -S --needed --noconfirm "${PKGS[@]}"
fi

# ---------------------------------------------------------------- display scaling
detect_dpi() {
	command -v xrandr >/dev/null && [ -n "${DISPLAY:-}" ] || return 1
	xrandr --current 2>/dev/null | python3 -c '
import re, sys
best = None
for line in sys.stdin:
    m = re.match(r"^(\S+) connected( primary)? (\d+)x(\d+)\+\d+\+\d+ .*? (\d+)mm x (\d+)mm", line)
    if m and int(m.group(5)) > 0:
        dpi = int(m.group(3)) * 25.4 / int(m.group(5))
        if best is None or m.group(2):
            best = dpi
if best is None:
    sys.exit(1)
print(min([96, 120, 144, 168, 192], key=lambda s: abs(s - best)))'
}

if [ -z "$DPI" ]; then
	if DPI="$(detect_dpi 2>/dev/null)" && [ -n "$DPI" ]; then
		say "Detected display scaling: ${DPI} DPI"
	else
		DPI=96
		warn "could not detect your monitor (no X session running); using 96 DPI."
		warn "on a 4K screen rerun with e.g.  ./install.sh --no-packages --no-build --dpi 144"
	fi
fi
case "$DPI" in ''|*[!0-9]*) die "--dpi must be a number, got '$DPI'" ;; esac

# ---------------------------------------------------------------- dotfiles + scripts
say "Installing config files and scripts into $HOME"
while IFS= read -r -d '' f; do
	rel=${f#home/}
	if [ "$rel" = ".Xresources" ]; then
		tmp="$(mktemp)"
		sed "s/^Xft\.dpi:.*/Xft.dpi: ${DPI}/" "$f" > "$tmp"
		place "$tmp" "$HOME/$rel"
		rm -f "$tmp"
	else
		place "$f" "$HOME/$rel"
	fi
done < <(find home -type f -print0)

# ---------------------------------------------------------------- Firefox
find_ff_profile() {
	local base d
	for base in "$HOME/.config/mozilla/firefox" "$HOME/.mozilla/firefox"; do
		for d in "$base"/*.default-release; do
			[ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
		done
	done
	return 1
}

say "Firefox settings"
if command -v firefox >/dev/null; then
	FF_PROFILE="$(find_ff_profile || true)"
	if [ -z "$FF_PROFILE" ]; then
		echo "No Firefox profile yet; starting Firefox headless once to create it..."
		timeout 20 firefox --headless --no-remote about:blank >/dev/null 2>&1 || true
		FF_PROFILE="$(find_ff_profile || true)"
	fi
	if [ -n "$FF_PROFILE" ]; then
		place firefox/user.js "$FF_PROFILE/user.js"
		echo "Installed user.js into $FF_PROFILE (restart Firefox to apply)"
	else
		warn "could not find/create a Firefox profile. Start Firefox once, close it, then run:"
		warn "  ./install.sh --no-packages --no-build"
	fi
	# Extensions (uBlock Origin) come from a system-wide Firefox policy, so they are installed
	# automatically the next time Firefox starts. Needs root because it lives in /etc.
	POLICY=/etc/firefox/policies/policies.json
	if ! cmp -s firefox/policies.json "$POLICY" 2>/dev/null; then
		[ -e "$POLICY" ] && sudo cp -a "$POLICY" "$POLICY.bak-$(date +%Y%m%d-%H%M%S)"
		sudo install -Dm644 firefox/policies.json "$POLICY"
		echo "Installed Firefox extension policy ($POLICY)"
	fi
else
	warn "firefox is not installed; skipping its settings"
fi

# ---------------------------------------------------------------- KeePassXC theme
say "KeePassXC: dark theme"
KP="$HOME/.config/keepassxc/keepassxc.ini"
mkdir -p "$(dirname "$KP")"
python3 - "$KP" <<'EOF'
import os, sys
p = sys.argv[1]
lines = open(p).read().split("\n") if os.path.exists(p) else []
for i, l in enumerate(lines):
    if l.startswith("ApplicationTheme="):
        lines[i] = "ApplicationTheme=dark"
        break
else:
    if "[GUI]" in lines:
        lines.insert(lines.index("[GUI]") + 1, "ApplicationTheme=dark")
    else:
        lines += ["[GUI]", "ApplicationTheme=dark"]
open(p, "w").write("\n".join(lines).rstrip("\n") + "\n")
EOF

# ---------------------------------------------------------------- GTK dark preference (dconf)
say "GTK/desktop dark preference"
dconf_write() {
	if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
		dconf write "$1" "$2"
	else
		dbus-run-session -- dconf write "$1" "$2"
	fi
}
if command -v dconf >/dev/null; then
	dconf_write /org/gnome/desktop/interface/color-scheme "'prefer-dark'" \
		&& dconf_write /org/gnome/desktop/interface/gtk-theme "'Adwaita'" \
		|| warn "could not write the dark preference; run: gsettings set org.gnome.desktop.interface color-scheme prefer-dark"
else
	warn "dconf is not installed; skipping the desktop dark preference"
fi

# ---------------------------------------------------------------- dwm / st / dmenu
if [ "$DO_BUILD" -eq 1 ]; then
	say "Building and installing dwm, st and dmenu (sudo for 'make install')"
	for t in dwm st dmenu; do
		dest="$HOME/.local/src/$t"
		mkdir -p "$dest"
		[ -e "$dest/config.h" ] && backup_if_different "$dest/config.h" "suckless/$t/config.h"
		cp -a "suckless/$t/." "$dest/"
	done
	# dwm's config.h calls the audio script by absolute path; point it at this user's home
	sed -i "s#/home/USER#$HOME#g" "$HOME/.local/src/dwm/config.h"
	for t in dwm st dmenu; do
		make -C "$HOME/.local/src/$t"
		sudo make -C "$HOME/.local/src/$t" install
	done
fi

# ---------------------------------------------------------------- Steam (optional)
if [ "$WITH_STEAM" -eq 1 ]; then
	say "Steam"
	if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
		warn "[multilib] is not enabled in /etc/pacman.conf. Uncomment the [multilib] section"
		warn "(and its Include line), run 'sudo pacman -Sy', then rerun with --steam."
	else
		gpu="$(lspci 2>/dev/null | grep -Ei 'vga|3d' || true)"
		libs=()
		case "$gpu" in
		*[Nn][Vv][Ii][Dd][Ii][Aa]*) libs+=(lib32-nvidia-utils) ;;
		*AMD*|*ATI*|*Radeon*)      libs+=(lib32-vulkan-radeon) ;;
		*Intel*)                   libs+=(lib32-vulkan-intel) ;;
		esac
		[ ${#libs[@]} -gt 0 ] || warn "unrecognised GPU; you may be asked to pick a 32-bit Vulkan driver"
		sudo pacman -S --needed --noconfirm "${libs[@]}" steam
	fi
fi

# ---------------------------------------------------------------- done
say "Done"
[ "$BACKED_UP" -eq 1 ] && echo "Existing files that were replaced are saved in: $BACKUP"
cat <<EOF

Next steps:
  1. Log out, then log in on the first text console (Ctrl+Alt+F1): X starts automatically.
     (On another console, or after exiting X, run:  startx)
  2. Mod is the Super/Windows key. Mod+Shift+Enter opens a terminal, Mod+P a launcher.
     See README.md for the audio keys and the full list.
  3. NVIDIA card? Install the driver yourself first (e.g. 'sudo pacman -S nvidia-open'),
     since the right package depends on your GPU and kernel. It is not part of this repo.
  4. Display too big/small?  ./install.sh --no-packages --no-build --dpi 120   (or 144, 192...)
EOF
