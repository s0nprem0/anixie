#!/bin/sh
# Forward logind's Lock signal to the shell.
#
# `loginctl lock-session` (and anything else that does the standard thing) asks
# logind to send Lock on the system bus. The lock itself lives in the shell, so
# this small listener turns that one signal into the same IPC call the lock key
# uses. It runs as its own user service so a shell restart does not drop it.
#
# The match includes this session's object path: locking another session on the
# same machine should not lock this one.
set -u

busctl="@BUSCTL@"
dbus_monitor="@DBUS_MONITOR@"
stdbuf="@STDBUF@"
quickshell="@QUICKSHELL@"

session_path=""
if [ -n "${XDG_SESSION_ID:-}" ]; then
  raw=$("$busctl" call org.freedesktop.login1 /org/freedesktop/login1 \
    org.freedesktop.login1.Manager GetSession s "$XDG_SESSION_ID" 2>/dev/null || true)
  session_path=${raw#o \"}
  session_path=${session_path%\"}
fi

rule="type='signal',interface='org.freedesktop.login1.Session',member='Lock'"
if [ -n "$session_path" ]; then
  rule="$rule,path='$session_path'"
fi

# `stdbuf` keeps dbus-monitor line-buffered while it writes into the pipe; an
# inherited block buffer would hold the signal until enough output filled it.
"$stdbuf" -oL "$dbus_monitor" --system "$rule" |
  while IFS= read -r line; do
    case "$line" in
      *"member=Lock"*) "$quickshell" ipc call lock lock >/dev/null 2>&1 || true ;;
    esac
  done
