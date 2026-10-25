set_action() {
  local output="${1:-}" key="${2:-}" value="${3:-}"
  [ -n "$output" ] && [ -n "$key" ] && [ -n "$value" ] ||
    die "set needs an output, a setting and a value"

  # Refuse an output that is not attached, rather than silently adding a monitor
  # rule for a name that will never come back.
  [ -n "$(field_of "$output" name)" ] || die "no output called \"$output\""

  local index disabled
  case "$key" in
    scale)
      case " $ladder " in
        *" $value "*) ;;
        *) die "scale must be one of: $ladder" ;;
      esac
      apply_change "$output" scale "$value"
      save_field "$output" scale "$value"
      ;;
    transform)
      index=$(transform_index "$value") ||
        die "transform must be one of: $transform_names"
      apply_change "$output" transform "$index"
      save_field "$output" transform "$index"
      ;;
    disabled)
      case "$value" in
        yes | true | on) index=1; disabled=true ;;
        no | false | off) index=0; disabled=false ;;
        *) die "disabled takes yes or no" ;;
      esac
      # The panel already refuses the focused screen. The CLI has no such
      # context, so it needs the stronger rule: never remove the last output.
      if [ "$index" = 1 ] && [ "$(field_of "$output" disabled)" != true ] &&
        [ "$(active_count)" -le 1 ]; then
        die "refusing to disable the only active output"
      fi
      apply_change "$output" disabled "$disabled"
      save_field "$output" disabled "$index"
      # Re-enabling adds an output back to the active set; its workspace block
      # needs the rules re-asserted because no hotplug event may arrive.
      [ "$index" = 0 ] && workspaces_sync_action >/dev/null
      ;;
    position)
      case "$value" in
        auto | auto-left | auto-right | auto-up | auto-down) ;;
        *)
          [[ "$value" =~ ^-?[0-9]+x-?[0-9]+$ ]] ||
            die "position must be auto, auto-left/right/up/down, or XxY"
          ;;
      esac
      apply_change "$output" position "$value"
      save_field "$output" position "$value"
      ;;
    mode)
      value=${value%Hz}
      case "$value" in
        preferred | highres | highrr | maxwidth) ;;
        *)
          [[ "$value" =~ ^[0-9]+x[0-9]+(@[0-9.]+)?$ ]] ||
            die "mode must be preferred, highres, highrr, or WxH[@R]"
          ;;
      esac
      apply_change "$output" mode "$value"
      save_field "$output" mode "$value"
      ;;
    mirror)
      case "$value" in
        none | off | "") value=none ;;
        *)
          [ "$value" = "$output" ] && die "an output cannot mirror itself"
          [ -n "$(field_of "$value" name)" ] ||
            die "no output called \"$value\" to mirror"
          [ "$(field_of "$value" disabled)" = true ] &&
            die "$value is off; turn it on before mirroring"
          # Hyprland has no meaning for a mirror of a mirror. Refusing here
          # gives the panel a sentence instead of a compositor error.
          [ "$(read_state "$value" | cut -f4)" = none ] ||
            die "$value is mirroring another screen; extend it first"
          ;;
      esac
      [ "$(field_of "$output" disabled)" = true ] &&
        die "$output is off; turn it on before mirroring"
      apply_change "$output" mirror "$value"
      save_field "$output" mirror "$value"
      # Coming back to extended gives the output a workspace again, and no
      # hotplug event arrives for a mirror being turned off.
      [ "$value" = none ] && workspaces_sync_action >/dev/null
      ;;
    *)
      die "set takes scale, transform, disabled, position, mode or mirror"
      ;;
  esac

  printf '%s %s %s\n' "$output" "$key" "$value"
}

# The timer that turns a try back into the previous value. It lives outside the
# shell that started it on purpose: closing the panel, or the shell itself
# crashing, must not leave the screen in a mode nobody can see well enough to
# undo.
stop_revert_timer() {
  # Only the timer. Stopping the service as well could cut a revert off halfway
  # when Keep and the countdown land on the same second.
  "$systemctl" --user stop "$revert_unit.timer" >/dev/null 2>&1 || true
}

