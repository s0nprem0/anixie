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
#   - the NMI watchdog spends a PMU counter and a periodic NMI on a machine that
#     is not being debugged
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

# amdgpu exposes one of these per card; the first is the integrated GPU here.
gpu_level() {
  for f in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
    if [ -e "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

# Keep the first value seen, not the current one: apply runs again whenever any
# property on the profile object changes, and by then the value is already ours.
remember() {
  [ -f "$STATE/$1" ] || printf '%s\n' "$2" >"$STATE/$1"
}

performance_on() {
  mkdir -p "$STATE"

  if gpu="$(gpu_level)"; then
    remember gpu "$(cat "$gpu")"
    printf 'high\n' >"$gpu" 2>/dev/null || true
  fi

  aspm=/sys/module/pcie_aspm/parameters/policy
  if [ -e "$aspm" ]; then
    policy="$("$SED" -n 's/.*\[\([^]]*\)\].*/\1/p' "$aspm")"
    [ -n "$policy" ] || policy=default
    remember aspm "$policy"
    printf 'performance\n' >"$aspm" 2>/dev/null || true
  fi

  remember nmi_watchdog "$("$SYSCTL" -n kernel.nmi_watchdog)"
  "$SYSCTL" -q -w kernel.nmi_watchdog=0 2>/dev/null || true

  for key in vm.dirty_background_ratio vm.dirty_ratio vm.dirty_background_bytes vm.dirty_bytes; do
    remember "$key" "$("$SYSCTL" -n "$key")"
  done
  "$SYSCTL" -q -w vm.dirty_background_bytes=134217728 vm.dirty_bytes=536870912 2>/dev/null || true
}

performance_off() {
  [ -d "$STATE" ] || return 0

  if gpu="$(gpu_level)" && [ -f "$STATE/gpu" ]; then
    cat "$STATE/gpu" >"$gpu" 2>/dev/null || true
  fi

  aspm=/sys/module/pcie_aspm/parameters/policy
  if [ -e "$aspm" ] && [ -f "$STATE/aspm" ]; then
    cat "$STATE/aspm" >"$aspm" 2>/dev/null || true
  fi

  if [ -f "$STATE/nmi_watchdog" ]; then
    "$SYSCTL" -q -w "kernel.nmi_watchdog=$(cat "$STATE/nmi_watchdog")" 2>/dev/null || true
  fi

  # Bytes first, ratios last. Each handler zeroes the other family, so the last
  # write wins; ratios are non-zero on this machine and bytes are zero, which is
  # the combination this order restores.
  if [ -f "$STATE/vm.dirty_ratio" ]; then
    "$SYSCTL" -q -w \
      "vm.dirty_background_bytes=$(cat "$STATE/vm.dirty_background_bytes")" \
      "vm.dirty_bytes=$(cat "$STATE/vm.dirty_bytes")" \
      "vm.dirty_background_ratio=$(cat "$STATE/vm.dirty_background_ratio")" \
      "vm.dirty_ratio=$(cat "$STATE/vm.dirty_ratio")" 2>/dev/null || true
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

case "${1:-}" in
  "" | status)
    if [ -d "$STATE" ]; then
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
