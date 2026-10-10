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
                  Default: on a re-run, the value already in ~/.Xresources;
                  on a first install, 96.
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
REPLACED=()

backup_if_different() { # dest src
	local dest=$1 src=$2 rel
	if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
		rel=${dest#"$HOME"/}
		mkdir -p "$BACKUP/$(dirname "$rel")"
		cp -a "$dest" "$BACKUP/$rel"
		REPLACED+=("$rel")
	fi
}

place() { # src dest
	local src=$1 dest=$2 mode=644
	[ -x "$src" ] && mode=755
	backup_if_different "$dest" "$src"
	install -Dm"$mode" "$src" "$dest"
}

# Root-owned files: an existing different one is kept next to it as .bak-<date>.
sudo_place() { # src dest
	cmp -s "$1" "$2" 2>/dev/null && return
	[ -e "$2" ] && sudo cp -a "$2" "$2.bak-$(date +%Y%m%d-%H%M%S)"
	sudo install -Dm644 "$1" "$2"
	echo "Installed $2"
}

# ---------------------------------------------------------------- packages
if [ "$DO_PACKAGES" -eq 1 ]; then
	say "Installing packages (sudo password may be requested)"
	mapfile -t PKGS < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' packages.txt | grep -v '^$')
	sudo pacman -S --needed --noconfirm "${PKGS[@]}"
fi

# ---------------------------------------------------------------- display scaling
# On a re-run keep the DPI already in ~/.Xresources, so a scaling picked by hand (or with an
# earlier --dpi) is not replaced. A first install uses 96 unless --dpi says otherwise.
if [ -z "$DPI" ] && [ -f "$HOME/.Xresources" ]; then
	DPI="$(awk '/^Xft\.dpi:/{ if (int($2) > 0) print int($2); exit }' "$HOME/.Xresources")"
	[ -n "$DPI" ] && say "Keeping your current display scaling: ${DPI} DPI (change it with --dpi N)"
fi
DPI="${DPI:-96}"
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
	# Extensions (uBlock Origin, Violentmonkey) come from a system-wide Firefox policy, so they are
	# installed automatically the next time Firefox starts. Needs root because it lives in /etc.
	# The Always-visible userscript ships in this repo, but Violentmonkey keeps its scripts in its
	# own storage, which a policy cannot seed, so it is imported by hand once (see the line printed).
	sudo_place firefox/policies.json /etc/firefox/policies/policies.json
	# Links opened from other programs (dwm-todo, chat apps) go to Firefox, not another installed browser.
	{ xdg-settings set default-web-browser firefox.desktop && xdg-mime default firefox.desktop text/html; } \
		|| warn "could not make Firefox the default browser; run: xdg-settings set default-web-browser firefox.desktop"
	echo "Violentmonkey will auto-install; import the userscript once by opening this in Firefox:"
	echo "  file://$PWD/firefox/always-visible.user.js   (Violentmonkey shows an install page)"
else
	warn "firefox is not installed; skipping its settings"
fi

# ---------------------------------------------------------------- Xorg config (/etc/X11)
# Touchpad tap-to-click everywhere (it only matches touchpads, so desktops are unaffected).
# AMD's X driver with TearFree only when a GPU runs on the amdgpu kernel driver, so NVIDIA and
# Intel machines get neither the package nor the file. Takes effect when X next starts.
say "Xorg config: touchpad tap-to-click, AMD TearFree"
HAS_AMDGPU=0
for d in /sys/class/drm/card[0-9]*/device/driver; do
	[ "$(basename "$(readlink -f "$d")")" = amdgpu ] && HAS_AMDGPU=1
done
if [ "$HAS_AMDGPU" -eq 1 ] && [ "$DO_PACKAGES" -eq 1 ]; then
	sudo pacman -S --needed --noconfirm xf86-video-amdgpu
fi
for f in etc/X11/xorg.conf.d/*.conf; do
	dest="/$f"
	if [ "${f##*/}" = 20-amdgpu.conf ] && [ "$HAS_AMDGPU" -eq 0 ]; then
		continue
	fi
	sudo_place "$f" "$dest"
done

