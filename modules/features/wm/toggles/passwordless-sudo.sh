#!/bin/sh
# Is sudo passwordless for this user, and how would you change that?
#
#   passwordless-sudo        print "on" or "off"
#   passwordless-sudo edit   open the sudoers file in a terminal, for editing
#
# The check reads the effective rule out of the generated sudoers file rather than
# asking `sudo`, so it never prompts and never leaves a failed attempt in the
# auth log. The indicator is a status light, not a switch: changing sudo is a
# deliberate edit of a root file and a reboot of sudo's own config, so it is not
# something to toggle from a panel.
set -eu

SUDO="@SUDO@"
TERMINAL="@TERMINAL@"

# The check asks sudo what it will actually do, rather than reading /etc/sudoers.
# The file is 0440 and root-owned, so a user cannot read it at all — and a grep of
# a file it cannot open fails, which is indistinguishable from "sudo does ask for
# a password". That reported this machine as secure when it was the opposite.
#
# `sudo -n` never prompts: it lists the policy and exits whether or not a password
# would have been needed, which is exactly the answer wanted. The listing is the
# user's effective one, so it accounts for group membership rather than only for
# the rule written down.
passwordless() {
  if "$SUDO" -n -l 2>/dev/null | grep -q "NOPASSWD"; then
    printf 'on'
  else
    printf 'off'
  fi
}

case "${1:-}" in
  "" | status)
    passwordless
    ;;
  edit)
    # visudo, not a plain editor: it syntax-checks before it writes, so a typo in
    # a sudoers edit cannot lock you out of the machine entirely. Run it where a
    # password can be typed, which is what a terminal is for.
    exec "$TERMINAL" -e visudo
    ;;
  *)
    printf 'passwordless-sudo: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac