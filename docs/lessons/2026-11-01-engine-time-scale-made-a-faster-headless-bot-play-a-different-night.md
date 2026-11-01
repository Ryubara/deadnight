# `Engine.time_scale` made a faster headless bot play a different night

2026-11-01

- **Symptom:** an autopilot run at `Engine.time_scale = 10` started round 1 after 1 s of ticks instead of 12 s (#158).
- **Cause:** `time_scale` scales the delta each `_physics_process` receives, so the "fixed" step grows and the rules
  see a different night than the one at normal speed.
- **Fix:** leave `time_scale` at 1 and run several fixed ticks in each physics frame (`Night.ticks_per_frame`), each
  with the constant step: about 1,500 ticks a second, the same night.
- **Documented:** [the autopilot](../design/slice.md#the-autopilot).
