#!/bin/sh
# Is sudo passwordless for this user, and how would you change that?
#
#   passwordless-sudo        print "off", "partial" or "full"
#   passwordless-sudo edit   open the declarative setting in an editor
#
# "full" means NOPASSWD applies to ALL: this user can become root from the
# session without a password. "partial" means only some commands are
# passwordless — still worth saying, since one command is sometimes enough, but
# not the same claim as full root. "off" means sudo asks.
#
# The check asks sudo for the user's effective policy rather than reading
# /etc/sudoers: the file is 0440 and root-owned, so a user cannot read it at
# all. `sudo -n -l` never prompts *and* does not write a failed attempt to the
# auth log the way `sudo -n true` does; the latter logs "a password is required"
# on every probe of a machine where sudo asks.
#
# The listing is only available when listing itself does not require a password.
# If listpw makes it ask, the answer is "off": some rule is protected, so this is
# not a passwordless-root machine. A NOPASSWD rule hidden behind that case would
# be missed, which is why "partial" talks about commands rather than root.
#
# On NixOS, changing this is an edit of the declarative config, not of
# /etc/sudoers: activation regenerates that file, so a visudo edit would be
# silently undone by the next rebuild. `edit` therefore opens users.nix in the
# checkout, where wheelNeedsPassword lives.
set -eu

SUDO="@SUDO@"
TERMINAL="@TERMINAL@"
EDITOR="@EDITOR@"
REPO="@REPO@"

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

# NOPASSWD tags a rule; ALL is its command list when the rule is unrestricted.
# Rules are one line each, so ALL must be the whole command spec or an entry in
# it — not a word inside an argument such as `/bin/echo ALL`.
passwordless() {
  listing=$("$SUDO" -n -l 2>/dev/null) || {
    printf 'off'
    return
  }
  if printf '%s\n' "$listing" | grep -Eq \
    'NOPASSWD:[[:space:]]*ALL([[:space:]]*$|[[:space:]]*,)|NOPASSWD:.*,[[:space:]]*ALL([[:space:]]*$|[[:space:]]*,)'; then
    printf 'full'
  elif printf '%s\n' "$listing" | grep -q 'NOPASSWD:'; then
    printf 'partial'
  else
    printf 'off'
  fi
}

case "${1:-}" in
  -h | --help)
    usage
    ;;
  "" | status)
    passwordless
    ;;
  edit)
    file="$REPO/modules/system/users.nix"
    if [ ! -f "$file" ]; then
      die "no $file; edit security.sudo.wheelNeedsPassword in the NixOS config"
    fi
    # In a terminal, because the editor is a TUI. No --hold: the window is the
    # editor, and it should close when the editor does.
    exec "$TERMINAL" -e "$EDITOR" "$file"
    ;;
  *)
    die "unknown argument \"$1\" (try --help)"
    ;;
esac
