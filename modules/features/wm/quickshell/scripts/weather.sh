#!/bin/sh
# Current conditions for the bar, printed as the Waybar-style JSON that
# CommandModule reads: {text, tooltip}.
#
# wttr.in geolocates the requestor when no place is named, so there is nothing
# to configure. Both halves come from one request so the label and the tooltip
# always describe the same reading.
#
# Run through `sh` rather than executed, so the file does not need to keep an
# executable bit through the store copy.

set -eu

raw=$(curl -fsS --max-time 5 "https://wttr.in/?format=%t|%C+%w+%h" 2>/dev/null) || {
  printf '%s\n' "Weather unavailable"
  exit 0
}

text=${raw%%|*}
detail=${raw#*|}

# Trim, collapse runs of spaces, drop the leading sign off the temperature, and
# strip quotes that would otherwise break the JSON this prints.
text=$(printf '%s' "$text" | tr -d '"+' | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')
detail=$(printf '%s' "$detail" | tr -d '"' | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')

printf '{"text":"%s","tooltip":"%s"}\n' "$text" "$detail"
