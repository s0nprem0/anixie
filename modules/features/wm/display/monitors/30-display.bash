internal_action() {
  local action="${1:-toggle}" name disabled
  case "$action" in
    on | off | toggle) ;;
    *) die "internal takes on, off or toggle" ;;
  esac

  name=$(internal_name)
  [ -n "$name" ] || die "no monitor found"
  disabled=$(field_of "$name" disabled)

  if [ "$action" = "toggle" ]; then
    if [ "$disabled" = true ]; then action=on; else action=off; fi
  fi

  if [ "$action" = "off" ]; then
    [ "$disabled" = true ] && return 0
    [ "$(active_count)" -le 1 ] && die "refusing to disable the only active output"
    apply_change "$name" disabled true
    save_field "$name" disabled 1
    printf 'internal panel %s: off\n' "$name"
  else
    [ "$disabled" != true ] && return 0
    apply_change "$name" disabled false
    save_field "$name" disabled 0
    workspaces_sync_action >/dev/null
    printf 'internal panel %s: on\n' "$name"
  fi
}

mirror_action() {
  local action="${1:-toggle}" internal external mirrored
  internal=$(internal_name)
  external=$(external_name)

  [ -n "$external" ] || die "no external monitor connected to mirror onto"
  [ "$(field_of "$internal" disabled)" = true ] &&
    die "internal panel is off; turn it on before mirroring"

  # Read rather than remembered: `mirrorOf` on the external is Hyprland's own answer,
  # so the toggle cannot drift out of step with a mirror set some other way.
  mirrored=$(field_of "$external" mirrorOf)
  [ "$mirrored" = null ] && mirrored=none

  case "$action" in
    toggle)
      if [ "${mirrored:-none}" = "none" ]; then action="on"; else action="off"; fi
      ;;
    on | off) ;;
    *) die "mirror takes on, off or toggle" ;;
  esac

  if [ "$action" = "on" ]; then
    apply_change "$external" mirror "$internal"
    save_field "$external" mirror "$internal"
    printf '%s now mirrors %s\n' "$external" "$internal"
  else
    apply_change "$external" mirror none
    save_field "$external" mirror none
    printf '%s extended again\n' "$external"
  fi
}

status_action() {
  # Same id-to-name resolution as the panel: `mirror of 0` is Hyprland's
  # internal target id, not something a person can act on.
  "$jq" -r '
    . as $all
    | ($all | map({ key: (.id | tostring), value: .name }) | from_entries) as $names
    | $all[]
    | "\(.name)\t\(.width)x\(.height)\tscale \(.scale)\t"
      + (if .disabled then "off"
         elif (.mirrorOf // "none") == "none" or (.mirrorOf // "") == ""
         then "extended"
         else "mirror of \($names[.mirrorOf] // .mirrorOf)" end)
      + (if .focused then "\tfocused" else "" end)' <<<"$(all_monitors_json)"
}

# How many outputs are currently in the layout. A saved state can leave an
# output disabled; only the active ones count for the last-display guard.
active_count() {
  "$jq" '[.[] | select(.disabled == false)] | length' <<<"$(all_monitors_json)"
}

# Close the lid with an external attached: take the internal panel out of the
# layout, remembering that this script did it. Opening it puts the panel back at
# its saved scale/position/mode. A panel the user had already switched off is
# left alone, so this does not undo a deliberate choice.
lid_action() {
  local action="${1:-toggle}" internal external saved
  internal=$(internal_name)
  external=$(external_name)
  [ -n "$internal" ] || return 0

  case "$action" in
    close | off)
      [ -n "$external" ] || {
        printf 'no external monitor; leaving the internal panel on\n'
        return 0
      }
      [ "$(field_of "$internal" disabled)" = true ] && return 0
      apply_change "$internal" disabled true
      save_field "$internal" disabled 1
      mkdir -p "$state_dir" || die "could not create $state_dir"
      printf '%s\n' "$internal" >"$lid_file"
      printf 'lid closed: internal panel %s off\n' "$internal"
      ;;
    open | on)
      [ -f "$lid_file" ] || return 0
      saved=$(cat "$lid_file" 2>/dev/null || true)
      [ -n "$saved" ] || {
        rm -f "$lid_file"
        return 0
      }
      [ -n "$(field_of "$saved" name)" ] || {
        rm -f "$lid_file"
        return 0
      }
      apply_change "$saved" disabled false
      save_field "$saved" disabled 0
      rm -f "$lid_file"
      workspaces_sync_action >/dev/null
      printf 'lid opened: internal panel %s on\n' "$saved"
      ;;
    toggle)
      if [ -f "$lid_file" ]; then lid_action open; else lid_action close; fi
      ;;
    reconcile)
      if lid_closed && [ -n "$(external_name)" ]; then
        lid_action close
      else
        lid_action open
      fi
      ;;
    *) die "lid takes close, open, toggle or reconcile" ;;
  esac
}

