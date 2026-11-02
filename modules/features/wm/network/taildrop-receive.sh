#!/usr/bin/env bash
set -euo pipefail

tailscale="@TAILSCALE@"
notify="@NOTIFY@"
xdg_open="@XDG_OPEN@"
jq="@JQ@"

downloads="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"
staging="$downloads/.taildrop"

mkdir -p "$staging"

claim() {
  local source="$1"
  local name="${source##*/}"
  local base="${name%.*}"
  local ext="${name#"$base"}"
  local candidate
  local index=0

  [[ -n "$base" ]] || {
    base="$name"
    ext=""
  }

  while ((index < 1000)); do
    if ((index == 0)); then
      candidate="$downloads/$name"
    else
      candidate="$downloads/$base-$index$ext"
    fi

    if ln -- "$source" "$candidate" 2>/dev/null; then
      rm -f -- "$source"
      printf '%s\n' "$candidate"
      return 0
    fi

    [[ -e "$candidate" ]] || return 1
    ((index++))
  done

  return 1
}

announce() {
  local path="$1"
  local name="${path##*/}"
  local args=(-g "󰒊" -u critical "Taildrop: $name" "Saved to $downloads" --exec "$xdg_open" "$path")

  case "${name,,}" in
    *.png | *.jpg | *.jpeg | *.gif | *.webp | *.avif | *.bmp | *.tif | *.tiff)
      args=(-i "$path" "${args[@]}")
      ;;
  esac

  "$notify" "${args[@]}" >/dev/null 2>&1 || true
}

deliver() {
  local file
  local target

  while IFS= read -r -d '' file; do
    target=$(claim "$file") || continue
    announce "$target"
  done < <(find "$staging" -mindepth 1 -maxdepth 1 -type f -print0)
}

state() {
  "$tailscale" status --json 2>/dev/null |
    "$jq" -r '.BackendState // "Unknown"' 2>/dev/null || echo "Unknown"
}

deliver

while true; do
  # Taildrop only has a queue once the node is logged in. Asking for it before
  # that fails with "Taildrop disabled; no storage directory", which used to
  # repeat in the journal every ten seconds.
  if [ "$(state)" != "Running" ]; then
    sleep 60
    continue
  fi

  if "$tailscale" file get --wait --conflict=rename "$staging"; then
    deliver
  else
    sleep 60
  fi
done
