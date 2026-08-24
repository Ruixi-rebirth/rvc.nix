#!/usr/bin/env bash
set -euo pipefail

for required_command in jq pactl systemctl wpctl; do
  if ! command -v "$required_command" >/dev/null; then
    echo "missing live PipeWire test dependency: $required_command" >&2
    exit 1
  fi
done

module_ids=()

cleanup() {
  local index
  for ((index = ${#module_ids[@]} - 1; index >= 0; index--)); do
    pactl unload-module "${module_ids[index]}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT INT TERM

sink_name="rvc_acceptance_out"
source_name="rvc_acceptance_mic"
sink_description="RVC-Acceptance-Output"
source_description="RVC-Acceptance-Microphone"

sink_id="$({
  pactl load-module module-null-sink \
    "sink_name=$sink_name" \
    "sink_properties=device.description=$sink_description"
})"
module_ids+=("$sink_id")

source_id="$({
  pactl load-module module-remap-source \
    "master=$sink_name.monitor" \
    "source_name=$source_name" \
    "source_properties=device.description=$source_description"
})"
module_ids+=("$source_id")

pactl --format=json list sinks | jq --exit-status \
  --arg name "$sink_name" \
  --arg description "$sink_description" '
    .[]
    | select(.name == $name)
    | select(.properties["device.description"] == $description)
  ' >/dev/null

pactl --format=json list sources | jq --exit-status \
  --arg name "$source_name" \
  --arg description "$source_description" '
    .[]
    | select(.name == $name)
    | select(.properties["device.description"] == $description)
  ' >/dev/null

wpctl_output="$(wpctl status)"
grep -F "$sink_description" <<<"$wpctl_output" >/dev/null
grep -F "$source_name" <<<"$wpctl_output" >/dev/null

systemctl --user is-active --quiet pipewire.service
systemctl --user is-active --quiet pipewire-pulse.service
systemctl --user is-active --quiet wireplumber.service

echo "PipeWire virtual microphone acceptance: OK"
