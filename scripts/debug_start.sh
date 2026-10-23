#!/bin/sh
# Run fprintd with debug logging in the background. Run with sudo.
#   sudo scripts/debug_start.sh [LIBDIR] && fprintd-enroll -f right-index-finger; sudo scripts/debug_stop.sh
# LIBDIR defaults to the installed patched library.
set -eu
HERE="$(dirname "$(readlink -f "$0")")"
LOG="$HERE/fprintd-debug.log"
LIB="${1:-/opt/libfprint-elan-touch/lib}"

systemctl stop fprintd 2>/dev/null || true
pkill -f /usr/libexec/fprintd 2>/dev/null || true
sleep 1
LD_LIBRARY_PATH="$LIB" G_MESSAGES_DEBUG=all \
  nohup /usr/libexec/fprintd -t > "$LOG" 2>&1 &
echo $! > "$HERE/.fprintd-debug.pid"
sleep 1
echo "debug fprintd running (log: $LOG)"
