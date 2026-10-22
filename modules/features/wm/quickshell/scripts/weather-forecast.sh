#!/bin/sh
# Weather: current conditions for the bar, and a three-day forecast for the panel.
#
#   weather [bar] [PLACE]     print the bar's JSON: {text, tooltip}
#   weather forecast [PLACE]  print the forecast as JSON, for the panel
#
# PLACE is a city, a postcode, or "LAT,LON" as wttr.in understands them. Empty or
# omitted means wttr.in geolocates the requestor by IP, which is the default when
# the weather widget has no `location` setting. The bar half asks for the three
# values it needs as a one-line format; the forecast half asks for the full j1
# document and trims it here rather than shipping 40KB of JSON through a panel to
# draw six numbers.
#
# Both come from one request so the bar's reading and the panel's forecast describe
# the same moment, and neither is cached on disk — a stale forecast is worse than
# no forecast, and wttr.in answers in well under a second.

set -eu

days=3
location=${2:-}

fetch() {
  # curl and jq are on PATH; the scripts/ directory is not a place to hard-code
  # store paths, since it ships as plain files rather than built scripts.
  #
  # The place is encoded rather than interpolated as-is: a city with a space or a
  # coordinate pair with a comma would otherwise change the URL's path or query.
  # Leaving PLACE empty keeps wttr.in's IP lookup.
  if [ -n "$location" ]; then
    place=$(printf '%s' "$location" | jq -sRr @uri)
    curl -fsS --max-time 8 "https://wttr.in/${place}?format=$1" 2>/dev/null
  else
    curl -fsS --max-time 8 "https://wttr.in/?format=$1" 2>/dev/null
  fi
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