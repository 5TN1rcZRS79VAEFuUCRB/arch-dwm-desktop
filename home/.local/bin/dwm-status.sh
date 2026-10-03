#!/usr/bin/env bash
#
# dwm status bar: CPU/GPU usage, CPU/GPU temp, RAM usage, volume, clock.
# Sets the root window name, which dwm displays on the right side of its bar.
#
# The clock ticks every second; the heavier stats (CPU/GPU/RAM) are sampled
# in the background every 2s and cached, so the clock never waits on them.

# Not a fixed name in world-writable /tmp: another local user could pre-create it as a symlink.
# Only one bar at a time: stop a copy left over from an earlier start or X session.
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/dwm-status.pid"
[ -r "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null

CACHE="${XDG_RUNTIME_DIR:-$HOME/.cache}/dwm-status-cache"
mkdir -p "$(dirname "$CACHE")"

cpu_usage() {
	local a b c i1 i2 t1 t2
	read -r _ a b c i1 _ < /proc/stat
	t1=$((a + b + c + i1))
	sleep 0.5
	read -r _ a b c i2 _ < /proc/stat
	t2=$((a + b + c + i2))
	echo $((t2 > t1 ? 100 * ((t2 - t1) - (i2 - i1)) / (t2 - t1) : 0))
}

# Intel reports "Package id 0", AMD reports Tctl/Tdie; prints nothing if neither exists.
cpu_temp() {
	sensors 2>/dev/null | awk '
		/^Package id 0:/ { t = $4 }
		/^(Tctl|Tdie):/  { if (t == "") t = $2 }
		END { gsub(/\+|°C/, "", t); if (t != "") printf "%.0f\n", t }'
}

ram_usage() {
	free | awk '/^Mem:/{printf "%.0f%%\n", 100 * $3 / $2}'
}

# GPU load and temperature (NVIDIA only; nothing is shown without nvidia-smi). One long-lived
# nvidia-smi prints a sample every 2 s and we read the latest line. Starting a new nvidia-smi
# twice a second was heavy and clashed with monitor sleep/wake, so do not go back to that.
GPU_FILE="${XDG_RUNTIME_DIR:-$HOME/.cache}/dwm-status-gpu"
rm -f "$GPU_FILE" "$GPU_FILE.tmp"
GPU_READER=
if command -v nvidia-smi >/dev/null; then
	nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits -l 2 2>/dev/null |
		while IFS= read -r line; do
			printf '%s\n' "${line//[[:space:]]/}" > "$GPU_FILE.tmp" && mv "$GPU_FILE.tmp" "$GPU_FILE"
		done &
	GPU_READER=$!
fi

# Laptops only (prints nothing without a battery): a level icon and "87%", with a + while charging, an = when
# held at a charge limit, and a ! when it is low. Details and power profiles: Mod+Shift+P (dwm-power).
battery_text() {
	local b cap status total=0 count=0 charging=0 holding=0 discharging=0
	for b in /sys/class/power_supply/BAT*; do
		[ -r "$b/capacity" ] && [ -r "$b/status" ] || continue
		cap="$(<"$b/capacity")"; status="$(<"$b/status")"
		total=$((total + cap)); count=$((count + 1))
		case "$status" in
			Charging) charging=1 ;;
			"Not charging") holding=1 ;;
			Discharging) discharging=1 ;;
		esac
	done
	[ "$count" -gt 0 ] || return 0
	cap=$((total / count))
	local icons=(    )
	local icon="${icons[(cap + 12) * 4 / 100]}"
	if [ "$charging" = 1 ]; then echo "$icon ${cap}%+"
	elif [ "$discharging" = 1 ] && [ "$cap" -le 15 ]; then echo "$icon ${cap}%!"
	elif [ "$holding" = 1 ]; then echo "$icon ${cap}%="
	else echo "$icon ${cap}%"; fi
}

sampler() {
	while true; do
		cpu="$(cpu_usage)"
		ctemp="$(cpu_temp)"
		ram="$(ram_usage)"
		gpu="$(cat "$GPU_FILE" 2>/dev/null)"
		bat="$(battery_text)"
		echo "${cpu}|${ctemp}|${ram}|${gpu}|${bat}" > "$CACHE.tmp"
		mv "$CACHE.tmp" "$CACHE"
	done
}

sampler &
SAMPLER=$!
trap 'kill $SAMPLER $GPU_READER 2>/dev/null; pkill -P $$ nvidia-smi 2>/dev/null' EXIT
trap 'exit' TERM  # so a kill runs the EXIT cleanup above

# dwm-audio sends USR1 after a volume/device change so the bar redraws
# immediately instead of waiting out the one-second sleep below.
echo $$ > "$PIDFILE"

# Next assignment, points and the focus countdown, written by dwm-school.
SCHOOL_BAR="${XDG_RUNTIME_DIR:-$HOME/.cache}/dwm-school-bar"
SCHOOL_FOCUS="${XDG_RUNTIME_DIR:-$HOME/.cache}/dwm-school-focus"
trap : USR1

while true; do
	IFS='|' read -r cpu ctemp ram gpu bat < "$CACHE" 2>/dev/null
	IFS=',' read -r gpu_util gpu_temp <<< "$gpu"
	clock="$(date '+%a %-I:%M %p')"
	vol="$("$HOME/.local/bin/dwm-audio" status 2>/dev/null)"

	# CPU temp and the GPU block are left out when the hardware has no sensor for them.
	stats="  ${cpu:-0}%"
	[ -n "$ctemp" ] && stats+=" ${ctemp}°"
	[ -n "$gpu_util" ] && stats+=" | 󰪭 ${gpu_util}% ${gpu_temp}°"

	hw=""; read -r hw < "$SCHOOL_BAR" 2>/dev/null
	fend=0; read -r fend _ < "$SCHOOL_FOCUS" 2>/dev/null
	if [ "${fend:-0}" -gt "$EPOCHSECONDS" ] 2>/dev/null; then
		left=$((fend - EPOCHSECONDS))
		printf -v hw '󰔛 %d:%02d | %s' $((left / 60)) $((left % 60)) "$hw"
	fi

	xsetroot -name "${hw:+ $hw |}${stats} |  ${ram:-?}${bat:+ | $bat} | ${vol:- ?} | ${clock} "
	sleep 1 & wait $!
done
