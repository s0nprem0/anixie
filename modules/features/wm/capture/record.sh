#!/bin/bash
# Screen recording, on gpu-screen-recorder.
#
#   record                      start one, or stop the one that is running
#   record --status             exit 0 while a recording this shell started is up
#   record --stop               stop it, tidy the file, and announce it
#   record --fullscreen         record the focused monitor, no picker
#   record --audio=WHICH        none | desktop | desktop+mic | desktop+mic+webcam
#   record --webcam-device=DEV  which camera, when the webcam is in the mix
#   record --webcam-size=SIZE   small | medium | large
#
# With no --audio the audio question is asked first, through the shell's picker:
# none, desktop,
# desktop and microphone, or desktop, microphone and webcam. The webcam entry only
# appears when a camera is actually attached.
#
# The picker is the screenshot picker, in `--match-monitor` form, so a whole-monitor
# pick records the monitor by name at native resolution and anything else records as
# a region. That keeps one set of keys for both capture paths.
#
# While a recording runs, `record` stops it, the bar indicator stops it, and
# `record --stop` stops it. All three go through the same lock.
#
# Files land in $SCREENRECORD_DIR, default ~/Videos, named
# screenrecording-YYYY-MM-DD_HH-MM-SS.mp4.

set -uo pipefail

shot_pick="@SHOT_PICK@"
record_process="@RECORD_PROCESS@"
webcam_overlay="@WEBCAM_OVERLAY@"
gsr="@GSR@"
ffmpeg="@FFMPEG@"
ffprobe="@FFPROBE@"
notify_send="@NOTIFY_SEND@"
notify_send_raw="@NOTIFY_SEND_RAW@"
mpv="@MPV@"
setsid="@SETSID@"

# Tell the shell whether a recording is running, for the bar's record dot.
#
# The dot used to ask: `record --status` every 1.5 seconds, which meant parsing
# this whole file twice a second to answer a question whose answer changes twice
# a day. The shell holds the state now and this pushes it in, the same way
# `toggle dnd` tells the shell about the notification state.
#
# Best effort on purpose. A shell that is not running is not a reason to fail a
# recording — and `|| true` is what says so, since `set -uo pipefail` would
# otherwise carry the failure out of this function.
shell_recording() {
  @QUICKSHELL@ ipc call capture recording "$1" >/dev/null 2>&1 || true
}

# Private to the user. XDG_RUNTIME_DIR is 0700 and lives for the session, which is
# what a recording's pid and filename want. The fallback is the state directory
# rather than /tmp: these paths are read back and used as paths — the filename is
# handed to ffmpeg and `mv`, the region to the overlay — so a name any other local
# account could create first is a name that account can point wherever it likes.
#
# The /anixie is outside the substitution on purpose. Inside it — as in
# `${XDG_RUNTIME_DIR:-$HOME/.local/state/anixie}` — the suffix would only apply
# when XDG_RUNTIME_DIR is unset, and the session would drop its files straight
# into /run/user/1000 beside the Wayland sockets.
runtime_dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/anixie"
out_dir="${SCREENRECORD_DIR:-${XDG_VIDEOS_DIR:-$HOME/Videos}}"
log_file="${SCREENRECORD_LOG:-/dev/null}"

pid_file="$runtime_dir/anixie-record.pid"
name_file="$runtime_dir/anixie-record.file"
region_file="$runtime_dir/anixie-record.region"
lock_file="$runtime_dir/anixie-record.lock"
starting_file="$runtime_dir/anixie-record.starting"
cancel_file="$runtime_dir/anixie-record.cancel"

# How long gpu-screen-recorder may take to create its output file before the
# start is treated as failed. 15s at 0.2s a tick: generous, because the first
# frames include the GPU encoder's own warm-up.
ready_ticks=75

action="toggle"
fullscreen="false"
audio=""
webcam_size="medium"
webcam_device=""

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

notify() {
  # $1 urgency, $2 title, $3 body, rest: extra notify-send arguments.
  urgency="$1"
  title="$2"
  body="$3"
  shift 3
  "$notify_send" -u "$urgency" -a record -G f03d "$@" "$title" "$body" >/dev/null 2>&1
}

