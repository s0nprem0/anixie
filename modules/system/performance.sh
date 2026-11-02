#!/bin/sh
# Extras for the performance power profile.
#
# power-profiles-daemon owns the profile itself: selecting performance raises the
# ACPI platform profile and puts every amd_pstate policy on the performance
# governor with the performance EPP. What it does not touch is the rest of the
# machine, which is where the remaining latency sits:
#
#   - the GPU stays on auto DPM, so it re-enters its highest state only under
#     load; forcing "high" keeps it there while the profile is selected
#   - PCIe ASPM is free to park links, which adds latency to the NVMe and the GPU
#   - up to 20% of RAM (1.6G here) may sit dirty before writeback starts, which
#     turns every large copy or build into a stall once it does
#
# Each value is remembered before it is changed and put back when the profile
# leaves performance, so choosing balanced — or unplugging, which the power
# profile watcher does — returns the machine to exactly what it was.
#
# The trigger is net.hadess.PowerProfiles on the system bus rather than the
# `powerprofile` helper, because the panel, `powerprofilesctl` and `anixie power`
# can all change the profile without going through that helper.
#
#   performance-tune status   whether the extras are in effect
#   performance-tune apply    apply or revert for the current profile
#   performance-tune watch    apply now, then on every profile change
set -eu

PPD="@PPD@"
BUSCTL="@BUSCTL@"
SYSCTL="@SYSCTL@"
SED="@SED@"
STDBUF="@STDBUF@"
STATE="@STATE@"

# amdgpu exposes one of these per card. Prefer the card that owns the boot
# display, which is the integrated GPU on a hybrid laptop; on a machine where
# nothing claims boot_vga, fall back to the first amdgpu card.
gpu_level() {
  fallback=
  for f in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
    [ -e "$f" ] || continue
    if [ "$(cat "${f%/*}/boot_vga" 2>/dev/null || true)" = "1" ]; then
      printf '%s\n' "$f"
      return 0
    fi
    [ -n "$fallback" ] || fallback=$f
  done
  [ -n "$fallback" ] || return 1
  printf '%s\n' "$fallback"
}

# Keep the first value seen, not the current one: apply runs again whenever any
# property on the profile object changes, and by then the value is already ours.
remember() {
  [ -f "$STATE/$1" ] || printf '%s\n' "$2" >"$STATE/$1"
}

# A failed write is worth a journal line: recording the original value while the
# tunable never changed would make `status` claim an effect that is not there.
set_value() {
  printf '%s\n' "$2" >"$1" 2>/dev/null ||
    printf 'performance-tune: cannot set %s\n' "$1" >&2
}

aspm_policy() {
  aspm=/sys/module/pcie_aspm/parameters/policy
  [ -r "$aspm" ] || return 1
  "$SED" -n 's/.*\[\([^]]*\)\].*/\1/p' "$aspm"
}

performance_on() {
  mkdir -p "$STATE"

  if gpu="$(gpu_level)"; then
    remember gpu "$(cat "$gpu")"
    set_value "$gpu" high
  fi

  if policy="$(aspm_policy)"; then
    [ -n "$policy" ] || policy=default
    remember aspm "$policy"
    set_value /sys/module/pcie_aspm/parameters/policy performance
  fi

  for key in vm.dirty_background_ratio vm.dirty_ratio vm.dirty_background_bytes vm.dirty_bytes; do
    remember "$key" "$("$SYSCTL" -n "$key")"
  done
  # Only one family is in use: writing bytes zeroes the ratios and the reverse.
  # Record which one was active so the restore writes that family alone rather
  # than guessing an order that only fits this machine's defaults.
  if [ ! -f "$STATE/dirty_family" ]; then
    if [ "$(cat "$STATE/vm.dirty_background_bytes" 2>/dev/null || echo 0)" != "0" ] ||
      [ "$(cat "$STATE/vm.dirty_bytes" 2>/dev/null || echo 0)" != "0" ]; then
      printf 'bytes\n' >"$STATE/dirty_family"
    else
      printf 'ratio\n' >"$STATE/dirty_family"
    fi
  fi
  "$SYSCTL" -q -w vm.dirty_background_bytes=134217728 vm.dirty_bytes=536870912 2>/dev/null ||
    printf 'performance-tune: cannot set the dirty writeback thresholds\n' >&2
}

performance_off() {
  [ -d "$STATE" ] || return 0

  if gpu="$(gpu_level)" && [ -f "$STATE/gpu" ]; then
    set_value "$gpu" "$(cat "$STATE/gpu")"
  fi

  if [ -f "$STATE/aspm" ]; then
    set_value /sys/module/pcie_aspm/parameters/policy "$(cat "$STATE/aspm")"
  fi

  if [ -f "$STATE/dirty_family" ]; then
    case "$(cat "$STATE/dirty_family" 2>/dev/null || true)" in
      bytes)
        "$SYSCTL" -q -w \
          "vm.dirty_background_bytes=$(cat "$STATE/vm.dirty_background_bytes")" \
          "vm.dirty_bytes=$(cat "$STATE/vm.dirty_bytes")" 2>/dev/null ||
          printf 'performance-tune: cannot restore the dirty writeback thresholds\n' >&2
        ;;
      *)
        "$SYSCTL" -q -w \
          "vm.dirty_background_ratio=$(cat "$STATE/vm.dirty_background_ratio")" \
          "vm.dirty_ratio=$(cat "$STATE/vm.dirty_ratio")" 2>/dev/null ||
          printf 'performance-tune: cannot restore the dirty writeback thresholds\n' >&2
        ;;
    esac
  fi

  rm -rf "$STATE"
}

apply() {
  profile="$("$PPD" get 2>/dev/null || true)"
  case "$profile" in
    performance) performance_on ;;
    *) performance_off ;;
  esac
}

watch() {
  apply
  # One header line per message, so a profile change does not apply twice.
  # Line-buffered: busctl writes through stdio, which would otherwise hold the
  # header back until the pipe filled.
  "$STDBUF" -oL "$BUSCTL" monitor --system \
    --match "type='signal',interface='org.freedesktop.DBus.Properties',path='/net/hadess/PowerProfiles',member='PropertiesChanged'" |
    while IFS= read -r line; do
      case "$line" in
        *Path=/net/hadess/PowerProfiles*) apply ;;
      esac
    done
}

# Look at the tunables themselves rather than the state directory: a write the
# kernel refused still creates the directory, and reporting "on" then would hide
# exactly the failure worth noticing.
extras_active() {
  if gpu="$(gpu_level)" && [ "$(cat "$gpu" 2>/dev/null || true)" = "high" ]; then
    return 0
  fi
  [ "$(aspm_policy 2>/dev/null || true)" = "performance" ] && return 0
  if [ "$("$SYSCTL" -n vm.dirty_background_bytes 2>/dev/null || true)" = "134217728" ] &&
    [ "$("$SYSCTL" -n vm.dirty_bytes 2>/dev/null || true)" = "536870912" ]; then
    return 0
  fi
  return 1
}

case "${1:-}" in
  "" | status)
    if extras_active; then
      echo "performance extras: on"
    else
      echo "performance extras: off"
    fi
    ;;
  apply) apply ;;
  watch) watch ;;
  -h | --help)
    "$SED" -n '2,/^[^#]/p' "$0" | "$SED" -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
    ;;
  *)
    printf 'performance-tune: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac
