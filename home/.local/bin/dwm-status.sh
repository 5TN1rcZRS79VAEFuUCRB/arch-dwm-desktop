#!/usr/bin/env bash
#
# dwm status bar: CPU/GPU usage, CPU/GPU temp, RAM usage, volume, clock.
# Sets the root window name, which dwm displays on the right side of its bar.
#
# The clock ticks every second; the heavier stats (CPU/GPU/RAM) are sampled
# in the background every 2s and cached, so the clock never waits on them.

# Not a fixed name in world-writable /tmp: another local user could pre-create it as a symlink.
CACHE="${XDG_RUNTIME_DIR:-$HOME/.cache}/dwm-status-cache"
mkdir -p "$(dirname "$CACHE")"

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

# GPU load and temperature (NVIDIA only; nothing is shown without nvidia-smi). One long-lived
# nvidia-smi prints a sample every 2 s and we read the latest line. Starting a new nvidia-smi
# twice a second was heavy and clashed with monitor sleep/wake, so do not go back to that.
# Set DWM_STATUS_GPU=0 (e.g. in ~/.xinitrc) to turn the readout off.
GPU_FILE="${XDG_RUNTIME_DIR:-$HOME/.cache}/dwm-status-gpu"
rm -f "$GPU_FILE" "$GPU_FILE.tmp"
GPU_READER=
if [ "${DWM_STATUS_GPU:-1}" = 1 ] && command -v nvidia-smi >/dev/null; then
	nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits -l 2 2>/dev/null |
		while IFS= read -r line; do
			printf '%s\n' "${line//[[:space:]]/}" > "$GPU_FILE.tmp" && mv "$GPU_FILE.tmp" "$GPU_FILE"
		done &
	GPU_READER=$!
fi
gpu_stats() {
	[ -r "$GPU_FILE" ] && cat "$GPU_FILE"
}

sampler() {
	while true; do
		cpu="$(cpu_usage)"
		ctemp="$(cpu_temp)"
		ram="$(ram_usage)"
		gpu="$(gpu_stats)"
		bat="$(battery_text)"
		echo "${cpu}|${ctemp}|${ram}|${gpu}|${bat}" > "$CACHE.tmp"
		mv "$CACHE.tmp" "$CACHE"
	done
}

sampler &
SAMPLER=$!
trap 'kill $SAMPLER $GPU_READER 2>/dev/null; pkill -P $$ nvidia-smi 2>/dev/null' EXIT

# dwm-audio sends USR1 after a volume/device change so the bar redraws
# immediately instead of waiting out the one-second sleep below.
echo $$ > "${XDG_RUNTIME_DIR:-/tmp}/dwm-status.pid"
trap : USR1

while true; do
	IFS='|' read -r cpu ctemp ram gpu bat < "$CACHE" 2>/dev/null
	IFS=',' read -r gpu_util gpu_temp <<< "$gpu"
	clock="$(date '+%a %b %d %I:%M:%S %p')"
	vol="$("$HOME/.local/bin/dwm-audio" status 2>/dev/null)"

	# CPU temp and the GPU block are left out when the hardware has no sensor for them.
	stats=" CPU ${cpu:-0}%"
	[ -n "$ctemp" ] && stats+=" ${ctemp}C"
	[ -n "$gpu_util" ] && stats+=" | GPU ${gpu_util}% ${gpu_temp}C"

	xsetroot -name "${stats} | RAM ${ram:-?}${bat:+ | $bat} | ${vol:-VOL ?} | ${clock} "
	sleep 1 & wait $!
done
