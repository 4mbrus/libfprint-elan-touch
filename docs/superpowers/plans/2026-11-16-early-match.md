# Early Match Result Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In touch mode (ELAN 04f3:0c6e) report the match result while the finger is still down.

**Architecture:** Submit the best frame via `elan_submit_image()` once `ELAN_TOUCH_SUBMIT_FRAMES` frames are held, then continue the existing lift-wait drain loop; `capture_complete` skips the submit and the retry/error paths if the image was already submitted.

**Tech Stack:** C (libfprint 1.94.9 `elan` driver), meson/ninja, fprintd 1.94.5.

**Spec:** `docs/superpowers/specs/2026-11-16-early-match-design.md`

## Global Constraints

- Only touch mode (`dev_type & ELAN_TOUCH`) changes; other devices/drivers unaffected.
- Lift gate unchanged: `elan_stop_capture` / next calibration only after finger off (no `0xaf` abort).
- Short touches (>= `ELAN_MIN_FRAMES` 7, < submit threshold) behave exactly as today.
- Source of truth is `patches/0001-elan-0c6e-touch-mode-sift-matching.patch`; edit `build/libfprint`, then regenerate the patch.
- No sudo by the agent: the user runs `sudo ./install.sh` (suggest `! sudo ./install.sh`).

## Review Focus

- Finger lifted before the threshold: single submit via the old path, no double report.
- Stray `0xaf` / PROTO error during the lift wait after early submit: no retry_scan, no session error.
- Lift wait hits `ELAN_TOUCH_MAX_EXTRA_FRAMES` (finger held ~10 s) after early submit: no second submit.
- Back-to-back verifies right after an early result: next calibration must succeed.
- Enroll: all 15 stages still advance, one early submit per touch, flag reset between touches.

(Hardware-bound driver: no unit-test harness exists, so each line is pinned by a live check in Task 2.)

---

### Task 1: Early submit in the capture state machine

**Files:**
- Modify: `build/libfprint/libfprint/drivers/elan.h` (near `ELAN_TOUCH_MAX_EXTRA_FRAMES`, ~line 44)
- Modify: `build/libfprint/libfprint/drivers/elan.c` (struct ~line 86, `elan_dev_reset_state` ~line 114, `capture_run_state` ~line 613, `capture_complete` ~line 640)

**Interfaces:**
- Produces: `#define ELAN_TOUCH_SUBMIT_FRAMES ELAN_MAX_FRAMES`; field `gboolean touch_submitted` in `FpiDeviceElan`.

- [ ] **Step 0: Baseline.** Before editing, run `git -C build/libfprint diff > <scratchpad>/before.diff` and confirm its hunks match the committed patch body. Expected: identical; if not, stop and tell the user.
- [ ] **Step 1: Add the constant and field.** In elan.h define `ELAN_TOUCH_SUBMIT_FRAMES` (= `ELAN_MAX_FRAMES`, with a comment: frames held before the result is reported early). In the `FpiDeviceElan` struct add `gboolean touch_submitted;` beside `extra_frames`; set it `FALSE` in `elan_dev_reset_state`.
- [ ] **Step 2: Early submit.** In `capture_run_state`, `CAPTURE_CHECK_ENOUGH_FRAMES`, touch-mode drain branch: before dropping the oldest frame, if `!self->touch_submitted && self->num_frames >= ELAN_TOUCH_SUBMIT_FRAMES`, call `elan_submit_image (idev)` and set `touch_submitted = TRUE`. Drain logic otherwise unchanged. Log `fp_dbg ("touch: result submitted early, waiting for finger off")`.
- [ ] **Step 3: Guard `capture_complete`.** When `touch_submitted` is TRUE: skip `elan_submit_image` and the "swipe too short" retry; treat timeout, success, and `FP_DEVICE_ERROR_PROTO` all as normal end of lift wait; clear `error`; still call `elan_stop_capture (self)`. Any other error keeps going to `fpi_image_device_session_error`.
- [ ] **Step 4: Build.** Run `./build.sh`. Expected: ninja finishes with no warnings from elan.c, prints "Built: ...libfprint-2.so.2.0.0".
- [ ] **Step 5: Commit** later with Task 2 (patch regeneration), so the commit contains the patch, not `build/`.

### Task 2: Live verification, patch regeneration, docs

**Files:**
- Modify: `patches/0001-elan-0c6e-touch-mode-sift-matching.patch` (regenerated)
- Modify: `README.md` (one bullet under "What this patch does"; one line for `ELAN_TOUCH_SUBMIT_FRAMES` if made env-tunable, otherwise omit)
- Use: `scripts/verify_test.sh`, `scripts/debug_start.sh`

- [ ] **Step 2: Install (user).** Ask the user to run `! sudo ./install.sh`. Expected: "4/4 restarting fprintd", `fprintd-list $USER` shows the sensor.
- [ ] **Step 3: Timing test.** Run `fprintd-verify` with the enrolled finger and keep it down for ~5 s; use `date +%T.%N` stamps or `scripts/debug_start.sh` logs. Expected: `verify-match` appears before the lift, within ~ the time to collect 30 frames (record the number).
- [ ] **Step 4: Review Focus checks.** (a) wrong finger: `verify-no-match` early; (b) quick tap (< 30 frames): result as before, one report; (c) 5 back-to-back verifies: all produce results, no `0xaf` / "unexpected pre-scan reply" aborts in the debug log; (d) hold the finger ~12 s: one result, no second one; (e) re-enroll one finger (`fprintd-enroll -f right-index-finger`): 15 stages complete. Record the outcomes.
- [ ] **Step 5: UI check.** Lock-screen / GNOME prompt (and `fingerprint-animation` extension): note whether the success shows before the lift. If only after, report it as the fprintd-side follow-up named in the spec; do not fix it in this task.
- [ ] **Step 6: If 30 frames is too slow,** lower `ELAN_TOUCH_SUBMIT_FRAMES` (not below `ELAN_MIN_FRAMES` + `ELAN_SKIP_LAST_FRAMES`), rebuild, repeat Steps 3-4, and check match scores did not drop (debug log scores vs. the 19-28 baseline in the README).
- [ ] **Step 7: Regenerate the patch.** `git -C build/libfprint diff > patches/0001-elan-0c6e-touch-mode-sift-matching.patch` keeping the existing header lines; check that `git apply --check` passes on a fresh v1.94.9 clone made in the scratchpad directory.
- [ ] **Step 8: Commit.** `git add patches docs README.md && git commit -m "Report touch-mode match result before finger lift"` ending with the Co-Authored-By line from the session.
