#!/usr/bin/env bash
set -euo pipefail

# End-to-end acceptance test for the realtime GUI conversion path:
# launch the real GUI, click "开始音频转换" with xdotool, and verify that the
# caller-selected input and the virtual output survive stream startup.

if [[ $# -ne 5 ]]; then
  echo "usage: $0 RVC_REALTIME MODEL.pth INDEX.index HOST_API INPUT_DEVICE" >&2
  exit 2
fi

for required_command in xdotool xwininfo; do
  if ! command -v "$required_command" >/dev/null; then
    echo "missing live GUI test dependency: $required_command" >&2
    exit 1
  fi
done

realtime_command="$1"
model_path="$(realpath -- "$2")"
index_path="$(realpath -- "$3")"
host_api="$4"
input_device="$5"
acceptance_root="$(mktemp -d /tmp/rvc-gui-click.XXXXXX)"
gui_pid=

cleanup() {
  if [[ -n $gui_pid ]] && kill -0 "$gui_pid" >/dev/null 2>&1; then
    kill "$gui_pid" >/dev/null 2>&1 || true
    wait "$gui_pid" >/dev/null 2>&1 || true
  fi
  case "$acceptance_root" in
  /tmp/rvc-gui-click.*) rm -rf -- "$acceptance_root" ;;
  *) echo "refusing unexpected cleanup path: $acceptance_root" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

mkdir -p "$acceptance_root/home" "$acceptance_root/config"
# Seed the saved configuration with the model/index paths so that clicking
# start never triggers the modal "please select a file" popups.
cat >"$acceptance_root/config/realtime.json" <<EOF
{"pth_path": "$model_path", "index_path": "$index_path", "sg_hostapi": "$host_api", "sg_input_device": "$input_device", "sg_output_device": "RVC-Output", "sr_type": "sr_model", "threhold": -60, "pitch": 0, "formant": 0.0, "rms_mix_rate": 0.0, "index_rate": 0.0, "block_time": 0.25, "crossfade_length": 0.05, "extra_time": 2.5, "f0method": "rmvpe"}
EOF

env \
  HOME="$acceptance_root/home" \
  RVC_CACHE_DIR="$acceptance_root/cache" \
  RVC_CONFIG_DIR="$acceptance_root/config" \
  RVC_DATA_DIR="$acceptance_root/data" \
  XDG_CACHE_HOME="$acceptance_root/xdg-cache" \
  XDG_CONFIG_HOME="$acceptance_root/xdg-config" \
  XDG_DATA_HOME="$acceptance_root/xdg-data" \
  "$realtime_command" \
  >"$acceptance_root/realtime.log" 2>&1 &
gui_pid=$!

window_id=
for _attempt in $(seq 1 60); do
  if ! kill -0 "$gui_pid" >/dev/null 2>&1; then
    cat "$acceptance_root/realtime.log" >&2
    echo "realtime GUI exited before creating its window" >&2
    exit 1
  fi
  window_id="$(xdotool search --name '^RVC' 2>/dev/null | head -1 || true)"
  if [[ -n $window_id ]]; then
    break
  fi
  sleep 0.5
done

if [[ -z $window_id ]]; then
  cat "$acceptance_root/realtime.log" >&2
  echo "realtime GUI window was not found" >&2
  exit 1
fi

# The start button is the leftmost widget of the bottom row.
window_x="$(xdotool getwindowgeometry --shell "$window_id" | sed -n 's/^X=//p')"
window_y="$(xdotool getwindowgeometry --shell "$window_id" | sed -n 's/^Y=//p')"
window_height="$(xdotool getwindowgeometry --shell "$window_id" | sed -n 's/^HEIGHT=//p')"
xdotool mousemove $((window_x + 60)) $((window_y + window_height - 20)) click 1

for _attempt in $(seq 1 120); do
  if grep -F 'RVC-Output' "$acceptance_root/realtime.log" >/dev/null 2>&1 &&
    grep -F 'CUDA Graph' "$acceptance_root/realtime.log" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$gui_pid" >/dev/null 2>&1; then
    cat "$acceptance_root/realtime.log" >&2
    echo "realtime GUI died while starting conversion" >&2
    exit 1
  fi
  sleep 0.5
done

grep -F 'RVC-Output' "$acceptance_root/realtime.log" >/dev/null
grep -F "$input_device" "$acceptance_root/realtime.log" >/dev/null

# The regression died immediately at stream start; surviving this long means
# the stream opened and the conversion callback is running.
sleep 15
if ! kill -0 "$gui_pid" >/dev/null 2>&1; then
  cat "$acceptance_root/realtime.log" >&2
  echo "realtime GUI was killed after starting conversion" >&2
  exit 1
fi

echo "RVC realtime click-to-convert acceptance: OK"
