#!/usr/bin/env python3
"""Read-only calendar subscriptions for the shell.

The clock panel asks this for the events in the month it is drawing. A
subscription is an `.ics` URL in ~/.config/anixie/calendar.json:

    {
      "urls": [
        "https://calendar.example.test/private/basic.ics",
        { "name": "Work", "url": "https://example.test/work.ics" }
      ],
      "refreshMinutes": 30
    }

Nothing is written back, and the URL is only ever read from the user's config;
the shell itself never needs the secret. Fetched calendars are cached under
~/.cache/anixie/calendar, keyed by URL hash, so opening the panel is a file read
and a fetch only happens when the cache is older than refreshMinutes.

Output is one JSON object:

    {"configured": true, "events": [...], "warnings": [...]}

Each event carries local-time ISO strings (`start`, `end`), `allDay`, and the
summary and location. An all-day event's `end` is exclusive, as iCalendar
defines it.
"""

import argparse
import datetime as dt
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

try:
    from icalendar import Calendar
    import recurring_ical_events
    from tzlocal import get_localzone
except ImportError as error:  # pragma: no cover - the Nix package provides these
    json.dump(
        {"configured": False, "events": [], "warnings": [f"calendar backend missing: {error}"]},
        sys.stdout,
    )
    sys.exit(0)

LOCAL = get_localzone()
USER_AGENT = "anixie-calendar/1"
TIMEOUT = 10


def config_home() -> str:
    return os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")


def cache_home() -> str:
    return os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")


def config_path() -> str:
    return os.path.join(config_home(), "anixie", "calendar.json")


def load_config() -> tuple[list[tuple[str, str]], int, list[str]]:
    """Return (urls, refreshMinutes, warnings). A missing file is not an error."""
    path = config_path()
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = json.load(handle)
    except FileNotFoundError:
        return [], 30, []
    except (OSError, json.JSONDecodeError) as error:
        return [], 30, [f"could not read {path}: {error}"]

    if not isinstance(raw, dict):
        return [], 30, [f"{path} must contain a JSON object"]

    entries = raw.get("urls")
    if entries is None and raw.get("url"):
        entries = [raw["url"]]
    if not isinstance(entries, list):
        return [], 30, [f"{path} needs a urls array"]

    urls: list[tuple[str, str]] = []
    for item in entries:
        if isinstance(item, str) and item.strip():
            urls.append((item.strip(), ""))
        elif isinstance(item, dict):
            url = str(item.get("url", "")).strip()
            if url:
                urls.append((url, str(item.get("name", "")).strip()))

    try:
        refresh = int(raw.get("refreshMinutes", 30))
    except (TypeError, ValueError):
        refresh = 30
    refresh = max(1, min(refresh, 24 * 60))

    return urls, refresh, []


def cache_path(url: str) -> str:
    digest = hashlib.sha256(url.encode("utf-8")).hexdigest()
    return os.path.join(cache_home(), "anixie", "calendar", digest + ".ics")


def fetch(url: str, refresh_minutes: int, force: bool) -> tuple[str | None, str | None]:
    """Return (ics text, warning). Falls back to the cache if the fetch fails."""
    path = cache_path(url)
    host = urllib.parse.urlsplit(url).hostname or "calendar"

    try:
        age = time.time() - os.stat(path).st_mtime
        if not force and age < refresh_minutes * 60:
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                return handle.read(), None
    except FileNotFoundError:
        pass
    except OSError:
        pass

    try:
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            data = response.read().decode("utf-8", "replace")
    except (urllib.error.URLError, OSError, ValueError) as error:
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                return handle.read(), f"could not refresh {host}; using the cached copy ({error})"
        except OSError:
            return None, f"could not fetch {host}: {error}"

    os.makedirs(os.path.dirname(path), exist_ok=True)
    temp = path + ".tmp"
    with open(temp, "w", encoding="utf-8") as handle:
        handle.write(data)
    os.replace(temp, path)

    return data, None


def as_local(value: dt.date | dt.datetime) -> str:
    if isinstance(value, dt.datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=LOCAL)
        return value.astimezone(LOCAL).isoformat()
    return value.isoformat()


def event_value(component, key: str) -> str:
    value = component.get(key)
    if value is None:
        return ""
    try:
        return str(component.decoded(key))
    except Exception:
        return str(value)


def duration_of(component) -> dt.timedelta | None:
    value = component.get("DURATION")
    if value is None:
        return None
    try:
        duration = value.dt
        return duration if isinstance(duration, dt.timedelta) else None
    except Exception:
        return None


def events_from(ics: str, start: dt.datetime, end: dt.datetime, calendar_name: str) -> list[dict]:
    try:
        calendar = Calendar.from_ical(ics)
    except Exception as error:
        raise ValueError(str(error)) from error

    try:
        occurrences = recurring_ical_events.of(calendar).between(start, end)
    except Exception as error:
        raise ValueError(str(error)) from error

    out = []
    for component in occurrences:
        starts = component.get("DTSTART")
        if starts is None:
            continue

        begin = starts.dt
        all_day = isinstance(begin, dt.date) and not isinstance(begin, dt.datetime)

        ends = component.get("DTEND")
        finish = ends.dt if ends is not None else None

        if finish is None:
            duration = duration_of(component)
            if duration is not None:
                finish = begin + duration
            elif all_day:
                finish = begin + dt.timedelta(days=1)

        out.append(
            {
                "summary": event_value(component, "SUMMARY") or "(no title)",
                "location": event_value(component, "LOCATION"),
                "start": as_local(begin),
                "end": as_local(finish) if finish is not None else "",
                "allDay": all_day,
                "calendar": calendar_name,
            }
        )

    return out


def main() -> int:
    parser = argparse.ArgumentParser(prog="calendar-events")
    sub = parser.add_subparsers(dest="command", required=True)

    listing = sub.add_parser("list", help="Events in a date range, as JSON")
    listing.add_argument("--from", dest="date_from", required=True, help="YYYY-MM-DD")
    listing.add_argument("--to", dest="date_to", required=True, help="YYYY-MM-DD (inclusive)")
    listing.add_argument("--refresh", action="store_true", help="Ignore the cache")

    args = parser.parse_args()

    if args.command != "list":
        parser.error(f"unknown command {args.command}")

    try:
        date_from = dt.date.fromisoformat(args.date_from)
        date_to = dt.date.fromisoformat(args.date_to)
    except ValueError as error:
        print(f"calendar-events: {error}", file=sys.stderr)
        return 2

    if date_to < date_from:
        date_from, date_to = date_to, date_from

    urls, refresh, warnings = load_config()
    configured = bool(urls)

    # Local midnight to the end of the last requested day. An event that starts
    # at 23:00 on the last day still belongs in the month being drawn.
    start = dt.datetime.combine(date_from, dt.time.min, LOCAL)
    end = dt.datetime.combine(date_to + dt.timedelta(days=1), dt.time.min, LOCAL)

    events = []
    for url, name in urls:
        ics, warning = fetch(url, refresh, args.refresh)
        if warning:
            warnings.append(warning)
        if not ics:
            continue
        try:
            events.extend(events_from(ics, start, end, name))
        except ValueError as error:
            host = urllib.parse.urlsplit(url).hostname or "calendar"
            warnings.append(f"could not parse {host}: {error}")

    events.sort(key=lambda item: (item["start"], item["summary"]))

    json.dump(
        {"configured": configured, "events": events, "warnings": warnings},
        sys.stdout,
        ensure_ascii=False,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
