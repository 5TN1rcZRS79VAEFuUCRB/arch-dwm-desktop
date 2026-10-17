#
# ~/.bash_profile
#

# Put ~/.local/bin (claude, launcher wrappers) on PATH for every login, including SSH.
# .xinitrc only covers the X session.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

[[ -f ~/.bashrc ]] && . ~/.bashrc

# Start X automatically when logging in on the first text console (not over SSH, not on
# other consoles, not from a terminal that is already inside X). Not exec'd on purpose:
# if X exits or fails to start you land back at a shell instead of a login loop.
# X is started again only when dwm-update asked for a restart (dwm-blank then ended the session).
if [[ -z "${DISPLAY:-}" && "${XDG_VTNR:-}" == 1 ]]; then
	while :; do
		rm -f "$XDG_RUNTIME_DIR/dwm-restart-x"
		startx
		[[ -e $XDG_RUNTIME_DIR/dwm-restart-x ]] || break
	done
fi
