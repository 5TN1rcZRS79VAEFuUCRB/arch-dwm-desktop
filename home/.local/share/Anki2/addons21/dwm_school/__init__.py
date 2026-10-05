# dwm-school: after every answered card, tell the dwm-school daemon, so the bar's "Anki: N cards"
# drops right away instead of at the daemon's next check.
import os
import signal

from aqt import gui_hooks

PIDFILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", os.path.expanduser("~/.cache")), "dwm-school.pid")


def poke(*_):
    try:
        with open(PIDFILE) as f:
            os.kill(int(f.read()), signal.SIGUSR1)
    except (OSError, ValueError):
        pass  # no daemon running: nothing to tell


gui_hooks.reviewer_did_answer_card.append(poke)
