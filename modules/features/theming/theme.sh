#!/bin/bash
# Themes.
#
#   theme                pick one
#   theme list           the names, one per line
#   theme current        the name in use
#   theme set NAME       switch to it
#   theme wallpaper [FILE] [auto|light|dark]
#                        derive a palette from a picture
#   theme next | prev    step through the list
#   theme apply          re-apply the current one (run at login)
#
# One palette drives the shell, the compositor's window borders, the terminal and
# the launcher. The shell is told over its IPC and switches immediately; Hyprland
# reloads, kitty takes SIGUSR1, and the rest read the files written here.
#
# btop, tmux, Helix, Yazi and hyprlock are rewritten on every switch, along with
# the resolved palette that Hyprland and the wallpaper command read. GTK follows
# the mode through gsettings (Adwaita/Adwaita-dark and Papirus/Papirus-Light),
# and Qt through qt6ct. Applications that read their config at startup pick the
# new palette up then; nothing here needs a rebuild.
#
# The palettes are a JSON file rather than a Nix expression because this script
# has to read the same list the shell was built from, and a shell script cannot
# evaluate Nix. One file, two readers, nothing to keep in step by hand.

set -uo pipefail

palettes="@PALETTES@"
state_dir="@STATE_DIR@"
default_theme="@DEFAULT_THEME@"

quickshell="@QUICKSHELL@"
matugen="@MATUGEN@"
generated="@GENERATED@"
hyprctl="@HYPRCTL@"
gsettings="@GSETTINGS@"
gsettings_schema_dir="@GSETTINGS_SCHEMA_DIR@"
jq="@JQ@"
wallpaper="@WALLPAPER@"
magick="@MAGICK@"
ffmpeg="@FFMPEG@"
sha256sum="@SHA256SUM@"
stat="@STAT@"

current_file="$state_dir/current"

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

names() {
  "$jq" -r 'keys[]' "$palettes" | sort
}

has() {
  # `wallpaper` is not in the file: it is whatever matugen last made of the
  # current picture, and it exists once a palette has been generated.
  [ "$1" = "wallpaper" ] && return 0
  "$jq" -e --arg n "$1" 'has($n)' "$palettes" >/dev/null 2>&1
}

mode_of() {
  "$jq" -r --arg n "$1" '.[$n]._mode // "dark"' "$palettes"
}

# One colour out of the resolved palette. materialise() writes it for a curated
# theme; matugen writes it for a wallpaper.
colour() {
  "$jq" -r --arg k "$1" '.[$k]' "$generated"
}

current() {
  local name=""
  [ -f "$current_file" ] && name=$(tr -d '[:space:]' <"$current_file")
  if [ -n "$name" ] && has "$name"; then
    printf '%s' "$name"
  else
    printf '%s' "$default_theme"
  fi
}

# Write the files the apps read. Everything that follows a theme is materialised
# here rather than rendered at build time, because a build-time value cannot
# change without a rebuild.
materialise() {
  local name="$1" tmp
  mkdir -p "$state_dir" || die "could not create $state_dir"

  if [ "$name" = "wallpaper" ]; then
    [ -f "$generated" ] || die "the generated palette is missing; run 'theme wallpaper FILE'"
  else
    tmp=$(mktemp "$state_dir/palette.XXXXXX") || die "could not create a palette file"
    "$jq" --arg n "$name" '.[$n] | del(._mode)' "$palettes" >"$tmp" \
      || die "could not resolve $name"
    mv "$tmp" "$generated"
  fi

  # The mode is metadata, not a colour: the build-time configs need it, and so
  # does a runtime switch of the glass theme.
  if [ "$name" = "wallpaper" ]; then
    "$jq" -r '._mode // "dark"' "$generated" >"$state_dir/mode"
  else
    "$jq" -r --arg n "$name" '.[$n]._mode // "dark"' "$palettes" >"$state_dir/mode"
  fi

  printf '%s\n' "$name" >"$current_file"

  # kitty reads this through an include in its generated config, so the same four
  # settings appear whether the theme was built in or set at runtime.
  cat >"$state_dir/kitty.conf" <<EOF
background $(colour background)
foreground $(colour foreground)
selection_background $(colour accent)
selection_foreground $(colour background)
EOF

  # tmux, btop, and whichever others have learned to read the state directory.
  # A failure here must not take the theme switch with it — the shell and the
  # terminal have already changed by this point.
  "@THEME_APPS@" "$name" >/dev/null 2>&1 || true
}

