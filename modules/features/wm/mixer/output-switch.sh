#!/bin/sh

# Cycle to the next available output and take what is playing with it.
#
# The sink list is read as JSON rather than parsed out of the human-readable
# listing, whose columns are localized and whose wording for an unavailable
# port moves between versions. A sink with no ports at all — a loopback, an
# EasyEffects sink — is always offered; a device whose every port reports itself
# unavailable, such as an HDMI output with nothing plugged in, is skipped rather
# than selected into silence.
set -eu

# The filter has to be the one the list is built with, not a second copy written
# out at each use: the count and the index both have to describe the same list,
# or the modulo lands on a sink the index did not count.
available='[.[] | select((.ports | length) == 0 or ([.ports[]? | .availability != "not available"] | any))]'

sinks=$(@PACTL@ -f json list sinks | @JQ@ "$available")
count=$(printf '%s' "$sinks" | @JQ@ 'length')

if [ "$count" -eq 0 ]; then
  @NOTIFY_SEND@ -a Audio "No audio output" || true
  exit 1
fi

current=$(@PACTL@ get-default-sink 2>/dev/null || true)
index=$(printf '%s' "$sinks" | @JQ@ --arg name "$current" 'map(.name) | index($name)')
if [ "$index" = "null" ]; then
  index=-1
fi
next=$(( (index + 1) % count ))

row=$(printf '%s' "$sinks" | @JQ@ -c --argjson next "$next" '.[$next]')
name=$(printf '%s' "$row" | @JQ@ -r '.name')
id=$(printf '%s' "$row" | @JQ@ -r '.index')
description=$(printf '%s' "$row" | @JQ@ -r '.description // .properties."device.description" // .name')

@OUTPUT_SET@ "$id" "$name"

@NOTIFY_SEND@ -a Audio "Audio output" "$description" || true