# Announce a finished recording: the thumbnail as the notification's image, and a
# Play button on it.
#
# This one uses notify-send directly rather than `notify`: the wait-and-print
# action protocol is not part of the wrapper's smaller interface, and the image
# hint already gives the card what a glyph would.
#
# Run in the background because `-A` implies `--wait` — notify-send stays up until
# the notification is dismissed or the button is pressed, and by then the file is
# already saved and there is nothing left to wait for. The chosen action is printed
# on stdout, which is where the play comes from. 9>&- so it does not keep the
# toggle's lock held after the script exits.
announce_saved() {
  file="$1"
  preview="$2"

  args=(-a record -u normal -t 10000 -G f03d)
  if [ -n "$preview" ] && [ -f "$preview" ]; then
    args+=(-h "string:image-path:$preview")
  fi
  args+=(-A "default=Play")

  {
    "$notify_send_raw" "${args[@]}" "Recording saved" "$file" 2>/dev/null |
      while read -r chosen; do
        if [ "$chosen" = "default" ]; then
          "$setsid" -f "$mpv" -- "$file" >/dev/null 2>&1
        fi
      done
  } 9>&- &
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --status) action="status" ;;
    --stop) action="stop" ;;
    --fullscreen) fullscreen="true" ;;
    --audio=*)
      audio="${1#*=}"
      case "$audio" in
        none | desktop | desktop+mic | desktop+mic+webcam) ;;
        *)
          printf 'record: unknown audio mode "%s"\n' "$audio" >&2
          exit 2
          ;;
      esac
      ;;
    --webcam-device=*) webcam_device="${1#*=}" ;;
    --webcam-size=*)
      webcam_size="${1#*=}"
      case "$webcam_size" in
        small | medium | large) ;;
        *)
          printf 'record: unknown webcam size "%s"\n' "$webcam_size" >&2
          exit 2
          ;;
      esac
      ;;
    *)
      printf 'record: unknown argument "%s" (try --help)\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

# ---- state -------------------------------------------------------------------

# Which recorder to act on, as arguments for `record-process`: `--pid N` when the
# saved pid is still a recorder, and nothing at all when it is not.
#
# The fallback is the point. A recorder can end without a stop — a crash, an OOM
# kill, the session tearing the process group down — and then the pid file names
# something that is gone. Reading only the saved pid would call that "not
# recording", and the toggle would start a *second* recorder instead of stopping
# the one still running: every press adding a recording and none of them stopping
# it. Treating "no saved pid, but a recorder of ours is up" as recording is what
# makes the key a stop in that state rather than another start.
#
# An empty list is deliberate — `record-process` reads no `--pid` as every recorder
# of this user — so this must not be written as a command substitution.
RECORDER_ARGS=()
select_recorder() {
  RECORDER_ARGS=()
  if [ -f "$pid_file" ]; then
    pid=$(cat "$pid_file" 2>/dev/null)
    if [ -n "$pid" ] && "$record_process" --pid "$pid"; then
      RECORDER_ARGS=(--pid "$pid")
    fi
  fi
  return 0
}

record_status() {
  select_recorder
  "$record_process" "${RECORDER_ARGS[@]}"
}

# ---- stopping ----------------------------------------------------------------

# The frame the thumbnail is taken from, read out of the raw recording before
# finalizing renames over it. Grabbed at 0.2s because finalizing trims the first
# 0.1s, so that is the frame the finished file shows at 0.1s.
grab_thumbnail() {
  raw="$1"
  preview="${raw%.mp4}-preview.png"
  [ -f "$raw" ] || return 1
  "$ffmpeg" -y -ss 00:00:00.2 -i "$raw" -vframes 1 -q:v 2 "$preview" -loglevel quiet 2>/dev/null || return 1
  printf '%s' "$preview"
}

# Trim the first frame, and normalize the audio if there is any, in one pass.
#
# The video is stream-copied — no re-encode — unless the first GOP carries
# discardable warm-up packets, which a copy cannot drop because it has to rewind
# to the keyframe. That is the one case worth paying for an encode.
#
# The audio pass hard-mutes the first 400ms, which drops the near-clipping
# transient PipeWire makes when the capture stream opens, then fades in over 50ms
# so the boundary does not click, then normalizes to -14 LUFS. loudnorm declares
# 192kHz output, so -ar pins the result back to 48kHz rather than letting the AAC
# encoder write 96kHz from a 48kHz recording.
finalize_recording() {
  raw="$1"
  [ -f "$raw" ] || return 0

  codec=(-c:v copy)
  if "$ffprobe" -v error -select_streams v:0 -read_intervals %+0.2 \
    -show_entries packet=flags -of csv=p=0 "$raw" 2>/dev/null | grep -q D; then
    codec=(-c:v libx264 -preset veryfast -crf 20)
  fi

  args=(-y -ss 0.1 -i "$raw" "${codec[@]}")
  if "$ffprobe" -v error -select_streams a -show_entries stream=codec_type \
    -of csv=p=0 "$raw" 2>/dev/null | grep -q audio; then
    args+=(-ar 48000 -af "volume=enable='lt(t,0.4)':volume=0,afade=t=in:st=0.4:d=0.05,loudnorm=I=-14:TP=-1.5:LRA=11")
  fi

  processed="${raw%.mp4}-processed.mp4"
  if "$ffmpeg" "${args[@]}" "$processed" -loglevel quiet 2>/dev/null; then
    mv "$processed" "$raw"
  else
    rm -f "$processed"
  fi
}

