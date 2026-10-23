# libfprint-elan-touch

Makes the **ELAN `04f3:0c6e`** fingerprint reader work on Linux **by touch**,
like it does on Windows. Tested on an ASUS Vivobook M3401QC running Debian 13
(libfprint 1.94.9, fprintd 1.94.5).

With stock libfprint this reader enrolls, but verification never matches
(see [libfprint#401](https://gitlab.freedesktop.org/libfprint/libfprint/-/issues/401)).

## Why stock libfprint fails

- The `elan` driver treats this reader as a **swipe** sensor and stitches frames
  together. When you hold your finger still, as you do on Windows, the result is a smeared image.
- Swiping works no better: the frame stitching distorts each swipe differently, so swipes
  scored 0–12 against each other (24 is needed to match).
- A single clean touch is only 150×52 px and contains just 0–4 minutiae, far
  too few for libfprint's NBIS/bozorth3 matcher.

## What this patch does

[`patches/0001-elan-0c6e-touch-mode-sift-matching.patch`](patches/0001-elan-0c6e-touch-mode-sift-matching.patch)
against libfprint **v1.94.9**:

- **Touch mode for `0c6e` only.** Instead of stitching, it uses the single frame with
  the strongest contact. It keeps polling until the finger is lifted, so the
  next calibration never runs with a finger on the sensor; otherwise the
  sensor answers `0xaf` and enrollment aborts.
- **SIFT matching** (`libfprint/sigfm/`). It extracts SIFT keypoints, applies Lowe's ratio test,
  then fits a rigid RANSAC model (rotation + shift, scale rejected). The score is the number of
  geometrically consistent matches. A single touch has about 100–140 SIFT keypoints, against
  0–4 minutiae.
- **New print type `FPI_PRINT_SIGFM`**, with save/load support so fprintd can store
  the prints.
- **Retry instead of abort** if the sensor still sends an unexpected reply.
- **Defaults:** 15 enroll touches, match threshold 12.

Other devices and drivers are unaffected: the SIFT path is enabled per device
by the driver.

### Results (one person, one laptop)

| Test | Result |
|---|---|
| Offline: 4 enrolled touches vs 4 new index touches | 4/4 matched (scores 19–28) |
| Offline: index vs middle finger, 32 pairs | highest score 3 (threshold 12) |
| Live fprintd: enrolled finger | 5/5 matched |
| Live fprintd: different finger | 0/3 matched |

This is a small sample. It shows the matcher separates fingers, but it is
**not** a measurement of the false-accept rate. Treat it as a convenience
unlock, like most laptop fingerprint readers.

## Install

Requirements (Debian/Ubuntu names):

```sh
sudo apt install git meson ninja-build g++ pkg-config libglib2.0-dev libgusb-dev \
  libopencv-core-dev libopencv-imgproc-dev libopencv-features2d-dev \
  libopencv-calib3d-dev libopencv-flann-dev
```

Build and install:

```sh
./build.sh          # clones libfprint v1.94.9, applies the patch, builds the ELAN driver
sudo ./install.sh   # installs to /opt/libfprint-elan-touch and points fprintd at it
```

Enroll and test:

```sh
fprintd-delete "$USER"                 # old prints from the stock driver won't match
fprintd-enroll -f right-index-finger   # 15 touches, hold ~1 s each, shift slightly between them
fprintd-verify
scripts/verify_test.sh                 # optional: 5 tries enrolled finger + 3 tries another finger
```

### What `install.sh` changes

| Path | Purpose |
|---|---|
| `/opt/libfprint-elan-touch/lib/libfprint-2.so.2` | patched library |
| `/etc/systemd/system/fprintd.service.d/elan-touch.conf` | `LD_LIBRARY_PATH` for fprintd only |
| `/opt/libfprint-elan-touch/uninstall.sh` | undo |

The distribution's `libfprint-2-2` package is not touched, so package updates
don't overwrite the fix. The OpenCV runtime libraries are marked as manually
installed, so `apt autoremove` keeps them.

**Limitation:** the library is built with only the `elan` driver, so other USB
fingerprint readers won't be detected while it is installed.

## Uninstall

```sh
sudo /opt/libfprint-elan-touch/uninstall.sh
```

This also deletes your enrolled prints, since the stock driver can't use them.

## Tuning

Edit `/etc/systemd/system/fprintd.service.d/elan-touch.conf` and uncomment:

- `ELAN_TOUCH_THRESHOLD` (default 12): a higher value is stricter.
- `ELAN_TOUCH_ENROLL_STAGES` (default 15): more stages cover more of the finger.

Then run `sudo systemctl daemon-reload && sudo systemctl stop fprintd` and re-enroll.

### More fingerprint tries for sudo

Debian's `pam_fprintd` profile allows only one fingerprint try for sudo. The GDM login and
lock screens already allow 3. To allow 3 tries everywhere:

```sh
sudo sed -i 's/pam_fprintd.so max-tries=1/pam_fprintd.so max-tries=3/' /usr/share/pam-configs/fprintd
sudo pam-auth-update --package
```

A `libpam-fprintd` update may reset this.

## Debugging

```sh
sudo scripts/debug_start.sh && fprintd-enroll -f right-index-finger; sudo scripts/debug_stop.sh
# log: scripts/fprintd-debug.log (contains your username; don't post it unredacted)
```

## Credits and license

- Based on [libfprint](https://gitlab.freedesktop.org/libfprint/libfprint), licensed LGPL-2.1-or-later.
- The SIFT matcher's API and integration approach follow **SIGFM** by Matthieu
  Charette, Natasha England-Elbro and Timur Mangliev
  ([goodix-fp-linux-dev/libfprint](https://github.com/goodix-fp-linux-dev/libfprint), `sigfm` branch).
  This patch uses a RANSAC consistency check instead of SIGFM's pairwise angle voting.
- This patch and scripts are released under the same license,
  **LGPL-2.1-or-later** (see [LICENSE](LICENSE)).

Not affiliated with ELAN, ASUS or the libfprint project.
