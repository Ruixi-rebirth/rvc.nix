#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /nix/store/...-rvc-*/bin/rvc-web" >&2
  exit 2
fi
for required_command in curl ss; do
  if ! command -v "$required_command" >/dev/null; then
    echo "missing live WebUI test dependency: $required_command" >&2
    exit 1
  fi
done

web_command="$1"
acceptance_root="$(mktemp -d /tmp/rvc-webui-acceptance.XXXXXX)"
web_pid=

cleanup() {
  if [[ -n $web_pid ]] && kill -0 "$web_pid" >/dev/null 2>&1; then
    kill "$web_pid" >/dev/null 2>&1 || true
    wait "$web_pid" >/dev/null 2>&1 || true
  fi
  case "$acceptance_root" in
  /tmp/rvc-webui-acceptance.*) rm -rf -- "$acceptance_root" ;;
  *) echo "refusing unexpected cleanup path: $acceptance_root" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

listen_port=
for candidate_port in $(seq 48650 48750); do
  if ! ss -H -ltn "sport = :$candidate_port" | grep -q .; then
    listen_port="$candidate_port"
    break
  fi
done
if [[ -z $listen_port ]]; then
  echo "no free WebUI acceptance port found" >&2
  exit 1
fi

mkdir -p "$acceptance_root/home"
env \
  HOME="$acceptance_root/home" \
  RVC_CACHE_DIR="$acceptance_root/cache" \
  RVC_CONFIG_DIR="$acceptance_root/config" \
  RVC_DATA_DIR="$acceptance_root/data" \
  XDG_CACHE_HOME="$acceptance_root/xdg-cache" \
  XDG_CONFIG_HOME="$acceptance_root/xdg-config" \
  XDG_DATA_HOME="$acceptance_root/xdg-data" \
  "$web_command" --noautoopen --port "$listen_port" \
  >"$acceptance_root/webui.log" 2>&1 &
web_pid=$!

http_ready=
for _attempt in $(seq 1 120); do
  if ! kill -0 "$web_pid" >/dev/null 2>&1; then
    cat "$acceptance_root/webui.log" >&2
    echo "WebUI exited before accepting connections" >&2
    exit 1
  fi

  if curl --fail --silent --show-error \
    "http://127.0.0.1:$listen_port/" \
    >"$acceptance_root/index.html" 2>/dev/null; then
    http_ready=1
    break
  fi
  sleep 0.5
done

if [[ -z $http_ready ]]; then
  cat "$acceptance_root/webui.log" >&2
  echo "WebUI did not become ready on localhost" >&2
  exit 1
fi

ss -H -ltn "sport = :$listen_port" |
  awk -v port="$listen_port" '
      $4 == "127.0.0.1:" port { found = 1 }
      $4 == "0.0.0.0:" port || $4 == "*:" port { public = 1 }
      END { exit !(found && !public) }
    '
test "$(wc -c <"$acceptance_root/index.html")" -gt 1000
grep -Fi 'gradio' "$acceptance_root/index.html" >/dev/null

echo "RVC WebUI localhost HTTP endpoint: OK $listen_port"