stop_recording() {
  # The same selection the status uses, so a recording whose pid file went stale is
  # still stopped rather than left running.
  select_recorder

  # SIGINT, not TERM: gpu-screen-recorder finalizes the container on INT, and a
  # TERM leaves a file with no moov atom that nothing will play.
  "$record_process" "${RECORDER_ARGS[@]}" --signal INT

  # Give it five seconds to finish writing, then take it down.
  count=0
  while "$record_process" "${RECORDER_ARGS[@]}" && [ "$count" -lt 50 ]; do
    sleep 0.1
    count=$((count + 1))
  done

  "$webcam_overlay" stop 2>/dev/null

  if "$record_process" "${RECORDER_ARGS[@]}"; then
    "$record_process" "${RECORDER_ARGS[@]}" --signal KILL
    notify critical "Recording failed" "It did not stop cleanly, so the file may be incomplete."
  else
    name=$(cat "$name_file" 2>/dev/null)
    if [ -n "$name" ] && [ -f "$name" ]; then
      # The thumbnail is taken first, while the raw file is still the raw file.
      preview=$(grab_thumbnail "$name")
      finalize_recording "$name"
      announce_saved "$name" "$preview"
      if [ -n "$preview" ] && [ -f "$preview" ]; then
        # The shell loads the image when the toast appears and never re-reads it,
        # so the preview only has to outlive that load.
        (sleep 5; rm -f "$preview") 9>&- &
      fi
    fi
  fi

  rm -f "$pid_file" "$name_file" "$region_file"

  # Reported here rather than where the stop was asked for: the dot is about
  # whether a recorder is running, not about whether a stop returned.
  shell_recording stop
}

# ---- starting ----------------------------------------------------------------

choose_audio() {
  # The answer does not come back to this process, so this cannot return a
  # choice the way it used to. The pick runs `record --audio=<which>`, and the
  # choice arrives as an argument to a second `record` that starts the same way
  # a keypress that already knew the answer does.
  {
    printf 'No audio\tnone\n'
    printf 'Desktop audio\tdesktop\n'
    printf 'Desktop + microphone\tdesktop+mic\n'
    if [ -n "$("$webcam_overlay" list 2>/dev/null | head -1)" ]; then
      printf 'Desktop + microphone + webcam\tdesktop+mic+webcam\n'
    fi
  } | pick --title 'record audio' --on-select 'record --audio={}'
}

# The audio flags gpu-screen-recorder wants.
#
# Two sources are joined with `|` into a *single* `-a`, not given as two `-a`
# flags. Both are accepted, but they mean different things: a second `-a` is a
# second audio stream, and two streams whose clocks start at different moments
# collide on the muxer —
#
#   Application provided invalid, non monotonically increasing dts to muxer
#
# — which drops frames and, in most players, only ever plays one of the two
# anyway. The pipe form mixes them into one track, which is what a screen
# recording wants.
audio_args() {
  case "$audio" in
    desktop) printf '%s\n' "-a" "default_output" ;;
    desktop+mic | desktop+mic+webcam) printf '%s\n' "-a" "default_output|default_input" ;;
    *) : ;;
  esac
}