# The compositor and the terminal have to be told. The shell is told through its
# IPC rather than left to notice: it reads the state file once at startup, and a
# FileView watch on it never fired on this Quickshell, so a running shell has no
# other way to hear about the change.
tell_apps() {
  local name="$1" mode gtk_theme icon_theme color_scheme qt_style

  # A generated palette cannot be named to the shell — the shell was built with
  # the curated ones — so it is handed over whole.
  if [ "$name" = "wallpaper" ]; then
    "$quickshell" ipc call theme palette "$(tr -d '\n' <"$generated")" >/dev/null 2>&1 || true
  else
    "$quickshell" ipc call theme set "$name" >/dev/null 2>&1 || true
  fi
  "$hyprctl" reload >/dev/null 2>&1 || true
  pkill -USR1 -x kitty 2>/dev/null || true

  # GTK reads the mode rather than only the palette: the dark and light variants
  # are separate themes, and the icon set has a matching pair.
  mode=$(tr -d '[:space:]' <"$state_dir/mode" 2>/dev/null || true)
  if [ "$mode" = "light" ]; then
    gtk_theme=Adwaita
    icon_theme=Papirus-Light
    color_scheme=prefer-light
    qt_style=adwaita
  else
    gtk_theme=Adwaita-dark
    icon_theme=Papirus-Dark
    color_scheme=prefer-dark
    qt_style=adwaita-dark
  fi

  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface color-scheme "$color_scheme" >/dev/null 2>&1 || true
  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface gtk-theme "$gtk_theme" >/dev/null 2>&1 || true
  GSETTINGS_SCHEMA_DIR="$gsettings_schema_dir" "$gsettings" set \
    org.gnome.desktop.interface icon-theme "$icon_theme" >/dev/null 2>&1 || true

  # Qt reads qt6ct's config when an application starts. The file lives in the
  # state directory and is linked into ~/.config by the Nix module.
  cat >"$state_dir/qt6ct.conf" <<EOF
[Appearance]
icon_theme=$icon_theme
style=$qt_style
EOF

  # The wallpaper follows the palette unless one of your own is set, in which
  # case this is a no-op — the `wallpaper` command owns that decision.
  "$wallpaper" apply >/dev/null 2>&1 || true
}

