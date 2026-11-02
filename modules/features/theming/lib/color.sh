#!/bin/sh
# POSIX color helpers for the theming scripts.

color_ok() {
  printf '%s' "$1" | grep -Eq '^#[0-9a-fA-F]{6}$'
}

# WCAG 2.x relative luminance for a #RRGGBB color.
color_luminance() {
  color_ok "$1" || return 1
  awk -v c="$1" '
    function hx(x) { return index("0123456789abcdef", tolower(x)) - 1 }
    function byte(h, p) { return hx(substr(h, p, 1)) * 16 + hx(substr(h, p + 1, 1)) }
    function lin(v) {
      v = v / 255
      if (v <= 0.04045) return v / 12.92
      return ((v + 0.055) / 1.055) ^ 2.4
    }
    function lum(h,   r, g, b) {
      sub(/^#/, "", h)
      r = lin(byte(h, 1))
      g = lin(byte(h, 3))
      b = lin(byte(h, 5))
      return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    BEGIN { print lum(c) }
  ' </dev/null
}

color_contrast() {
  color_ok "$1" || return 1
  color_ok "$2" || return 1
  awk -v a="$1" -v b="$2" '
    function hx(x) { return index("0123456789abcdef", tolower(x)) - 1 }
    function byte(h, p) { return hx(substr(h, p, 1)) * 16 + hx(substr(h, p + 1, 1)) }
    function lin(v) {
      v = v / 255
      if (v <= 0.04045) return v / 12.92
      return ((v + 0.055) / 1.055) ^ 2.4
    }
    function lum(h,   r, g, b) {
      sub(/^#/, "", h)
      r = lin(byte(h, 1))
      g = lin(byte(h, 3))
      b = lin(byte(h, 5))
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

# Mix two colors in encoded sRGB. t is clamped to [0, 1].
color_mix() {
  color_ok "$1" || return 1
  color_ok "$2" || return 1
  awk -v a="$1" -v b="$2" -v t="$3" '
    function hx(x) { return index("0123456789abcdef", tolower(x)) - 1 }
    function byte(h, p) { return hx(substr(h, p, 1)) * 16 + hx(substr(h, p + 1, 1)) }
    BEGIN {
      if (t !~ /^-?[0-9]+([.][0-9]+)?$/) exit 1
      if (t < 0) t = 0
      if (t > 1) t = 1
      sub(/^#/, "", a)
      sub(/^#/, "", b)
      out = "#"
      for (i = 1; i <= 5; i += 2) {
        av = byte(a, i)
        bv = byte(b, i)
        ch = av + (bv - av) * t
        if (ch < 0) ch = 0
        if (ch > 255) ch = 255
        out = out sprintf("%02x", int(ch + 0.5))
      }
      print out
    }
  ' </dev/null
}

# Adjust foreground toward black or white until it reaches the target ratio
# against bg. Returns the original foreground when it already passes.
color_adjust_contrast() {
  color_ok "$1" || return 1
  color_ok "$2" || return 1
  awk -v fg="$1" -v bg="$2" -v want="$3" '
    function hx(x) { return index("0123456789abcdef", tolower(x)) - 1 }
    function byte(h, p) { return hx(substr(h, p, 1)) * 16 + hx(substr(h, p + 1, 1)) }
    function lin(v) {
      v = v / 255
      if (v <= 0.04045) return v / 12.92
      return ((v + 0.055) / 1.055) ^ 2.4
    }
    function lum(h,   r, g, b) {
      sub(/^#/, "", h)
      r = lin(byte(h, 1))
      g = lin(byte(h, 3))
      b = lin(byte(h, 5))
      return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    function ratio(a, b,   la, lb) {
      la = lum(a)
      lb = lum(b)
      if (la < lb) { t = la; la = lb; lb = t }
      return (la + 0.05) / (lb + 0.05)
    }
    function mix(a, b, t,   i, av, bv, ch, out) {
      sub(/^#/, "", a)
      sub(/^#/, "", b)
      out = "#"
      for (i = 1; i <= 5; i += 2) {
        av = byte(a, i)
        bv = byte(b, i)
        ch = av + (bv - av) * t
        if (ch < 0) ch = 0
        if (ch > 255) ch = 255
        out = out sprintf("%02x", int(ch + 0.5))
      }
      return out
    }
    BEGIN {
      if (want !~ /^[0-9]+([.][0-9]+)?$/) exit 1
      if (want + 0 <= 0) exit 1
      if (ratio(fg, bg) >= want + 0) {
        print fg
        exit 0
      }
      # choose the endpoint with higher contrast
      cBlack = ratio("#000000", bg)
      cWhite = ratio("#ffffff", bg)
      endpoint = cBlack >= cWhite ? "#000000" : "#ffffff"
      if (ratio(endpoint, bg) < want + 0) {
        # cannot reach target
        exit 1
      }
      lo = 0
      hi = 1
      for (i = 0; i < 40; i++) {
        mid = (lo + hi) / 2
        cand = mix(fg, endpoint, mid)
        if (ratio(cand, bg) >= want + 0) hi = mid
        else lo = mid
      }
      print mix(fg, endpoint, hi)
    }
  ' </dev/null
}

color_accent_name() {
  color_ok "$1" || return 1
  awk -v c="$1" '
    function hx(x) { return index("0123456789abcdef", tolower(x)) - 1 }
    function byte(h, p) { return hx(substr(h, p, 1)) * 16 + hx(substr(h, p + 1, 1)) }
    BEGIN {
      sub(/^#/, "", c)
      r = byte(c, 1) / 255
      g = byte(c, 3) / 255
      b = byte(c, 5) / 255
      max = r
      min = r
      if (g > max) max = g
      if (b > max) max = b
      if (g < min) min = g
      if (b < min) min = b
      d = max - min
      if (d < 0.08 || max < 0.1 || min > 0.9) {
        print "slate"
        exit
      }
      if (max == r) h = 60 * (((g - b) / d) % 6)
      else if (max == g) h = 60 * (((b - r) / d) + 2)
      else h = 60 * (((r - g) / d) + 4)
      if (h < 0) h += 360
      if (h < 15 || h >= 345) print "red"
      else if (h < 45) print "orange"
      else if (h < 70) print "yellow"
      else if (h < 160) print "green"
      else if (h < 200) print "teal"
      else if (h < 260) print "blue"
      else if (h < 320) print "purple"
      else print "pink"
    }
  ' </dev/null
}

color_palette_fix() {
  color_file=$1
  : "${JQ:=jq}"

  [ -f "$color_file" ] || return 1
  command -v "$JQ" >/dev/null 2>&1 || return 1
  "$JQ" -e 'type == "object"' "$color_file" >/dev/null 2>&1 || return 1

  color_tmp=$(mktemp "${color_file}.XXXXXX") || return 1
  cp "$color_file" "$color_tmp" || { rm -f "$color_tmp"; return 1; }

  # Text foregrounds that must remain readable. Decorative/accent colors are
  # left alone to preserve palette relationships.
  for color_key in foreground fgLight muted outline; do
    color_value=$("$JQ" -r --arg k "$color_key" '.[$k] // empty' "$color_tmp")
    [ -n "$color_value" ] || continue
    color_ok "$color_value" || { rm -f "$color_tmp"; return 1; }

    for color_bg in background surface; do
      color_bg_value=$("$JQ" -r --arg k "$color_bg" '.[$k] // empty' "$color_tmp")
      [ -n "$color_bg_value" ] || continue
      color_ok "$color_bg_value" || { rm -f "$color_tmp"; return 1; }

      color_fixed=$(color_adjust_contrast "$color_value" "$color_bg_value" 4.5) || { rm -f "$color_tmp"; return 1; }
      [ -n "$color_fixed" ] || { rm -f "$color_tmp"; return 1; }
      if [ "$color_fixed" != "$color_value" ]; then
        color_jq_tmp="${color_tmp}.jq"
        if ! "$JQ" --arg k "$color_key" --arg v "$color_fixed" '.[$k] = $v' "$color_tmp" >"$color_jq_tmp"; then
          rm -f "$color_tmp" "$color_jq_tmp"
          return 1
        fi
        mv "$color_jq_tmp" "$color_tmp"
        color_value=$color_fixed
      fi
    done
  done

  "$JQ" -e 'type == "object"' "$color_tmp" >/dev/null 2>&1 || { rm -f "$color_tmp"; return 1; }
  chmod --reference="$color_file" "$color_tmp" 2>/dev/null || true
  mv "$color_tmp" "$color_file"
}