start_recording() {
  # A pid left by a recording that ended without a stop would otherwise hide this
  # one from the toggle until it had started and saved its own.
  rm -f "$pid_file"

  mkdir -p "$out_dir" || {
    notify critical "Recording failed" "Could not create $out_dir."
    return 1
  }

  if [ "$fullscreen" = "true" ]; then
    monitor=$("$shot_pick" fullscreen --match-monitor) || return 1
    target="$monitor"
  else
    target=$("$shot_pick" smart --match-monitor) || return 1
  fi
  [ -n "$target" ] || return 1

  case "$target" in
    monitor:*)
      # By name, at native resolution. A monitor pick fed through as a region
      # would be scaled and re-derived for no reason.
      capture_args=(-w "${target#monitor:}" -s 0x0)
      ;;
    region:*)
      # gsr takes the region as WxH+X+Y, which is what --match-monitor already
      # produced. It is in the compositor's logical space, the same space slurp
      # returned, so the numbers pass through untouched.
      capture_args=(-w region -region "${target#region:}")
      ;;
    *)
      notify critical "Recording failed" "The picker returned something unexpected: $target"
      return 1
      ;;
  esac

  if [ "$audio" = "desktop+mic+webcam" ]; then
    "$webcam_overlay" start "$webcam_size" "$webcam_device" "$target" || {
      notify critical "Recording failed" "Could not start the webcam overlay."
      return 1
    }
  fi

  name="$out_dir/screenrecording-$(date +%Y-%m-%d_%H-%M-%S).mp4"

  mapfile -t audio_flags < <(audio_args)
  [ ${#audio_flags[@]} -gt 0 ] && audio_flags+=(-ac aac)

  echo "===== $(date '+%F %T') target: $target audio: ${audio:-none} =====" >>"$log_file"

  # 9>&- closes the lock file descriptor in the child. Without it the recorder
  # inherits it and holds the lock for as long as it runs, so the toggle that is
  # meant to stop the recording would find the lock busy and cancel nothing.
  "$gsr" "${capture_args[@]}" -k auto -f 60 -fm cfr \
    -fallback-cpu-encoding yes -o "$name" "${audio_flags[@]}" \
    9>&- 2>>"$log_file" &
  pid=$!

  ticks=0
  while kill -0 "$pid" 2>/dev/null && [ ! -f "$name" ]; do
    if [ -e "$cancel_file" ]; then
      break
    fi
    if [ "$ticks" -ge "$ready_ticks" ]; then
      # It is running but has produced nothing. Rather than leave a recorder the
      # toggle cannot see, take it down and report.
      kill -INT "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      rm -f "$name"
      "$webcam_overlay" stop 2>/dev/null
      notify critical "Recording failed" "gpu-screen-recorder did not start. See $log_file."
      return 1
    fi
    ticks=$((ticks + 1))
    sleep 0.2
  done

  if [ -e "$cancel_file" ]; then
    kill -INT "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    rm -f "$name"
    "$webcam_overlay" stop 2>/dev/null
    return 1
  fi

  if kill -0 "$pid" 2>/dev/null; then
    printf '%s' "$pid" >"$pid_file"
    printf '%s' "$name" >"$name_file"
    printf '%s' "${target#*:}" >"$region_file"
    return 0
  fi

  rm -f "$name"
  "$webcam_overlay" stop 2>/dev/null
  notify critical "Recording failed" "gpu-screen-recorder exited before it started. See $log_file."
  return 1
}

# ---- the toggle --------------------------------------------------------------

if [ "$action" = "status" ]; then
  record_status
  exit $?
fi

mkdir -p "$runtime_dir" || exit 1

# An explicit stop is deliberately *not* serialized on the lock. A stop is what is
# asked for when something is stuck, so it must not be blockable by a start that is
# itself stuck — a start sitting in its picker holds the lock, and waiting on it
# would make the key appear to do nothing at all. The cancel file stands that start
# down, and the signal goes to whatever recorder is actually running.
if [ "$action" = "stop" ]; then
  touch "$cancel_file"
  if record_status; then
    stop_recording
    exit 0
  fi
  exit 1
fi

# The toggle, on the other hand, is serialized: two of them racing must not both
# begin a recording. A second request that finds the lock busy asks the start in
# progress to cancel rather than queueing behind it.
exec 9>"$lock_file"
if ! flock -n 9; then
  touch "$cancel_file"
  exit 0
fi

if record_status; then
  stop_recording
  exit 0
fi

rm -f "$cancel_file"

if [ -z "$audio" ]; then
  # Asked, and then this process is done: the picker runs `record --audio=...`,
  # which is the branch above.
  choose_audio
  exit 0
fi

printf '%s' "$$" >"$starting_file"
if start_recording; then
  rm -f "$starting_file"
  shell_recording start
else
  rm -f "$starting_file" "$cancel_file"
  exit 1
fi
