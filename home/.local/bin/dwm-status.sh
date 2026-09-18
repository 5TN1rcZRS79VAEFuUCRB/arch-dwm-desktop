#!/usr/bin/env bash
#
# dwm status bar: CPU/GPU usage, CPU/GPU temp, RAM usage, volume, clock.
# Sets the root window name, which dwm displays on the right side of its bar.
#
# The clock ticks every second; the heavier stats (CPU/GPU/RAM) are sampled
# in the background every 2s and cached, so the clock never waits on them.

CACHE=/tmp/dwm-status-cache

cpu_usage() {
	read -r _ a b c idle _ < /proc/stat
	total1=$((a + b + c + idle))
	idle1=$idle
	sleep 0.5
	read -r _ a b c idle _ < /proc/stat
	total2=$((a + b + c + idle))
	idle2=$idle
	total_diff=$((total2 - total1))
	idle_diff=$((idle2 - idle1))
	if [ "$total_diff" -gt 0 ]; then
		echo $(((100 * (total_diff - idle_diff)) / total_diff))
	else
		echo 0
	fi
}

# Intel reports "Package id 0", AMD reports Tctl/Tdie; prints nothing if neither exists.
cpu_temp() {
	sensors 2>/dev/null | awk '
		/^Package id 0:/ { t = $4 }
		/^(Tctl|Tdie):/  { if (t == "") t = $2 }
		END { gsub(/\+|°C/, "", t); print t }'
}

ram_usage() {
	free -h | awk '/^Mem:/{print $3"/"$2}'
}

gpu_stats() {
	nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' '
}

sampler() {
	while true; do
		cpu="$(cpu_usage)"
		ctemp="$(cpu_temp)"
		ram="$(ram_usage)"
		gpu="$(gpu_stats)"
		echo "${cpu}|${ctemp}|${ram}|${gpu}" > "$CACHE.tmp"
		mv "$CACHE.tmp" "$CACHE"
	done
}

sampler &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null' EXIT

# dwm-audio sends USR1 after a volume/device change so the bar redraws
# immediately instead of waiting out the one-second sleep below.
echo $$ > "${XDG_RUNTIME_DIR:-/tmp}/dwm-status.pid"
trap : USR1

while true; do
	IFS='|' read -r cpu ctemp ram gpu < "$CACHE" 2>/dev/null
	IFS=',' read -r gpu_util gpu_temp <<< "$gpu"
	clock="$(date '+%a %b %d %I:%M:%S %p')"
	vol="$("$HOME/.local/bin/dwm-audio" status 2>/dev/null)"

	# CPU temp and the GPU block are left out when the hardware has no sensor for them.
	stats=" CPU ${cpu:-0}%"
	[ -n "$ctemp" ] && stats+=" ${ctemp}C"
	[ -n "$gpu_util" ] && stats+=" | GPU ${gpu_util}% ${gpu_temp}C"

	xsetroot -name "${stats} | RAM ${ram:-?} | ${vol:-VOL ?} | ${clock} "
	sleep 1 & wait $!
done
