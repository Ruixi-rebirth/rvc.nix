#!/usr/bin/env bash

set -euo pipefail

if (($# != 4)); then
  echo "usage: $0 PACKAGE CHECKPOINT INPUT EXPECTED_DEVICE" >&2
  exit 2
fi

package=$1
checkpoint=$2
input=$3
expected_device=$4

case "$expected_device" in
cpu | cuda) ;;
*)
  echo "EXPECTED_DEVICE must be cpu or cuda" >&2
  exit 2
  ;;
esac

for executable in ffmpeg ffprobe; do
  if ! command -v "$executable" >/dev/null; then
    echo "$executable is required" >&2
    exit 1
  fi
done

if [[ ! -x "$package/bin/rvc-cli" ]]; then
  echo "missing rvc-cli in package: $package" >&2
  exit 1
fi
if [[ ! -f $checkpoint || ${checkpoint##*.} != pth ]]; then
  echo "checkpoint must be an existing .pth file" >&2
  exit 1
fi
if [[ ! -f $input ]]; then
  echo "input audio does not exist: $input" >&2
  exit 1
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/rvc-cli-e2e.XXXXXX")
cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

mkdir -p \
  "$test_root/home" \
  "$test_root/data/assets/weights" \
  "$test_root/config" \
  "$test_root/cache" \
  "$test_root/io"
cp -- "$checkpoint" "$test_root/data/assets/weights/acceptance.pth"

HOME="$test_root/home" \
  RVC_DATA_DIR="$test_root/data" \
  RVC_CONFIG_DIR="$test_root/config" \
  RVC_CACHE_DIR="$test_root/cache" \
  "$package/bin/rvc-cli" \
  --model acceptance.pth \
  --input "$input" \
  --output "$test_root/io/output.wav" \
  --f0-method rmvpe \
  --index-rate 0 \
  --overwrite \
  2>&1 | tee "$test_root/cli.log"

case "$expected_device" in
cpu)
  grep -Eq '^Current device: cpu([[:space:]]|$)' "$test_root/cli.log"
  ;;
cuda)
  grep -Eq '^Current device: cuda(:[[:digit:]]+)?([[:space:]]|$)' \
    "$test_root/cli.log"
  ;;
esac

probe=$(
  ffprobe -v error \
    -select_streams a:0 \
    -show_entries stream=codec_name,sample_rate,channels \
    -of csv=p=0 \
    "$test_root/io/output.wav"
)
if [[ $probe != "pcm_s16le,48000,1" ]]; then
  echo "unexpected output stream: $probe" >&2
  exit 1
fi

duration=$(
  ffprobe -v error \
    -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 \
    "$test_root/io/output.wav"
)
awk -v duration="$duration" 'BEGIN { exit !(duration > 0) }'

ffmpeg -hide_banner -nostats \
  -i "$test_root/io/output.wav" \
  -af volumedetect \
  -f null - \
  2>"$test_root/volume.log"
if ! grep -Eq 'max_volume: -?[[:digit:]]' "$test_root/volume.log"; then
  echo "output is silent or has no measurable peak" >&2
  exit 1
fi

printf 'RVC CLI end-to-end: OK %s %s seconds %s\n' \
  "$expected_device" "$duration" "$probe"
