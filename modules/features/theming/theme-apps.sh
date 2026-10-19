#!/bin/sh
# The files the other applications read their colours from.
#
# Rendered when the theme changes rather than when the system is built, which is
# the difference between a theme that reaches the editor and one that waits for a
# rebuild. Each file lives where its application looks for it and is rewritten on
# every switch; the applications pick it up at their next start (tmux is told, so
# a running server changes at once).
set -eu

palettes="@PALETTES@"
state_dir="@STATE_DIR@"
jq="@JQ@"
tmux="@TMUX@"
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
danger=$(colour danger)
success=$(colour success)

mkdir -p "$state_dir"

# ---- tmux ----
cat >"$state_dir/tmux.conf" <<EOF
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

# Told, not left to notice: a running server changes now.
"$tmux" source-file "$state_dir/tmux.conf" >/dev/null 2>&1 || true

# ---- btop ----
# btop only looks for themes inside its own config directory, so the file has to
# live there rather than in the state directory.
btop_themes="${XDG_CONFIG_HOME:-$HOME/.config}/btop/themes"
mkdir -p "$btop_themes"

cat >"$btop_themes/anixie.theme" <<EOF
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
