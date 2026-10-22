#!/bin/sh
# Local model usage for the bar.
#
#   model-usage.sh [days]
#
# Prints one JSON object. opencode already has a stats command, but it only
# prints a table, so the few fields the widget needs are pulled out of it here.
# Claude's CLI has no stats command; its session logs carry per-message usage,
# so those are summed over the same window. Nothing is uploaded and nothing
# outside these two local tools is consulted.
#
# This is approximate by nature: opencode's table rounds token counts and Claude
# logs may contain the same request more than once. It is a usage glance, not a
# billing record.

set -u

days="${1:-1}"
case "$days" in
  '' | *[!0-9]*) days=1 ;;
esac
[ "$days" -ge 1 ] || days=1

oc_sessions=0
oc_cost=0
oc_input=0
oc_output=0
oc_cache=0
oc_model=""

if command -v opencode >/dev/null 2>&1; then
  stats=$(opencode stats --days "$days" --models 1 2>/dev/null | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' || true)

  value=$(
    printf '%s\n' "$stats" \
      | sed -n 's/.*Sessions *\([0-9][0-9]*\) *│.*/\1/p' \
      | head -n 1
  )
  [ -n "$value" ] && oc_sessions=$value

  value=$(
    printf '%s\n' "$stats" \
      | sed -n 's/.*Total Cost *\$\([0-9][0-9.]*\) *│.*/\1/p' \
      | head -n 1
  )
  [ -n "$value" ] && oc_cost=$value

  value=$(
    printf '%s\n' "$stats" \
      | sed -n 's/.*Input *\([0-9][0-9.]*[KMGkmg]*\) *│.*/\1/p' \
      | head -n 1
  )
  [ -n "$value" ] && oc_input=$value

  value=$(
    printf '%s\n' "$stats" \
      | sed -n 's/.*Output *\([0-9][0-9.]*[KMGkmg]*\) *│.*/\1/p' \
      | head -n 1
  )
  [ -n "$value" ] && oc_output=$value

  value=$(
    printf '%s\n' "$stats" \
      | sed -n 's/.*Cache Read *\([0-9][0-9.]*[KMGkmg]*\) *│.*/\1/p' \
      | head -n 1
  )
  [ -n "$value" ] && oc_cache=$value

  value=$(
    printf '%s\n' "$stats" \
      | sed -n '/MODEL USAGE/{n;n;s/^│ *//;s/ *│$//;p;q;}' \
      | head -n 1 \
      | tr -d '"\\'
  )
  [ -n "$value" ] && oc_model=$value
fi

cl_sessions=0
cl_input=0
cl_output=0
cl_cache=0

if command -v jq >/dev/null 2>&1 && [ -d "$HOME/.claude/projects" ]; then
  totals=$(
    find "$HOME/.claude/projects" -name '*.jsonl' -type f -mtime -"$days" -print0 2>/dev/null \
      | xargs -0 -r jq -r '
          select(.message.usage)
          | [
              (.sessionId // .session_id // ""),
              (.message.usage.input_tokens // 0),
              (.message.usage.output_tokens // 0),
              (.message.usage.cache_creation_input_tokens // 0),
              (.message.usage.cache_read_input_tokens // 0)
            ]
          | @tsv
        ' 2>/dev/null \
      | awk -F '\t' '
          {
            if ($1 != "") seen[$1] = 1
            input += $2
            output += $3
            cache += $4 + $5
          }
          END {
            for (key in seen) sessions++
            printf "%d %d %d %d\n", sessions, input, output, cache
          }
        '
  )

  if [ -n "$totals" ]; then
    # shellcheck disable=SC2086
    set -- $totals
    cl_sessions=${1:-0}
    cl_input=${2:-0}
    cl_output=${3:-0}
    cl_cache=${4:-0}
  fi
fi

printf '{"days":%s,"opencode":{"sessions":%s,"cost":"%s","input":"%s","output":"%s","cache":"%s","model":"%s"},"claude":{"sessions":%s,"input":%s,"output":%s,"cache":%s}}\n' \
  "$days" "$oc_sessions" "$oc_cost" "$oc_input" "$oc_output" "$oc_cache" "$oc_model" \
  "$cl_sessions" "$cl_input" "$cl_output" "$cl_cache"
