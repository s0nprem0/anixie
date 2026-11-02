#!/bin/sh
set -eu

root=${REPO_ROOT:-$(pwd)}
. "$root/modules/features/theming/lib/auto.sh"

[ "$(auto_mode 07:00 19:00 08:00)" = light ]
[ "$(auto_mode 07:00 19:00 19:00)" = dark ]
[ "$(auto_mode 07:00 19:00 02:00)" = dark ]
[ "$(auto_mode 22:00 02:00 23:00)" = light ]
[ "$(auto_mode 22:00 02:00 01:00)" = light ]
[ "$(auto_mode 22:00 02:00 12:00)" = dark ]
