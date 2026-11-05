#!/bin/bash
# Application notification logic
# shellcheck disable=SC2154
# Sourced by theme.sh, which defines the tools and state directories these
# functions use; checked standalone, shellcheck cannot see those assignments.

apply_cursor() {
  local size=""
  if [ -f "$cursor_file" ]; then
    size=$(tr -d '[:space:]' <"$cursor_file" 2>/dev/null || true)
  fi
  case "$size" in
    ''|*[!0-9]*) size="$cursor_size_default" ;;
  esac
  if [ "$size" -lt 8 ] || [ "$size" -gt 128 ]; then
    size="$cursor_size_default"
  fi
  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface cursor-size "$size" >/dev/null 2>&1 || true
  "$hyprctl" setcursor "$cursor_theme" "$size" >/dev/null 2>&1 || true
}

tell_apps() {
  local name="$1" mode gtk_theme icon_theme color_scheme palette
  palette="$live_link/palette.json"

  if [ "$name" = "wallpaper" ]; then
    "$quickshell" ipc call theme palette "$(tr -d '\n' <"$palette" 2>/dev/null || tr -d '\n' <"$generated")" >/dev/null 2>&1 || true
  else
    "$quickshell" ipc call theme set "$name" >/dev/null 2>&1 || true
  fi
  "$hyprctl" reload >/dev/null 2>&1 || true
  pkill -USR1 -x kitty 2>/dev/null || true

  mode=$(tr -d '[:space:]' <"$live_link/mode" 2>/dev/null || tr -d '[:space:]' <"$state_dir/mode" 2>/dev/null || true)
  if [ "$mode" = "light" ]; then
    gtk_theme=adw-gtk3
    icon_theme=Papirus-Light
    color_scheme=prefer-light
  else
    gtk_theme=adw-gtk3-dark
    icon_theme=Papirus-Dark
    color_scheme=prefer-dark
  fi

  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface color-scheme "$color_scheme" >/dev/null 2>&1 || true
  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface gtk-theme "$gtk_theme" >/dev/null 2>&1 || true
  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface icon-theme "$icon_theme" >/dev/null 2>&1 || true
  accent=$(color_accent_name "$(colour primary)")
  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface accent-color "$accent" >/dev/null 2>&1 || true

  # Discord (Equicord): drop the rendered palette into the themes folder and make
  # sure it is enabled. Best-effort — Equicord may not be installed.
  equicord_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Equicord"
  if [ -d "$equicord_dir" ] && [ -s "$live_link/discord.css" ]; then
    mkdir -p "$equicord_dir/themes" 2>/dev/null || true
    cp "$live_link/discord.css" "$equicord_dir/themes/anixie.theme.css" 2>/dev/null || true
    if [ -f "$equicord_dir/settings/settings.json" ]; then
      tmp=$(mktemp "$equicord_dir/settings/.settings.XXXXXX") || true
      if [ -n "$tmp" ]; then
        "$jq" 'if (.enabledThemes // [] | index("anixie")) then . else .enabledThemes = ((.enabledThemes // []) + ["anixie"] | unique) end' \
          "$equicord_dir/settings/settings.json" >"$tmp" 2>/dev/null &&
        mv "$tmp" "$equicord_dir/settings/settings.json" || rm -f "$tmp"
      fi
    fi
  fi

  apply_cursor
  "$tmux" source-file "$live_link/tmux.conf" >/dev/null 2>&1 || true
  "$wallpaper" apply >/dev/null 2>&1 || true
}

run_hooks() {
  local name="$1" mode hook_dir hook bg fg surface muted primary accent alt secondary tertiary yellow danger success error outline surface_container surface_variant bg_dark bg_light fg_light
  hook_dir="${XDG_CONFIG_HOME:-$HOME/.config}/anixie/theme-hooks"
  [ -d "$hook_dir" ] || return 0

  mode=$(tr -d '[:space:]' <"$live_link/mode" 2>/dev/null || printf 'dark')
  bg=$(colour background)
  fg=$(colour foreground)
  surface=$(colour surface)
  muted=$(colour muted)
  primary=$(colour primary)
  accent=$(colour accent)
  alt=$(colour accentAlt)
  secondary=$(colour secondary)
  tertiary=$(colour tertiary)
  yellow=$(colour yellow)
  danger=$(colour danger)
  success=$(colour success)
  error=$(colour error)
  outline=$(colour outline)
  surface_container=$(colour surfaceContainer)
  surface_variant=$(colour surfaceVariant)
  bg_dark=$(colour bgDark)
  bg_light=$(colour bgLight)
  fg_light=$(colour fgLight)

  for hook in "$hook_dir"/*.sh; do
    [ -x "$hook" ] || continue
    env ANIXIE_THEME="$name" ANIXIE_MODE="$mode" \
      ANIXIE_BG="$bg" ANIXIE_FG="$fg" ANIXIE_SURFACE="$surface" \
      ANIXIE_MUTED="$muted" ANIXIE_PRIMARY="$primary" ANIXIE_ACCENT="$accent" \
      ANIXIE_ACCENT_ALT="$alt" ANIXIE_SECONDARY="$secondary" ANIXIE_TERTIARY="$tertiary" \
      ANIXIE_YELLOW="$yellow" ANIXIE_DANGER="$danger" ANIXIE_ERROR="$error" \
      ANIXIE_SUCCESS="$success" ANIXIE_OUTLINE="$outline" \
      ANIXIE_SURFACE_CONTAINER="$surface_container" ANIXIE_SURFACE_VARIANT="$surface_variant" \
      ANIXIE_BG_DARK="$bg_dark" ANIXIE_BG_LIGHT="$bg_light" ANIXIE_FG_LIGHT="$fg_light" \
      "$hook" >/dev/null 2>&1 || true
  done
}