# Replugging a mouse re-applies the dwm-mouse settings (Mod+Shift+M): the rule starts a user service.
# The 70- rule lets the same menu read a Razer mouse's DPI without root.
say "udev: re-apply mouse settings on replug, Razer DPI access"
sudo_place etc/udev/rules.d/90-dwm-mouse.rules /etc/udev/rules.d/90-dwm-mouse.rules
sudo_place etc/udev/rules.d/70-dwm-mouse-dpi.rules /etc/udev/rules.d/70-dwm-mouse-dpi.rules
sudo udevadm control --reload || warn "could not reload udev rules; they take effect after a reboot"
sudo udevadm trigger --subsystem-match=hidraw --action=change 2>/dev/null || true
systemctl --user daemon-reload 2>/dev/null || true

# ---------------------------------------------------------------- local hostnames (mDNS)
# Avahi announces this machine as <hostname>.local, and nss-mdns lets ssh, ping, etc.
# look up other machines' .local names. Adds mdns_minimal to the hosts: line only once.
say "mDNS: .local hostnames"
if [ -e /usr/lib/libnss_mdns_minimal.so.2 ]; then
	if ! grep -q '^hosts:.*mdns' /etc/nsswitch.conf; then
		sudo cp -a /etc/nsswitch.conf "/etc/nsswitch.conf.bak-$(date +%Y%m%d-%H%M%S)"
		sudo sed -Ei '/^hosts:/s/ (resolve|files)/ mdns_minimal [NOTFOUND=return] \1/' /etc/nsswitch.conf
	fi
	sudo systemctl enable --now avahi-daemon \
		|| warn "could not start avahi; run: sudo systemctl enable --now avahi-daemon"
else
	warn "nss-mdns is not installed; skipping .local hostnames"
fi

# ---------------------------------------------------------------- Syncthing (KeePassXC sync)
# Only the service is set up here. Device keys and the folder/device pairing live in
# ~/.local/state/syncthing and are never in this repo; pair devices at http://127.0.0.1:8384.
say "Tailscale and ssh arch-server"
# ~/.ssh/config stays this machine's own file; the repo's host entries come in through an Include.
SSH_INCLUDE='Include ~/.ssh/config.d/*.conf'
touch "$HOME/.ssh/config" && chmod 600 "$HOME/.ssh/config"
if ! grep -qxF "$SSH_INCLUDE" "$HOME/.ssh/config"; then
	if [ -s "$HOME/.ssh/config" ]; then sed -i "1i $SSH_INCLUDE" "$HOME/.ssh/config"; else echo "$SSH_INCLUDE" > "$HOME/.ssh/config"; fi
fi
if command -v tailscale >/dev/null; then
	sudo systemctl enable --now tailscaled || warn "could not start tailscaled; run: sudo systemctl enable --now tailscaled"
	tailscale status >/dev/null 2>&1 || warn "Tailscale is not logged in yet; run once: sudo tailscale up"
fi

say "Syncthing: start now and at every login"
if command -v syncthing >/dev/null; then
	systemctl --user enable --now syncthing \
		|| warn "could not start syncthing; after logging in run: systemctl --user enable --now syncthing"
else
	warn "syncthing is not installed; skipping"
fi

# ---------------------------------------------------------------- git identity
# GitHub noreply address, so commits work and push without exposing an email.
say "git: commit name and email"
git config --global user.name 5TN1rcZRS79VAEFuUCRB
git config --global user.email 327155685+5TN1rcZRS79VAEFuUCRB@users.noreply.github.com

# ---------------------------------------------------------------- Claude Code add-ons
# ponytail + caveman plugins, and the caveman proxy routed in front of Claude Code
# (caveman's SessionStart hook starts the proxy each session). Undo: caveman disable claude
say "Claude Code: ponytail and caveman plugins, caveman proxy"
if command -v claude >/dev/null; then
	{
		claude plugin marketplace add DietrichGebert/ponytail \
			&& claude plugin install ponytail@ponytail \
			&& claude plugin marketplace add JuliusBrussee/caveman \
			&& claude plugin install caveman@caveman \
			&& npm install -g --prefix "$HOME/.local" @caveman-ai/cli \
			&& "$HOME/.local/bin/caveman" setup --install \
			&& "$HOME/.local/bin/caveman" enable claude
	} || warn "Claude add-ons failed (often a download hiccup); rerun: ./install.sh --no-packages --no-build"
else
	warn "Claude Code is not installed; skipping. Install it (curl -fsSL https://claude.ai/install.sh | bash), then rerun"
fi

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
# Hand edits to these files are gone from the live copies; copy back into the repo any worth keeping.
if [ ${#REPLACED[@]} -gt 0 ]; then
	warn "these files differed from the repo and were replaced (old copies in $BACKUP):"
	printf '  ~/%s\n' "${REPLACED[@]}" >&2
fi
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
