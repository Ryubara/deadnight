# Two thumbs flicked the view: each finger's first drag had a wrong relative

2026-11-02

- **Symptom:** on a phone, looking with the right thumb while the left thumb moved the character made the view flick
  round fast (the maintainer, #497). One thumb alone was fine.
- **Cause:** found by logging every touch event (index, position, relative, owner) in Chrome with two fingers. The
  web runtime measures the first `InputEventScreenDrag.relative` of a finger from another position: the origin for
  the look finger (1454 px for a 100 px drag), the other finger's press for the stick finger. `velocity` was stale for
  three drags. A single finger's press seeds the position, so one thumb never showed it.
- **Fix:** `TouchControls` keeps each finger's last position and reads the step from the finger's own path, trusting
  `velocity` only after three drags; Aim now drags the view like Fire. Tests drive two indexes with the wrong first
  `relative` (`test_touch_player.gd`); `touch_look.py` has a two-finger case.
- **Documented:** [Web export research](../research/web-export.md), [Touch controls](../design/touch-controls.md).
