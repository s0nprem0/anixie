#!/bin/sh
# Forward logind's Lock and PrepareForSleep signals to the shell.
#
# `loginctl lock-session` (and anything else that does the standard thing) asks
# logind to send Lock on the system bus. The lock itself lives in the shell, so
# this small listener turns that one signal into the same IPC call the lock key
# uses. It runs as its own user service so a shell restart does not drop it.
#
# PrepareForSleep is what used to be hypridle's only remaining job: lock before
# the machine suspends, and turn the panel back on when it resumes. Doing it here
# keeps the whole idle/suspend path in one place and removes a second daemon.
#
# The Lock match includes this session's object path: locking another session on
# the same machine should not lock this one. PrepareForSleep is machine-wide, so
# it has no path filter.
set -u

busctl="@BUSCTL@"
dbus_monitor="@DBUS_MONITOR@"
stdbuf="@STDBUF@"
quickshell="@QUICKSHELL@"
hyprctl="@HYPRCTL@"

session_path=""
if [ -n "${XDG_SESSION_ID:-}" ]; then
  raw=$("$busctl" call org.freedesktop.login1 /org/freedesktop/login1 \
    org.freedesktop.login1.Manager GetSession s "$XDG_SESSION_ID" 2>/dev/null || true)
  session_path=${raw#o \"}
  session_path=${session_path%\"}
fi

lock_rule="type='signal',interface='org.freedesktop.login1.Session',member='Lock'"
if [ -n "$session_path" ]; then
  lock_rule="$lock_rule,path='$session_path'"
fi
sleep_rule="type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"

lock() {
  "$quickshell" ipc call lock lock >/dev/null 2>&1 || true
}

# Hyprland does not always bring the panel back on its own after resume. A
# plain "on" is not enough when the panel is stuck dark; cycling the DPMS state
# forces the modeset that repaints it.
resume() {
  "$hyprctl" dispatch 'hl.dsp.dpms({action = "off"})' >/dev/null 2>&1 || true
  sleep 0.2
  "$hyprctl" dispatch 'hl.dsp.dpms({action = "on"})' >/dev/null 2>&1 || true
}

# `stdbuf` keeps dbus-monitor line-buffered while it writes into the pipe; an
# inherited block buffer would hold the signal until enough output filled it.
#
# The signal header and its boolean argument arrive on separate lines, so the
# header records that the next boolean belongs to PrepareForSleep.
pending=""
"$stdbuf" -oL "$dbus_monitor" --system "$lock_rule" "$sleep_rule" |
  while IFS= read -r line; do
    case "$line" in
      *"member=Lock"*)
        lock
        pending=""
        ;;
      *"member=PrepareForSleep"*) pending="sleep" ;;
      *"boolean true"*)
        [ "$pending" = sleep ] && lock
        pending=""
        ;;
      *"boolean false"*)
        [ "$pending" = sleep ] && resume
        pending=""
        ;;
      *) pending="" ;;
    esac
  done
