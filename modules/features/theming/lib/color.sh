#!/bin/sh

color_ok() {
  printf '%s' "$1" | grep -Eq '^#[0-9a-fA-F]{6}$'
}

color_luminance() {
  awk -v c="$1" '
    function hx(x) { return index("0123456789abcdef", tolower(x)) - 1 }
    function byte(h, p) { return hx(substr(h, p, 1)) * 16 + hx(substr(h, p + 1, 1)) }
    function lum(h,   r, g, b) {
      sub(/^#/, "", h)
      r = byte(h, 1) / 255
      g = byte(h, 3) / 255
      b = byte(h, 5) / 255
      r = r <= 0.03928 ? r / 12.92 : ((r + 0.055) / 1.055) ^ 2.4
      g = g <= 0.03928 ? g / 12.92 : ((g + 0.055) / 1.055) ^ 2.4
      b = b <= 0.03928 ? b / 12.92 : ((b + 0.055) / 1.055) ^ 2.4
      return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    BEGIN { print lum(c) }
  ' </dev/null
}

color_contrast() {
  awk -v a="$1" -v b="$2" '
    function hx(x) { return index("0123456789abcdef", tolower(x)) - 1 }
    function byte(h, p) { return hx(substr(h, p, 1)) * 16 + hx(substr(h, p + 1, 1)) }
    function lum(h,   r, g, b) {
      sub(/^#/, "", h)
      r = byte(h, 1) / 255
      g = byte(h, 3) / 255
      b = byte(h, 5) / 255
      r = r <= 0.03928 ? r / 12.92 : ((r + 0.055) / 1.055) ^ 2.4
      g = g <= 0.03928 ? g / 12.92 : ((g + 0.055) / 1.055) ^ 2.4
      b = b <= 0.03928 ? b / 12.92 : ((b + 0.055) / 1.055) ^ 2.4
      return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    BEGIN {
      la = lum(a)
      lb = lum(b)
      if (la < lb) {
        t = la
        la = lb
        lb = t
      }
      print (la + 0.05) / (lb + 0.05)
    }
  ' </dev/null
}

color_mix() {
  awk -v a="$1" -v b="$2" -v t="$3" '
    function hx(x) { return index("0123456789abcdef", tolower(x)) - 1 }
    function byte(h, p) { return hx(substr(h, p, 1)) * 16 + hx(substr(h, p + 1, 1)) }
    function mix(a, b, t,   h, i, av, bv, out) {
      sub(/^#/, "", a)
      sub(/^#/, "", b)
      out = "#"
      for (i = 1; i <= 5; i += 2) {
        av = byte(a, i)
        bv = byte(b, i)
        out = out sprintf("%02x", av + (bv - av) * t)
      }
      return out
    }
    BEGIN { print mix(a, b, t) }
  ' </dev/null
}

color_adjust_contrast() {
  awk -v fg="$1" -v bg="$2" -v want="$3" '
    function hx(x) { return index("0123456789abcdef", tolower(x)) - 1 }
    function byte(h, p) { return hx(substr(h, p, 1)) * 16 + hx(substr(h, p + 1, 1)) }
    function lum(h,   r, g, b) {
      sub(/^#/, "", h)
      r = byte(h, 1) / 255
      g = byte(h, 3) / 255
      b = byte(h, 5) / 255
      r = r <= 0.03928 ? r / 12.92 : ((r + 0.055) / 1.055) ^ 2.4
      g = g <= 0.03928 ? g / 12.92 : ((g + 0.055) / 1.055) ^ 2.4
      b = b <= 0.03928 ? b / 12.92 : ((b + 0.055) / 1.055) ^ 2.4
      return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    function ratio(a, b,   la, lb) {
      la = lum(a)
      lb = lum(b)
      if (la < lb) {
        t = la
        la = lb
        lb = t
      }
      return (la + 0.05) / (lb + 0.05)
    }
    function mix(a, b, t,   h, i, av, bv, out) {
      sub(/^#/, "", a)
      sub(/^#/, "", b)
      out = "#"
      for (i = 1; i <= 5; i += 2) {
        av = byte(a, i)
        bv = byte(b, i)
        out = out sprintf("%02x", av + (bv - av) * t)
      }
      return out
    }
    BEGIN {
      target = ratio("#ffffff", bg) >= ratio("#000000", bg) ? "#ffffff" : "#000000"
      if (ratio(fg, bg) >= want) {
        print fg
        exit
      }
      for (i = 1; i <= 20; i++) {
        candidate = mix(fg, target, i / 20)
        if (ratio(candidate, bg) >= want) {
          print candidate
          exit
        }
      }
      print target
    }
  ' </dev/null
}

color_palette_fix() {
  color_file=$1
  : "${JQ:=jq}"

  for color_key in foreground muted primary accent accentAlt secondary tertiary success yellow danger error; do
    color_value=$("$JQ" -r --arg k "$color_key" '.[$k] // empty' "$color_file")
    [ -n "$color_value" ] || continue

    for color_bg in background surface; do
      color_bg_value=$("$JQ" -r --arg k "$color_bg" '.[$k] // empty' "$color_file")
      [ -n "$color_bg_value" ] || continue

      color_fixed=$(color_adjust_contrast "$color_value" "$color_bg_value" 4.5)
      if [ "$color_fixed" != "$color_value" ]; then
        color_tmp=$(mktemp "$color_file.XXXXXX") || return 1
        if "$JQ" --arg k "$color_key" --arg v "$color_fixed" '.[$k] = $v' "$color_file" >"$color_tmp"; then
          mv "$color_tmp" "$color_file"
        else
          rm -f "$color_tmp"
          return 1
        fi
        color_value=$color_fixed
      fi
    done
  done
}
