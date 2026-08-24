#!/usr/bin/env bash
set -euo pipefail

if (($# != 3)); then
  echo "usage: $0 PACKAGE CHECKPOINT EXPECTED_DEVICE" >&2
  exit 2
fi

package=$1
checkpoint=$2
expected_device=$3

case "$expected_device" in
cpu | cuda) ;;
*)
  echo "EXPECTED_DEVICE must be cpu or cuda" >&2
  exit 2
  ;;
esac

if [[ ! -x "$package/bin/rvc-realtime" ]]; then
  echo "missing rvc-realtime in package: $package" >&2
  exit 1
fi
if [[ ! -f $checkpoint || ${checkpoint##*.} != pth ]]; then
  echo "checkpoint must be an existing .pth file" >&2
  exit 1
fi

# The package ships the multi-mode launcher next to its entry points; the
# launcher's `env` mode reports the resolved source tree and Python
# environment, so nothing here depends on generated script internals.
launcher_script="$package/bin/rvc-launcher-$expected_device"
if [[ ! -x $launcher_script ]]; then
  echo "missing rvc-launcher-$expected_device in package: $package" >&2
  exit 1
fi
readarray -t launcher_env < <("$launcher_script" env)
source_dir="${launcher_env[0]:-}"
python_bin="${launcher_env[1]:-}"
if [[ -z $source_dir || -z $python_bin ]]; then
  echo "the launcher env mode did not report its paths" >&2
  exit 1
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/rvc-realtime-e2e.XXXXXX")
cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

mkdir -p \
  "$test_root/home" \
  "$test_root/data/assets/weights" \
  "$test_root/config" \
  "$test_root/cache"
cp -- "$checkpoint" "$test_root/data/assets/weights/acceptance.pth"

export HOME="$test_root/home"
export RVC_DATA_DIR="$test_root/data"
export RVC_CONFIG_DIR="$test_root/config"
export RVC_CACHE_DIR="$test_root/cache"
export PYTHONPATH="$source_dir"

if [[ $expected_device == "cuda" ]]; then
  export RVC_REQUIRE_CUDA=1
  export LD_LIBRARY_PATH="${RVC_DRIVER_LIBRARY_PATH:-/run/opengl-driver/lib}"
else
  unset LD_LIBRARY_PATH
fi

# The launcher populates pinned model assets into the isolated data root.
"$package/bin/rvc-doctor" >/dev/null

forward_script=$(readlink -f "${BASH_SOURCE[0]%/*}/realtime_infer_forward.py")
(
  cd "$test_root/data"
  "$python_bin" -P \
    "$forward_script" \
    "$test_root/data/assets/weights/acceptance.pth" \
    "$expected_device"
)

printf 'RVC realtime inference end-to-end: OK %s\n' "$expected_device"