# Whether the firmware reports the lid as closed. The pre-session recovery has
# no Hyprland to ask, and the switch event may not have fired yet.
lid_closed() {
  local state
  for state in /proc/acpi/button/lid/*/state; do
    [ -r "$state" ] || continue
    grep -q closed "$state" && return 0
  done
  return 1
}

# Clear the disabled flag on one output, leaving every other field alone.
clear_disabled() {
  local output="$1" tmp
  [ -f "$state_file" ] || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/monitors.XXXXXX") || die "could not make a temporary file"
  awk -v n="$output" -v OFS=' ' '
    $1 == n && $4 == "1" { $4 = "0" }
    { print }
  ' "$state_file" >"$tmp"
  if cmp -s "$state_file" "$tmp"; then
    rm -f "$tmp"
  else
    mv "$tmp" "$state_file"
  fi
}

# Clear a saved "internal panel off" when no external display is connected, and
# clear a clamshell state left over from the last shutdown when the lid is open
# again. This runs before the graphical session, when Hyprland is not up yet, so
# it reads the DRM connectors and the firmware lid state directly. Without it,
# docking, switching the laptop panel off, and booting undocked would apply
# disabled = true to the only screen.
recover_action() {
  local name status lid_output
  [ -f "$state_file" ] || {
    rm -f "$lid_file"
    return 0
  }

  if [ -f "$lid_file" ] && ! lid_closed; then
    lid_output=$(cat "$lid_file" 2>/dev/null || true)
    [ -n "$lid_output" ] && clear_disabled "$lid_output"
    rm -f "$lid_file"
    printf 'lid is open; cleared the saved clamshell state\n'
  fi

  for status in /sys/class/drm/card*-*/status; do
    [ -r "$status" ] || continue
    [ "$(cat "$status")" = connected ] || continue
    name=${status%/status}
    # A connected connector with no EDID is not a display the kernel can mode;
    # treating it as usable would keep the internal panel off for a screen that
    # will come up at 0x0. `-s` is not enough here: sysfs reports the edid
    # attribute's stat size as 0 even when reading it returns the blob.
    [ "$(wc -c <"$name/edid" 2>/dev/null || printf 0)" -gt 0 ] || continue
    name=${name##*/}
    name=${name#card*-}
    case "$name" in
      eDP* | LVDS* | DSI* | Virtual* | HEADLESS*) ;;
      *)
        printf 'external display %s is connected; keeping the saved state\n' "$name"
        return 0
        ;;
    esac
  done

  # No usable external display: clear every internal panel that was left off,
  # and drop the lid marker so opening the lid later does not try to restore a
  # panel that is already on.
  for name in $(awk '$1 ~ /^(eDP|LVDS|DSI)/ && $4 == "1" { print $1 }' "$state_file"); do
    clear_disabled "$name"
  done
  rm -f "$lid_file"
  printf 'no external display; cleared the internal-display off state\n'
}

# Cycle DPMS off and on. Hyprland does not always repaint a panel after resume;
# a full off/on cycle is the reliable way to bring it back without a VT switch.
wake_action() {
  "$hyprctl" eval 'hl.dispatch(hl.dsp.dpms({ action = "off" }))' >/dev/null
  sleep 0.2
  "$hyprctl" eval 'hl.dispatch(hl.dsp.dpms({ action = "on" }))' >/dev/null
  printf 'display power cycled\n'
}

# The internal panel is the one with a kernel backlight; everything else is
# adjusted over DDC/CI. The name test matches the eDP/LVDS/DSI panels the kernel
# and Hyprland use.
