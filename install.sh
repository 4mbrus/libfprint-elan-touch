#!/bin/sh
# Install the patched libfprint next to the system one and point only fprintd
# at it. Run ./build.sh first, then: sudo ./install.sh
# Nothing from the system packages is overwritten; uninstall.sh undoes all of it.
set -eu
HERE="$(dirname "$(readlink -f "$0")")"
LIB="$HERE/build/libfprint/_build/libfprint/libfprint-2.so.2.0.0"
DEST=/opt/libfprint-elan-touch
DROPIN=/etc/systemd/system/fprintd.service.d/elan-touch.conf

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
[ -f "$LIB" ] || { echo "$LIB not found - run ./build.sh first"; exit 1; }

echo "1/4 installing library to $DEST"
install -d "$DEST/lib"
install -m 0644 "$LIB" "$DEST/lib/libfprint-2.so.2.0.0"
ln -sf libfprint-2.so.2.0.0 "$DEST/lib/libfprint-2.so.2"
install -m 0644 "$HERE"/patches/*.patch "$DEST/"
install -m 0755 "$HERE/uninstall.sh" "$DEST/uninstall.sh"

echo "2/4 pointing fprintd at it"
install -d "$(dirname "$DROPIN")"
cat > "$DROPIN" <<EOF
# Added by libfprint-elan-touch install.sh. Remove with $DEST/uninstall.sh
[Service]
Environment=LD_LIBRARY_PATH=$DEST/lib
# Tuning (defaults shown):
#Environment=ELAN_TOUCH_THRESHOLD=12
#Environment=ELAN_TOUCH_ENROLL_STAGES=15
EOF

echo "3/4 keeping the OpenCV runtime libraries installed"
if command -v apt-mark >/dev/null 2>&1; then
  pkgs="$(dpkg-query -W -f '${Package}\n' 'libopencv-*' 2>/dev/null |
          grep -E '^libopencv-(core|imgproc|features2d|calib3d|flann)[0-9.]+[a-z]*$' || true)"
  [ -n "$pkgs" ] && apt-mark manual $pkgs >/dev/null
fi

echo "4/4 restarting fprintd"
pkill -f /usr/libexec/fprintd 2>/dev/null || true
systemctl daemon-reload
systemctl stop fprintd 2>/dev/null || true
sleep 1
fprintd-list "${SUDO_USER:-root}" >/dev/null 2>&1 || true
PID="$(systemctl show -p MainPID --value fprintd)"
if [ "$PID" != 0 ] && grep -q "$DEST/lib/libfprint-2.so" "/proc/$PID/maps"; then
  echo
  echo "OK: fprintd (pid $PID) is using the patched library."
  echo "Existing fingerprints from the stock driver won't match; enroll again:"
  echo "  fprintd-delete \$USER && fprintd-enroll -f right-index-finger"
else
  echo
  echo "WARNING: fprintd does not seem to be using the patched library. Check: journalctl -u fprintd -b"
  exit 1
fi
