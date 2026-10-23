#!/bin/sh
# The files the other applications read their colours from.
#
# Rendered when the theme changes rather than when the system is built, which is
# the difference between a theme that reaches the editor and one that waits for a
# rebuild. Each file lives in the state directory the Nix modules link into
# ~/.config, and is rewritten on every switch; the applications pick it up at
# their next start (tmux is told, so a running server changes at once).
set -eu

palettes="@PALETTES@"
state_dir="@STATE_DIR@"
jq="@JQ@"
tmux="@TMUX@"
helix_template="@HELIX_TEMPLATE@"
yazi_template="@YAZI_TEMPLATE@"
hyprlock_template="@HYPRLOCK_TEMPLATE@"
qt6ct_colors_template="@QT6CT_COLORS_TEMPLATE@"
gtk_template="@GTK_TEMPLATE@"
gtk3_css_template="@GTK3_CSS_TEMPLATE@"
gtk4_css_template="@GTK4_CSS_TEMPLATE@"
cursor_theme="@POINTER_CURSOR_THEME@"
cursor_size="@POINTER_CURSOR_SIZE@"
generated="@STATE_DIR@/palette.json"

name="${1:-}"
[ -n "$name" ] || exit 0

colour() {
  if [ "$name" = "wallpaper" ] && [ -f "$generated" ]; then
    "$jq" -r --arg k "$1" '.[$k]' "$generated"
  else
    "$jq" -r --arg n "$name" --arg k "$1" '.[$n][$k]' "$palettes"
  fi
}

bg=$(colour background)
fg=$(colour foreground)
surface=$(colour surface)
muted=$(colour muted)
primary=$(colour primary)
accent=$(colour accent)
alt=$(colour accentAlt)
yellow=$(colour yellow)
danger=$(colour danger)
success=$(colour success)

# A generated palette from before the yellow token existed still gets a usable
# terminal yellow instead of the literal string "null".
case "$yellow" in
  "" | null) yellow=$accent ;;
esac

# Rendering a palette file with a missing key would write the literal string
# "null" into every template — which is not a colour, and Yazi refuses to parse
# its TOML at all. Refuse instead, leaving the last good files in place.
for value in "$bg" "$fg" "$surface" "$muted" "$primary" "$accent" "$alt" "$danger" "$success"; do
  case "$value" in
    "" | null)
      printf 'theme-apps: the palette is incomplete; keeping the previous files\n' >&2
      exit 1
      ;;
  esac
done

mode=$(tr -d '[:space:]' <"$state_dir/mode" 2>/dev/null || printf 'dark')
if [ "$mode" = "light" ]; then
  helix_parent=base16_default_light
  gtk_theme=Adwaita
  gtk_icon=Papirus-Light
  gtk_dark=0
else
  helix_parent=base16_default_dark
  gtk_theme=Adwaita-dark
  gtk_icon=Papirus-Dark
  gtk_dark=1
fi

mkdir -p "$state_dir"

# Render one of the templates with the palette. Only the placeholders the
# templates actually use are listed; the hex values are safe inside the sed
# expression because none of them contains the delimiter.
render() {
  render_tmp=$(mktemp "$state_dir/.render.XXXXXX") || return 1
  sed \
    -e "s|@BG@|$bg|g" \
    -e "s|@SURFACE@|$surface|g" \
    -e "s|@FG@|$fg|g" \
    -e "s|@MUTED@|$muted|g" \
    -e "s|@PRIMARY@|$primary|g" \
    -e "s|@ACCENT@|$accent|g" \
    -e "s|@ACCENT_ALT@|$alt|g" \
    -e "s|@YELLOW@|$yellow|g" \
    -e "s|@SUCCESS@|$success|g" \
    -e "s|@DANGER@|$danger|g" \
    -e "s|@BG_HEX@|${bg#\#}|g" \
    -e "s|@SURFACE_HEX@|${surface#\#}|g" \
    -e "s|@FG_HEX@|${fg#\#}|g" \
    -e "s|@MUTED_HEX@|${muted#\#}|g" \
    -e "s|@PRIMARY_HEX@|${primary#\#}|g" \
    -e "s|@ACCENT_HEX@|${accent#\#}|g" \
    -e "s|@ACCENT_ALT_HEX@|${alt#\#}|g" \
    -e "s|@YELLOW_HEX@|${yellow#\#}|g" \
    -e "s|@SUCCESS_HEX@|${success#\#}|g" \
    -e "s|@DANGER_HEX@|${danger#\#}|g" \
    -e "s|@HELIX_PARENT@|$helix_parent|g" \
    -e "s|@GTK_THEME@|$gtk_theme|g" \
    -e "s|@GTK_ICON@|$gtk_icon|g" \
    -e "s|@GTK_DARK@|$gtk_dark|g" \
    -e "s|@CURSOR_THEME@|$cursor_theme|g" \
    -e "s|@CURSOR_SIZE@|$cursor_size|g" \
    -e "s|@BG_RGBA_F2@|rgba(${bg#\#}f2)|g" \
    -e "s|@BG_RGBA_FF@|rgba(${bg#\#}ff)|g" \
    -e "s|@SURFACE_RGBA_FF@|rgba(${surface#\#}ff)|g" \
    -e "s|@FG_RGBA_FF@|rgba(${fg#\#}ff)|g" \
    -e "s|@SUCCESS_RGBA_FF@|rgba(${success#\#}ff)|g" \
    -e "s|@DANGER_RGBA_FF@|rgba(${danger#\#}ff)|g" \
    -e "s|@ACCENT_ALT_RGBA_FF@|rgba(${alt#\#}ff)|g" \
    -e "s|@MUTED_RGBA_FF@|rgba(${muted#\#}ff)|g" \
    "$1" >"$render_tmp" || {
    rm -f "$render_tmp"
    return 1
  }
  mv "$render_tmp" "$2"
}

