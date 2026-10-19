#!/bin/sh
# Weather: current conditions for the bar, and a three-day forecast for the panel.
#
#   weather            print the bar's JSON: {text, tooltip}
#   weather forecast   print the forecast as JSON, for the panel
#
# wttr.in geolocates the requestor when no place is named, so there is nothing to
# configure. The bar half asks for the three values it needs as a one-line format;
# the forecast half asks for the full j1 document and trims it here rather than
# shipping 40KB of JSON through a panel to draw six numbers.
#
# Both come from one request so the bar's reading and the panel's forecast describe
# the same moment, and neither is cached on disk — a stale forecast is worse than
# no forecast, and wttr.in answers in well under a second.

set -eu

days=3

fetch() {
  # curl and jq are on PATH; the scripts/ directory is not a place to hard-code
  # store paths, since it ships as plain files rather than built scripts.
  curl -fsS --max-time 8 "https://wttr.in/?format=$1" 2>/dev/null
}

bar() {
  raw=$(fetch "%t|%C+%w+%h") || {
    printf '{"text":"--","tooltip":"Weather unavailable"}\n'
    exit 0
  }

  text=${raw%%|*}
  detail=${raw#*|}

  # Trim, collapse runs of spaces, drop the leading sign off the temperature, and
  # strip quotes that would otherwise break the JSON this prints.
  text=$(printf '%s' "$text" | tr -d '"+' | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')
  detail=$(printf '%s' "$detail" | tr -d '"' | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')

  printf '{"text":"%s","tooltip":"%s"}\n' "$text" "$detail"
}

forecast() {
  raw=$(fetch "j1") || {
    printf '{"ok":false}\n'
    exit 0
  }

  printf '%s' "$raw" | jq -c --argjson days "$days" '
    {
      ok: true,
      area: (.nearest_area[0].areaName[0].value // ""),
      current: {
        temp: (.current_condition[0].temp_C // ""),
        desc: (.current_condition[0].weatherDesc[0].value // ""),
      },
      days: [
        .weather[0:$days][]
        | {
            date: .date,
            hi: .maxtempC,
            lo: .mintempC,
            # One description for the day, taken from a middling hour. The first
            # hour is overnight and the last is near dawn the next morning, so
            # either end describes the wrong half of the day.
            desc: (.hourly[4].weatherDesc[0].value // ""),
            chance: (.hourly[4].chanceofrain // "0"),
          }
      ],
    }' 2>/dev/null || printf '{"ok":false}\n'
}

case "${1:-bar}" in
  bar | "") bar ;;
  forecast) forecast ;;
  *)
    printf 'weather: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac