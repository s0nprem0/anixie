#!/usr/bin/env bash
set -euo pipefail

wifi_qr="@WIFI_QR@"
wl_copy="@WL_COPY@"

if [[ ${1:-} == "--copy" ]]; then
  "$wifi_qr" --password | "$wl_copy"
else
  exec "$wifi_qr" --password
fi
