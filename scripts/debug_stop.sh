#!/bin/sh
# Stop the debug fprintd; the normal service starts again on demand. Run with sudo.
HERE="$(dirname "$(readlink -f "$0")")"
kill "$(cat "$HERE/.fprintd-debug.pid" 2>/dev/null)" 2>/dev/null
rm -f "$HERE/.fprintd-debug.pid"
chown "${SUDO_USER:-root}" "$HERE/fprintd-debug.log" 2>/dev/null
echo "debug fprintd stopped"
