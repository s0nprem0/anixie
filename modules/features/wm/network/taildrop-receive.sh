#!/usr/bin/env bash
set -euo pipefail

tailscale="@TAILSCALE@"
notify="@NOTIFY@"
xdg_open="@XDG_OPEN@"

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

deliver

while true; do
  if "$tailscale" file get --wait --conflict=rename "$staging"; then
    deliver
  else
    sleep 10
  fi
done