render "$helix_template" "$state_dir/helix.toml"
render "$yazi_template" "$state_dir/yazi.toml"
render "$hyprlock_template" "$state_dir/hyprlock.conf"
render "$qt6ct_colors_template" "$state_dir/qt6ct-colors.conf"
render "$gtk_template" "$state_dir/gtk-3.0-settings.ini"
render "$gtk_template" "$state_dir/gtk-4.0-settings.ini"
render "$gtk3_css_template" "$state_dir/gtk-3.0.css"
render "$gtk4_css_template" "$state_dir/gtk-4.0.css"

# ---- tmux ----
tmux_conf=$(mktemp "$state_dir/.tmux.XXXXXX") || exit 1
cat >"$tmux_conf" <<EOF
set -g status-style "bg=$surface,fg=$fg"
set -g status-left-style "bg=$surface,fg=$muted"
set -g status-right-style "bg=$surface,fg=$muted"
set -g window-status-style "bg=$surface,fg=$muted"
set -g window-status-current-style "bg=$primary,fg=$bg,bold"
set -g pane-border-style "fg=$surface"
set -g pane-active-border-style "fg=$primary"
set -g message-style "bg=$surface,fg=$fg"
set -g message-command-style "bg=$surface,fg=$fg"
set -g mode-style "bg=$primary,fg=$bg"
set -g clock-mode-colour "$primary"
set -g copy-mode-match-style "bg=$surface,fg=$accent"
set -g copy-mode-current-match-style "bg=$accent,fg=$bg"
EOF
mv "$tmux_conf" "$state_dir/tmux.conf"

# Told, not left to notice: a running server changes now.
"$tmux" source-file "$state_dir/tmux.conf" >/dev/null 2>&1 || true

# ---- btop ----
# btop only looks for themes inside its own config directory, so the file has to
# live there rather than in the state directory.
btop_themes="${XDG_CONFIG_HOME:-$HOME/.config}/btop/themes"
mkdir -p "$btop_themes"

btop_theme=$(mktemp "$btop_themes/.anixie.XXXXXX") || exit 1
cat >"$btop_theme" <<EOF
theme[main_bg]="$bg"
theme[main_fg]="$fg"
theme[title]="$primary"
theme[hi_fg]="$primary"
theme[selected_bg]="$surface"
theme[selected_fg]="$fg"
theme[inactive_fg]="$muted"
theme[proc_misc]="$accent"
theme[cpu_box]="$surface"
theme[mem_box]="$surface"
theme[net_box]="$surface"
theme[proc_box]="$surface"
theme[div_line]="$surface"
theme[temp_start]="$success"
theme[temp_mid]="$alt"
theme[temp_end]="$danger"
theme[cpu_start]="$success"
theme[cpu_mid]="$alt"
theme[cpu_end]="$danger"
theme[free_start]="$surface"
theme[free_mid]="$muted"
theme[free_end]="$muted"
theme[cached_start]="$surface"
theme[cached_mid]="$muted"
theme[cached_end]="$muted"
theme[available_start]="$muted"
theme[available_mid]="$muted"
theme[available_end]="$surface"
theme[used_start]="$primary"
theme[used_mid]="$accent"
theme[used_end]="$alt"
theme[download_start]="$primary"
theme[download_mid]="$accent"
theme[download_end]="$alt"
theme[upload_start]="$primary"
theme[upload_mid]="$accent"
theme[upload_end]="$alt"
EOF
mv "$btop_theme" "$btop_themes/anixie.theme"

# ---- terminal tools ----
# The zsh prompt uses ANSI names, which kitty now maps to the palette. bat and
# eza are told to use those same ANSI names, and fzf gets an explicit palette so
# its chrome does not stay on the default grey.
terminal_env="$state_dir/terminal.zsh"
terminal_tmp=$(mktemp "$state_dir/.terminal.XXXXXX") || exit 1
cat >"$terminal_tmp" <<EOF
export BAT_THEME=ansi
export EZA_COLORS='di=34:ln=36:ex=32:or=31:mi=31:*.tar=31:*.zip=31:*.gz=31:*.7z=31:*.jpg=35:*.png=35:*.mp4=35'
export FZF_DEFAULT_OPTS="\${FZF_DEFAULT_OPTS:-} --color=fg:$fg,bg:$bg,hl:$primary,fg+:$fg,bg+:$surface,hl+:$primary,info:$accent,prompt:$primary,pointer:$accent,marker:$success,spinner:$accent,header:$muted,border:$surface"
EOF
mv "$terminal_tmp" "$terminal_env"

# ---- user hooks ----
# Applications without a config format worth owning get a small contract instead:
# an executable under ~/.config/anixie/theme-hooks receives the palette in the
# environment after every switch.
hook_dir="${XDG_CONFIG_HOME:-$HOME/.config}/anixie/theme-hooks"
if [ -d "$hook_dir" ]; then
  for hook in "$hook_dir"/*.sh; do
    [ -x "$hook" ] || continue
    env ANIXIE_THEME="$name" ANIXIE_MODE="$mode" \
      ANIXIE_BG="$bg" ANIXIE_FG="$fg" ANIXIE_SURFACE="$surface" \
      ANIXIE_MUTED="$muted" ANIXIE_PRIMARY="$primary" ANIXIE_ACCENT="$accent" \
      ANIXIE_ACCENT_ALT="$alt" ANIXIE_YELLOW="$yellow" \
      ANIXIE_DANGER="$danger" ANIXIE_SUCCESS="$success" \
      "$hook" >/dev/null 2>&1 || true
  done
fi
