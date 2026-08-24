#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /nix/store/...-rvc-*/bin/rvc-realtime" >&2
  exit 2
fi
if ! command -v xwininfo >/dev/null; then
  echo "missing live GUI test dependency: xwininfo" >&2
  exit 1
fi

realtime_command="$1"
acceptance_root="$(mktemp -d /tmp/rvc-gui-acceptance.XXXXXX)"
gui_pid=

cleanup() {
  if [[ -n $gui_pid ]] && kill -0 "$gui_pid" >/dev/null 2>&1; then
    kill "$gui_pid" >/dev/null 2>&1 || true
    wait "$gui_pid" >/dev/null 2>&1 || true
  fi
  case "$acceptance_root" in
  /tmp/rvc-gui-acceptance.*) rm -rf -- "$acceptance_root" ;;
  *) echo "refusing unexpected cleanup path: $acceptance_root" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

mkdir -p "$acceptance_root/home"
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

window_found=
for _attempt in $(seq 1 60); do
  if ! kill -0 "$gui_pid" >/dev/null 2>&1; then
    cat "$acceptance_root/realtime.log" >&2
    echo "realtime GUI exited before creating its window" >&2
    exit 1
  fi

  if xwininfo -root -tree 2>/dev/null | grep -F '"RVC - GUI"' >/dev/null; then
    window_found=1
    break
  fi
  sleep 0.5
done

if [[ -z $window_found ]]; then
  cat "$acceptance_root/realtime.log" >&2
  echo "RVC realtime window was not visible through XWayland" >&2
  exit 1
fi

echo "RVC realtime XWayland window: OK"
