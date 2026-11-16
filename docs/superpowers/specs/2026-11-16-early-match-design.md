# Early match result for ELAN 04f3:0c6e touch mode (short design)

## Intent / why
Today the match result only appears after the finger is lifted, so the user
can't tell whether the reading worked and keeps the finger down longer than
needed. Goal: the match / no-match result is reported while the finger is
still on the sensor.

## Why it is late today
`capture_run_state` (elan.c) keeps polling until the finger is lifted
(`CAPTURE_CHECK_ENOUGH_FRAMES` drain loop), and only `capture_complete` calls
`elan_submit_image()` -> `fpi_image_device_image_captured()`. Matching and
`fpi_device_verify_report()` happen right after that call, so everything waits.
The lift wait itself must stay: starting the next calibration with a finger on
the sensor makes it answer 0xaf and aborts enrollment.

## Goals
- Verify/identify: result reported as soon as ~ELAN_MAX_FRAMES frames are held,
  finger still down.
- Enrollment stages also advance early (same code path).
- Lift gate unchanged: stop_capture / next calibration only after finger off.

## Non-goals / anti-goals
- No change to matching, thresholds, or other devices/drivers.
- Must not reintroduce the 0xaf abort or double-report a result.

## Approaches considered
1. **(chosen)** Submit the image early, keep polling for lift afterwards.
2. Emit a "captured" signal early, match after lift: no real result early.
3. Shorten the lift wait: doesn't fix it, risks 0xaf.

## Design (my calls, adjustable)
- Add `touch_submitted` flag to `FpiDeviceElan`, reset in `elan_dev_reset_state`.
- In `CAPTURE_CHECK_ENOUGH_FRAMES`, touch mode, first time `num_frames >=
  ELAN_MAX_FRAMES`: call `elan_submit_image()`, set flag, then continue the
  existing drain loop unchanged.
- In `capture_complete`: if flag set, don't submit again; a timeout or an
  unexpected pre-scan reply (0xaf) after the early submit just ends the lift
  wait (no retry_scan, no session error). Then `elan_stop_capture` runs as now
  and reports finger-off, which completes the action.
- Short touches (< ELAN_MAX_FRAMES, >= ELAN_MIN_FRAMES) behave exactly as today.
- Trigger frame count is a named constant (`ELAN_TOUCH_SUBMIT_FRAMES`, default
  = ELAN_MAX_FRAMES) so it can be lowered if 30 frames takes too long; I'll
  measure the time on the real sensor.
- Delivered by regenerating `patches/0001-...patch`; rebuild with build.sh.

## Verification
Live `fprintd-verify` with timestamps: result time vs. lift time; enrolled
finger (match), other finger (no-match), repeated back-to-back verifies
(no 0xaf), short tap, and one enroll run.

## Open risk, checked during testing
Whether fprintd/GNOME UI shows the early `verify-match` signal immediately or
only on completion. If only on completion, a small fprintd-side follow-up is
needed; the driver change is still required.
