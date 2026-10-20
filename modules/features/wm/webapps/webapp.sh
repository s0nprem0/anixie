#!/bin/sh
# webapp — a website, in the application menu.
#
#   webapp add NAME URL     install it
#   webapp list             what is installed
#   webapp remove NAME      take it away again
#
# A site you use like an application deserves an entry in the launcher rather
# than a tab you hunt for. The entry is an ordinary .desktop file, which is what
# makes it show up everywhere — the menu, any launcher, the dock — without
# teaching the shell about it.
#
# Chromium in --app mode with a class of its own: that is the difference between
# "a browser window showing a site" and "an application", and the class is what
# lets a window rule or the dock treat it as one.
set -eu

apps="@APPS@"
browser="@BROWSER@"
update="@UPDATE_DB@"

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

# A name becomes the file's own name, so `list` and `remove` can name it back.
slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed -e 's/^-*//' -e 's/-*$//'
}

case "${1:-}" in
  "" | -h | --help | help)
    usage
    ;;
  add)
    [ $# -ge 3 ] || { usage >&2; exit 2; }
    name="$2"
    url="$3"

    case "$url" in
      http://* | https://*) ;;
      *)
        printf 'webapp: the address needs to be http:// or https://\n' >&2
        exit 2
        ;;
    esac

    id=$(slug "$name")
    [ -n "$id" ] || { printf 'webapp: a name needs a letter or a digit in it\n' >&2; exit 2; }

    mkdir -p "$apps"

    # No quotes around the address: .desktop parsing has its own escaping rules
    # and a wrongly escaped Exec is a menu entry that does nothing. An address
    # with a space in it is refused above rather than mangled here.
    cat > "$apps/webapp-$id.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$name
Comment=$url
Exec=$browser --app=$url --class=webapp-$id
Icon=web-browser
Terminal=false
Categories=Network;WebBrowser;
StartupWMClass=webapp-$id
EOF

    # Launchers cache the directory; without this a new entry can take a session
    # to appear.
    "$update" "$apps" 2>/dev/null || true
    printf 'webapp: installed "%s" (%s)\n' "$name" "$url"
    ;;
  list)
    found=0
    for file in "$apps"/webapp-*.desktop; do
      [ -f "$file" ] || continue
      found=1
      sed -n 's/^Name=//p' "$file"
    done
    [ "$found" -eq 1 ] || printf 'webapp: none installed\n'
    ;;
  remove)
    [ $# -ge 2 ] || { usage >&2; exit 2; }
    id=$(slug "$2")
    file="$apps/webapp-$id.desktop"
    if [ ! -f "$file" ]; then
      printf 'webapp: nothing called "%s"\n' "$2" >&2
      exit 1
    fi
    rm -f "$file"
    "$update" "$apps" 2>/dev/null || true
    printf 'webapp: removed "%s"\n' "$2"
    ;;
  *)
    printf 'webapp: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac
