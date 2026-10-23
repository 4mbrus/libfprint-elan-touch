#!/bin/sh
# Undo install.sh: fprintd goes back to the system libfprint. Run with sudo.
# Fingerprints enrolled with the patched library won't work with the stock
# one, so they are deleted too (re-enroll if a future libfprint supports this reader).
set -eu
DEST=/opt/libfprint-elan-touch
DROPIN=/etc/systemd/system/fprintd.service.d/elan-touch.conf

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

if [ -n "${SUDO_USER:-}" ]; then
  fprintd-delete "$SUDO_USER" >/dev/null 2>&1 || true
fi
rm -f "$DROPIN"
rmdir --ignore-fail-on-non-empty "$(dirname "$DROPIN")" 2>/dev/null || true
systemctl daemon-reload
systemctl stop fprintd 2>/dev/null || true
rm -rf "$DEST"
echo "Removed. fprintd now uses the system libfprint again."
echo "Optional: mark the OpenCV runtime libraries (libopencv-core*, -imgproc*, -features2d*, -calib3d*, -flann*) as auto with apt-mark,"
echo "          remove the -dev build dependencies, then run apt autoremove."
