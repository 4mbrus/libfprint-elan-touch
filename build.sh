#!/bin/sh
# Fetch libfprint, apply the touch-mode patch and build the ELAN driver.
# Result: build/libfprint/_build/libfprint/libfprint-2.so.2.0.0
set -eu
HERE="$(dirname "$(readlink -f "$0")")"
VERSION=v1.94.9
SRC="$HERE/build/libfprint"
PATCH="$HERE/patches/0001-elan-0c6e-touch-mode-sift-matching.patch"

missing=""
for t in git meson ninja g++ pkg-config; do
  command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
pkg-config --exists gusb glib-2.0 gio-unix-2.0 2>/dev/null || missing="$missing libgusb-dev/libglib2.0-dev"
for m in core imgproc features2d calib3d flann; do
  [ -e "/usr/include/opencv4/opencv2/$m.hpp" ] || missing="$missing libopencv-$m-dev"
done
if [ -n "$missing" ]; then
  echo "Missing build dependencies:$missing"
  echo "On Debian/Ubuntu:"
  echo "  sudo apt install git meson ninja-build g++ pkg-config libglib2.0-dev libgusb-dev \\"
  echo "    libopencv-core-dev libopencv-imgproc-dev libopencv-features2d-dev libopencv-calib3d-dev libopencv-flann-dev"
  exit 1
fi

if [ ! -d "$SRC" ]; then
  git clone --quiet --depth 1 --branch "$VERSION" \
    https://gitlab.freedesktop.org/libfprint/libfprint.git "$SRC"
  git -C "$SRC" apply "$PATCH"
  echo "Applied $(basename "$PATCH") to libfprint $VERSION"
fi

if [ ! -d "$SRC/_build" ]; then
  meson setup "$SRC/_build" "$SRC" --buildtype=release \
    -Ddrivers=elan -Dintrospection=false -Ddoc=false \
    -Dudev_rules=disabled -Dudev_hwdb=disabled -Dinstalled-tests=false
fi
ninja -C "$SRC/_build"

echo
echo "Built: $SRC/_build/libfprint/libfprint-2.so.2.0.0"
echo "Next:  sudo ./install.sh"
