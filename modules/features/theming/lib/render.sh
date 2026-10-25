#!/bin/sh

: "${JQ:=jq}"
: "${SED:=sed}"

render_template() {
  render_source=$1
  render_palette=$2
  render_out=$3
  render_extras=${4:-}

  [ -n "${TOKENS_JSON:-}" ] || return 1
  [ -f "$render_source" ] || return 1
  [ -f "$render_palette" ] || return 1

  render_script=$(mktemp "${TMPDIR:-/tmp}/anixie-render.XXXXXX") || return 1

  "$JQ" -r --slurpfile tokens "$TOKENS_JSON" '
    ($tokens[0]) as $spec |
    . as $palette |
    ($spec.derived // {}) as $derivedMap |
    ($spec.colors | with_entries(.value = { key: .key, token: .value })) as $base |
    ($derivedMap | with_entries(.value = {
      key: .key,
      token: "ANSI_" + (.key | sub("^ansi"; ""))
    })) as $derived |
    (($base + $derived) | to_entries[]) |
    .value.key as $key |
    .value.token as $token |
    ($palette[$key] // (if $derivedMap[$key] != null then $palette[$derivedMap[$key]] else null end)) as $value |
    select($value != null and $value != "") |
    ("s|@" + $token + "@|" + $value + "|g"),
    ("s|@" + $token + "_HEX@|" + ($value | sub("^#"; "")) + "|g"),
    ($spec.alphas[] as $alpha |
      ($value | sub("^#"; "")) as $hex |
      ($alpha | ascii_downcase) as $suffix |
      ("s|@" + $token + "_ALPHA_" + $alpha + "@|#" + $hex + $suffix + "|g"),
      ("s|@" + $token + "_BARE_" + $alpha + "@|" + $hex + $suffix + "|g"),
      ("s|@" + $token + "_RGBA_" + $alpha + "@|rgba(" + $hex + $suffix + ")|g")
    )
  ' "$render_palette" >"$render_script" || {
    rm -f "$render_script"
    return 1
  }

  if [ -n "$render_extras" ] && [ -f "$render_extras" ]; then
    "$JQ" -r 'to_entries[] | "s|@" + .key + "@|" + (.value | tostring) + "|g"' \
      "$render_extras" >>"$render_script" || {
      rm -f "$render_script"
      return 1
    }
  fi

  render_tmp="$render_out.tmp.$$"
  if "$SED" -f "$render_script" "$render_source" >"$render_tmp"; then
    mv "$render_tmp" "$render_out"
  else
    rm -f "$render_tmp" "$render_script"
    return 1
  fi

  rm -f "$render_script"
  return 0
}
