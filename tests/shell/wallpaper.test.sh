#!/bin/sh
set -eu

root=${REPO_ROOT:-$(pwd)}
JQ=${JQ:-jq}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/state/live" "$tmp/lib"

printf '#!/bin/sh\nprintf %%s\\\\n \x27[{"name":"eDP-1","width":1920,"height":1200},{"name":"HDMI-A-1","width":2560,"height":1440}]\x27\n' >"$tmp/bin/hyprctl"
cat >"$tmp/bin/mpvpaper" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/mpvpaper.log"
EOF
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/quickshell"
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/pgrep"
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/pkill"
cat >"$tmp/bin/magick" <<'EOF'
#!/bin/sh
for last; do :; done
: >"$last"
EOF
cat >"$tmp/bin/ffmpeg" <<'EOF'
#!/bin/sh
for last; do :; done
: >"$last"
EOF
chmod +x "$tmp/bin/"*

sed \
  -e "s|@STATE_DIR@|$tmp/state|g" \
  -e "s|@DATA_DIR@|$tmp/data|g" \
  -e "s|@WALLPAPER_DIRS@|'$tmp/lib'|g" \
  -e "s|@WALLPAPER_RECURSIVE@|false|g" \
  -e "s|@PALETTES@|$root/modules/features/theming/themes.json|g" \
  -e "s|@DEFAULT_THEME@|tokyo-night|g" \
  -e "s|@JQ@|$(command -v jq)|g" \
  -e "s|@MAGICK@|$tmp/bin/magick|g" \
  -e "s|@FFMPEG@|$tmp/bin/ffmpeg|g" \
  -e "s|@MPVPAPER@|$tmp/bin/mpvpaper|g" \
  -e "s|@HYPRCTL@|$tmp/bin/hyprctl|g" \
  -e "s|@PGREP@|$tmp/bin/pgrep|g" \
  -e "s|@PKILL@|$tmp/bin/pkill|g" \
  -e "s|@QUICKSHELL@|$tmp/bin/quickshell|g" \
  -e "s|@SHA256SUM@|$(command -v sha256sum)|g" \
  -e "s|@STAT@|$(command -v stat)|g" \
  -e "s|@WIDTH@|1920|g" \
  -e "s|@HEIGHT@|1080|g" \
  -e "s|@ANIXIE_LIB@|$root/modules/features/cli/lib.sh|g" \
  "$root/modules/features/theming/wallpaper.sh" >"$tmp/wallpaper"

jq '.["tokyo-night"]' "$root/modules/features/theming/themes.json" >"$tmp/state/live/palette.json"
printf 'tokyo-night\n' >"$tmp/state/current"
printf 'dark\n' >"$tmp/state/mode"
printf 'image\n' >"$tmp/lib/a.png"
printf 'image\n' >"$tmp/lib/b.png"
printf 'video\n' >"$tmp/lib/v.mp4"

HOME="$tmp/home" sh "$tmp/wallpaper" library --json >"$tmp/library.json"
"$JQ" -e 'length == 4 and any(.[]; .name == "a.png") and any(.[]; .video == true)' "$tmp/library.json" >/dev/null

HOME="$tmp/home" sh "$tmp/wallpaper" use "$tmp/lib/a.png" --output eDP-1 >/dev/null
"$JQ" -e --arg p "$tmp/lib/a.png" '.outputs["eDP-1"].path == $p and .outputs["eDP-1"].video == false' "$tmp/state/background.json" >/dev/null

HOME="$tmp/home" sh "$tmp/wallpaper" use "$tmp/lib/v.mp4" --output HDMI-A-1 >/dev/null
"$JQ" -e '.outputs["HDMI-A-1"].video == true' "$tmp/state/background.json" >/dev/null
grep -q 'HDMI-A-1' "$tmp/mpvpaper.log"

HOME="$tmp/home" sh "$tmp/wallpaper" generated >/dev/null
"$JQ" -e '.outputs["eDP-1"].video == false and .outputs["HDMI-A-1"].video == false
  and (.outputs["eDP-1"].path | contains("/state/wallpapers/"))' "$tmp/state/background.json" >/dev/null

[ "$(HOME="$tmp/home" sh "$tmp/wallpaper" status)" = "running" ]
HOME="$tmp/home" sh "$tmp/wallpaper" pause
[ "$(HOME="$tmp/home" sh "$tmp/wallpaper" status)" = "paused" ]
HOME="$tmp/home" sh "$tmp/wallpaper" resume
[ "$(HOME="$tmp/home" sh "$tmp/wallpaper" status)" = "running" ]

HOME="$tmp/home" sh "$tmp/wallpaper" next >/dev/null
HOME="$tmp/home" sh "$tmp/wallpaper" rotate >/dev/null
"$JQ" -e '.version == 1' "$tmp/state/wallpapers.json" >/dev/null
