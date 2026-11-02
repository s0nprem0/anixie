{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.calendar;

  # The backend for the clock panel's subscription view: iCalendar parsing and
  # recurrence expansion, with the local time zone from the system.
  python = pkgs.python3.withPackages (
    ps: with ps; [
      icalendar
      recurring-ical-events
      tzlocal
    ]
  );

  # A shebang rather than a wrapper: the script is stdlib Python plus the three
  # libraries above, and writeTextFile keeps the executable bit and the path
  # short enough for the kernel's shebang limit.
  calendarEvents = pkgs.writeTextFile {
    name = "calendar-events";
    destination = "/bin/calendar-events";
    executable = true;
    text = builtins.replaceStrings [ "#!/usr/bin/env python3" ] [ "#!${python}/bin/python3" ] (
      builtins.readFile ./calendar-events.py
    );
  };
in
{
  options.anixie.wm.calendar = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the clock panel can show read-only calendar subscriptions.";
    };

    bin = lib.mkOption {
      type = lib.types.str;
      internal = true;
      readOnly = true;
      default = if cfg.enable then "${calendarEvents}/bin/calendar-events" else "";
      description = "The calendar-events command the shell calls, or an empty string when disabled.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ calendarEvents ];
  };
}
