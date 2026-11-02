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
printf 'image' >"$last"
EOF
cat >"$tmp/bin/ffmpeg" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/ffmpeg.log"
for last; do :; done
printf 'frame' >"\$last"
EOF
chmod +x "$tmp/bin/"*

sed \
  -e "s|@STATE_DIR@|$tmp/state|g" \
  -e "s|@DATA_DIR@|$tmp/data|g" \
  -e "s|@WALLPAPER_DIRS@|'$tmp/lib'|g" \
  -e "s|@WALLPAPER_RECURSIVE@|false|g" \
  -e "s|@DEFAULT_WALLPAPER@|'$tmp/lib/a.png'|g" \
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
  -e "s|@FLOCK@|$(command -v flock)|g" \
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
[ -s "$tmp/state/library.json" ]
HOME="$tmp/home" sh "$tmp/wallpaper" library --json --refresh >"$tmp/library2.json"
"$JQ" -e 'length == 4' "$tmp/library2.json" >/dev/null

# The cache notices a file added behind the command's back, and keeps the
# existing thumbnails rather than rebuilding the whole library.
printf 'image\n' >"$tmp/lib/c.png"
HOME="$tmp/home" sh "$tmp/wallpaper" library --json >"$tmp/library3.json"
"$JQ" -e 'length == 5 and any(.[]; .name == "c.png")' "$tmp/library3.json" >/dev/null

# A configured default fills in before anything is chosen, for the fallback and
# for every output.
[ "$(HOME="$tmp/home" sh "$tmp/wallpaper" current)" = "$tmp/lib/a.png" ]
HOME="$tmp/home" sh "$tmp/wallpaper" apply >/dev/null
"$JQ" -e --arg p "$tmp/lib/a.png" '
  .fallback.path == $p
  and .outputs["eDP-1"].path == $p
  and .outputs["HDMI-A-1"].path == $p
' "$tmp/state/background.json" >/dev/null

HOME="$tmp/home" sh "$tmp/wallpaper" use "$tmp/lib/a.png" --output eDP-1 >/dev/null
"$JQ" -e --arg p "$tmp/lib/a.png" '.outputs["eDP-1"].path == $p and .outputs["eDP-1"].video == false' "$tmp/state/background.json" >/dev/null

HOME="$tmp/home" sh "$tmp/wallpaper" use "$tmp/lib/v.mp4" --output HDMI-A-1 >/dev/null
"$JQ" -e '.outputs["HDMI-A-1"].video == true and (.outputs["HDMI-A-1"].poster | length > 0)' "$tmp/state/background.json" >/dev/null
grep -q 'HDMI-A-1' "$tmp/mpvpaper.log"
# The poster is sampled a second in rather than taken from a fade-in.
grep -q -- '-ss 1' "$tmp/ffmpeg.log"

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

# `record` writes a choice without applying it, which is the path theme.sh uses
# after deriving a palette from a named picture.
HOME="$tmp/home" sh "$tmp/wallpaper" record "$tmp/lib/b.png" >/dev/null
"$JQ" -e --arg p "$tmp/lib/b.png" '
  .themes["tokyo-night"].fallback.path == $p
  and (.themes["tokyo-night"].outputs | length) == 0
' "$tmp/state/wallpapers.json" >/dev/null

# Two choices at once are a read-modify-write of the same file; the lock keeps
# one from overwriting the other. Both are applied, so the last apply wins the
# background, but both selections must survive.
HOME="$tmp/home" sh "$tmp/wallpaper" use "$tmp/lib/a.png" --output eDP-1 >/dev/null &
first=$!
HOME="$tmp/home" sh "$tmp/wallpaper" use "$tmp/lib/v.mp4" --output HDMI-A-1 >/dev/null &
second=$!
wait "$first"
wait "$second"
"$JQ" -e '
  .themes["tokyo-night"].outputs
  | has("eDP-1") and has("HDMI-A-1")
' "$tmp/state/wallpapers.json" >/dev/null

# Rotation is a persisted interval in minutes; zero turns it off. The shell
# reads the file, so the command only has to write and report it.
[ "$(HOME="$tmp/home" sh "$tmp/wallpaper" rotation)" = 0 ]
HOME="$tmp/home" sh "$tmp/wallpaper" rotation 30 >/dev/null
[ "$(cat "$tmp/state/rotation")" = 30 ]
[ "$(HOME="$tmp/home" sh "$tmp/wallpaper" rotation)" = 30 ]
if HOME="$tmp/home" sh "$tmp/wallpaper" rotation soon >/dev/null 2>&1; then exit 1; fi
if HOME="$tmp/home" sh "$tmp/wallpaper" rotation 1441 >/dev/null 2>&1; then exit 1; fi
HOME="$tmp/home" sh "$tmp/wallpaper" rotation 0 >/dev/null
[ "$(HOME="$tmp/home" sh "$tmp/wallpaper" rotation)" = 0 ]

# Caches only collect what is referenced or recent. A stale entry goes, while
# the thumbnail and poster in use survive even with an ancient mtime.
old='2020-01-01 00:00:00'
thumb=$("$JQ" -r '[.[] | .thumb | select(length > 0)][0]' "$tmp/state/library.json")
[ -s "$thumb" ]
printf 'stale\n' >"$tmp/state/thumbs/stale.jpg"
touch -d "$old" "$tmp/state/thumbs/stale.jpg" "$thumb"
HOME="$tmp/home" sh "$tmp/wallpaper" library --json --refresh >/dev/null
[ ! -e "$tmp/state/thumbs/stale.jpg" ]
[ -s "$thumb" ]

poster=$("$JQ" -r '.outputs["HDMI-A-1"].poster' "$tmp/state/background.json")
[ -s "$poster" ]
printf 'stale\n' >"$tmp/state/posters/stale.jpg"
printf 'stale\n' >"$tmp/state/wallpapers/tokyo-night-GONE.png"
printf '1920x1080\n' >"$tmp/state/wallpapers/tokyo-night-GONE.png.size"
touch -d "$old" "$tmp/state/posters/stale.jpg" "$poster" \
  "$tmp/state/wallpapers/tokyo-night-GONE.png" "$tmp/state/wallpapers/tokyo-night-GONE.png.size"
HOME="$tmp/home" sh "$tmp/wallpaper" apply >/dev/null
[ ! -e "$tmp/state/posters/stale.jpg" ]
[ -s "$poster" ]
[ ! -e "$tmp/state/wallpapers/tokyo-night-GONE.png" ]
[ ! -e "$tmp/state/wallpapers/tokyo-night-GONE.png.size" ]