start_revert_timer() {
  # The service does not inherit the compositor's environment, and hyprctl
  # needs the instance signature and runtime directory to find the socket. Pass
  # the state location too, so the revert reads the same pending file.
  local env_args=()
  [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] &&
    env_args+=(--setenv=HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE")
  [ -n "${XDG_RUNTIME_DIR:-}" ] &&
    env_args+=(--setenv=XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR")
  [ -n "${XDG_STATE_HOME:-}" ] &&
    env_args+=(--setenv=XDG_STATE_HOME="$XDG_STATE_HOME")
  [ -n "${HOME:-}" ] &&
    env_args+=(--setenv=HOME="$HOME")

  # --collect removes the transient units when they finish, so the next try does
  # not trip over the leftovers of this one.
  "$systemd_run" --user --quiet --collect --unit="$revert_unit" \
    --on-active="$revert_seconds" "${env_args[@]}" -- "$0" revert >/dev/null 2>&1
}

# Apply a change that can leave a screen unreadable, keeping the old value in a
# pending file until `keep` says the new one is usable.
try_action() {
  local output="${1:-}" key="${2:-}" value="${3:-}" state old tmp

  [ -n "$output" ] && [ -n "$key" ] && [ -n "$value" ] ||
    die "try needs an output, a setting and a value"
  [ -f "$pending_file" ] &&
    die "a display change is already pending; run keep or revert first"
  [ -n "$(field_of "$output" name)" ] || die "no output called \"$output\""
  [ "$(field_of "$output" disabled)" = true ] &&
    die "$output is off; turn it on first"

  state=$(read_state "$output") || die "no output called \"$output\""

  # Only the settings that can make the panel unusable. Mirror and on/off are
  # visible immediately and undone from the same panel.
  case "$key" in
    scale)
      case " $ladder " in
        *" $value "*) ;;
        *) die "scale must be one of: $ladder" ;;
      esac
      old=$(cut -f1 <<<"$state")
      ;;
    transform)
      value=$(transform_index "$value") ||
        die "transform must be one of: $transform_names"
      old=$(cut -f2 <<<"$state")
      ;;
    mode)
      value=${value%Hz}
      case "$value" in
        preferred | highres | highrr | maxwidth) ;;
        *)
          [[ "$value" =~ ^[0-9]+x[0-9]+(@[0-9.]+)?$ ]] ||
            die "mode must be preferred, highres, highrr, or WxH[@R]"
          ;;
      esac
      old=$(cut -f6 <<<"$state")
      ;;
    position)
      case "$value" in
        auto | auto-left | auto-right | auto-up | auto-down) ;;
        *)
          [[ "$value" =~ ^-?[0-9]+x-?[0-9]+$ ]] ||
            die "position must be auto, auto-left/right/up/down, or XxY"
          ;;
      esac
      old=$(cut -f5 <<<"$state")
      ;;
    *)
      die "try takes scale, transform, mode or position"
      ;;
  esac

  mkdir -p "$state_dir" || die "could not create $state_dir"
  tmp=$(mktemp "${TMPDIR:-/tmp}/monitors.XXXXXX") || die "could not make a temporary file"
  printf '%s\t%s\t%s\t%s\n' "$output" "$key" "$old" "$value" >"$tmp"
  mv "$tmp" "$pending_file"

  # Arm the timer before touching the screen. If this script is killed between
  # the two steps — closing the panel destroys the process — the timer still
  # removes the stale pending file and puts the old value back. Arming it after
  # the change would leave a pending change with nothing left to undo it.
  stop_revert_timer
  if ! start_revert_timer; then
    rm -f "$pending_file"
    die "could not schedule the automatic revert; the display was not changed"
  fi

  apply_change "$output" "$key" "$value"

  printf '%s %s %s (reverting in %ss unless kept)\n' \
    "$output" "$key" "$value" "$revert_seconds"
}

# Persist the pending change and disarm the timer.
keep_action() {
  local output key _old new

  [ -f "$pending_file" ] || {
    printf 'no display change to keep\n'
    return 0
  }

  IFS=$'\t' read -r output key _old new <"$pending_file" ||
    die "could not read the pending display change"

  stop_revert_timer
  save_field "$output" "$key" "$new"
  rm -f "$pending_file"
  printf '%s %s %s kept\n' "$output" "$key" "$new"
}

# Put the pending change back. Also what the timer runs after its countdown.
revert_action() {
  local output key old _new

  [ -f "$pending_file" ] || return 0
  IFS=$'\t' read -r output key old _new <"$pending_file" || {
    rm -f "$pending_file"
    return 1
  }

  # The output can disappear during the countdown. There is nothing left to
  # revert in that case, and the stale pending file would block the next try.
  if [ -z "$(field_of "$output" name)" ]; then
    rm -f "$pending_file"
    return 0
  fi

  stop_revert_timer
  apply_change "$output" "$key" "$old"
  rm -f "$pending_file"
  printf '%s %s reverted to %s\n' "$output" "$key" "$old"
}

# Ask the running shell to put each output's name on it for a moment.
identify_action() {
  local reply
  # `ipc call` exits zero even when the target does not exist (it prints
  # "Target not found."), so the answer is what says whether the shell is new
  # enough to have the handler.
  reply=$("$quickshell" ipc call identify flash 2>&1) || true
  [ "$reply" = "ok" ] ||
    die "could not ask the running shell to identify the displays (${reply:-no reply})"
  printf 'display names flashed\n'
}

