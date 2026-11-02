#!/bin/sh

# Point the default output at a sink and take the streams that are already
# playing with it.
#
# Usage: audio-output-set <node-id> <sink-name>
#
# Both identifiers are needed. PipeWire and WirePlumber select by node id; the
# PulseAudio compatibility layer, which is what can move a stream that is
# already open, names sinks. And a new default only captures streams created
# after it changes, so an application that is already playing would keep going
# to the old output until it was restarted.
set -eu

node_id=${1:?usage: audio-output-set <node-id> <sink-name>}
sink_name=${2:?usage: audio-output-set <node-id> <sink-name>}

@WPCTL@ set-default "$node_id" >/dev/null
@PACTL@ set-default-sink "$sink_name" >/dev/null 2>&1 || true

# Move only real application streams. A filter-chain's own output is a sink
# input too but carries no application.name, and moving it would rewire the
# processing rather than an application — onto headphones, or into its own
# virtual sink, which is a cycle. EasyEffects' output has to stay put for the
# same reason.
@PACTL@ -f json list sink-inputs 2>/dev/null |
  @JQ@ -r '.[] | select((.properties["application.name"] // "") != "") | select(.properties["application.name"] != "EasyEffects") | .index' |
  while read -r input; do
    if [ -n "$input" ]; then
      @PACTL@ move-sink-input "$input" "$sink_name" >/dev/null 2>&1 || true
    fi
  done