# Read the current wallpaper into a palette. Deliberately last in the order of
# things that can fail: a wallpaper matugen cannot parse leaves the previous
# palette in place rather than half-applying a new one. Results are cached by
# path, modification time and requested mode; videos use their first frame.
generate() {
  local wp="${1:-}" requested="${2:-auto}" mode json tmp
  local source mtime key cache_dir cache frame saturation mono
  local -a args
  mkdir -p "$state_dir" || die "could not create $state_dir"

  case "$requested" in
    "" | auto | smart) requested=smart ;;
    light | dark) ;;
    *) die "mode must be auto, light or dark" ;;
  esac

  # A picture can be named, and otherwise the current one is used — but only if it
  # is a file. The generated wallpaper is a gradient made *from* the palette, so
  # reading a palette out of it is a circle; saying so is better than reporting
  # that there is no wallpaper at all.
  [ -n "$wp" ] || wp=$("$wallpaper" current 2>/dev/null || true)

  [ -n "$wp" ] && [ -f "$wp" ] || die "no picture to read a palette from — set one with 'wallpaper set FILE', or name one: 'theme wallpaper FILE'"

  # Cache the result per path, modification time and mode. Re-selecting the same
  # wallpaper is then instant, and an overwritten file is read again.
  mtime=$("$stat" -Lc %Y "$wp" 2>/dev/null || printf '0')
  key=$(printf '%s\n%s\n%s\n' "$wp" "$mtime" "$requested" | "$sha256sum")
  key=${key%% *}
  cache_dir="$state_dir/cache"
  cache="$cache_dir/palette-$key.json"
  mkdir -p "$cache_dir" || die "could not create $cache_dir"

  if [ -f "$cache" ]; then
    cp "$cache" "$generated"
    return
  fi

  source="$wp"
  case "$(printf '%s' "${source##*.}" | tr '[:upper:]' '[:lower:]')" in
    mp4 | m4v | mov | webm | mkv | avi | ogv)
      frame="$cache_dir/frame-$key.jpg"
      if [ ! -f "$frame" ]; then
        "$ffmpeg" -y -loglevel error -i "$source" -frames:v 1 -q:v 2 "$frame" \
          || die "could not read a frame from $wp"
      fi
      source="$frame"
      ;;
  esac

  # A monochrome picture would otherwise get a tinted Material palette; ask
  # matugen for the neutral one instead.
  saturation=$("$magick" "$source" -colorspace HSL -channel G -separate \
    -format '%[fx:mean]' info: 2>/dev/null || printf '1')
  if awk -v s="$saturation" 'BEGIN { exit !(s < 0.08) }'; then
    mono=1
  else
    mono=0
  fi

  args=(image "$source" --mode "$requested" --source-color-index 0 --json hex)
  # --source-color-index keeps matugen from asking which colour to use: that
  # prompt is a hard error when this runs from a keybind or a service.
  if [ "$mono" = "1" ]; then
    args+=(--type scheme-monochrome)
  fi

  json=$("$matugen" "${args[@]}" 2>/dev/null) \
    || die "matugen could not read $source"
  [ -f "$generated" ] || die "matugen wrote no palette"

  mode=$(printf '%s' "$json" | "$jq" -r '.mode // empty' 2>/dev/null || true)
  if [ -z "$mode" ]; then
    if [ "$requested" = "smart" ]; then mode=dark; else mode=$requested; fi
  fi

  # Keep the mode with the palette so the shell can style light surfaces and a
  # later `theme apply` knows what it is applying without asking matugen again.
  tmp=$(mktemp "$state_dir/palette.XXXXXX") || die "could not create a palette file"
  "$jq" --arg mode "$mode" '. + {_mode: $mode}' "$generated" >"$tmp" \
    || die "could not read the generated palette"
  mv "$tmp" "$generated"

  cp "$generated" "$cache"
}

set_theme() {
  local name="$1"
  [ "$name" = "wallpaper" ] && generate "${2:-}" "${3:-auto}"
  has "$name" || die "no theme called \"$name\" (try: theme list)"
  materialise "$name"
  tell_apps "$name"
  printf 'Theme: %s\n' "$name"
}

step() {
  local direction="$1" here target
  here=$(current)

  # Sorted order, wrapping at both ends, so next from the last is the first.
  target=$(
    names | awk -v here="$here" -v dir="$direction" '
      { list[NR] = $0; if ($0 == here) at = NR }
      END {
        # A generated wallpaper is not in the list. Stepping away from it starts
        # at the first theme going forward and the last going back.
        if (at == 0) at = (dir == "next") ? 0 : 1
        if (dir == "next") at = (at % NR) + 1
        else at = ((at - 2 + NR) % NR) + 1
        print list[at]
      }'
  )

  [ -n "$target" ] || die "could not work out the next theme"
  set_theme "$target"
}

case "${1:-}" in
  -h | --help)
    usage
    ;;
  list)
    names
    ;;
  current)
    current
    ;;
  apply)
    # No change, just make sure the files match the saved choice — this is what
    # login runs, since a fresh boot has the state directory but not the files.
    materialise "$(current)"
    tell_apps "$(current)"
    ;;
  set)
    [ $# -ge 2 ] || die "set needs a theme name"
    set_theme "$2"
    ;;
  wallpaper)
    set_theme wallpaper "${2:-}" "${3:-auto}"
    ;;
  next)
    step next
    ;;
  prev | previous)
    step prev
    ;;
  "")
    # The picker runs `theme set <name>` itself, so this has nothing left to do
    # but hand over the names and be done. The label carries the mode; the value
    # stays the name, so the command it runs does not change.
    names | while IFS= read -r name; do
      printf '%s (%s)\t%s\n' "$name" "$(mode_of "$name")" "$name"
    done | pick --title 'theme' --on-select 'theme set {}'
    exit 0
    ;;
  *)
    printf 'theme: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac
