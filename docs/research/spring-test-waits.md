# How a UI test waits for a spring

A `UISpring` runs on a fixed 1/240 s step (`UISpring.step` adds the frame's delta to a carry and takes one step for each
whole 1/240 s in it), so it ends in the same place at any frame rate, and a frame shorter than 4.17 ms moves nothing.
A test that waits a count of frames and reads the value is therefore a test of the machine's frame time. The frame-time
story is in [windowed vs headless tests](windowed-vs-headless-tests.md); this page is the recipe the five spring suites
share (#1219, after the check box in #1215).

## The recipe

Each suite has the same two helpers and the same cap (`SETTLE_SECONDS := 5.0`, slack and not a tolerance):

- `_leave(spring, from)`: frames until `spring.value` is no longer `from`, summing `get_process_delta_time()`.
- `_settle(spring)`: frames until `spring.is_settled()`, the same cap.

A case then reads: change the thing, one `await_idle_frame()`, assert the spring's `target` (the one thing a frame does
settle), `_leave`, assert the value is past its start and below 1.0 (it is a spring, not a snap), `_settle`, assert
`is_settled()` and the exact end value. The old `is_equal_approx(1.0, 0.02)` is `is_equal(1.0)` now: a settled spring
snaps to its target.

A case that must see nothing happen (pointer focus lights no ring) cannot wait for a settled spring; it watches a length
of frame time (`_watch(0.6)`, longer than a ring takes to rise) and asserts the target and the value stayed at 0.

## What changed

| Suite | Case | Old wait | Failed first at |
| --- | --- | --- | --- |
| `test_ui_toggle` | `test_the_knob_rides_a_spring_to_the_new_side` | 120 frames | 1000 and 480 frames a second |
| `test_ui_slider` | `test_the_fill_follows_the_value_on_a_spring` | 120 frames | 1000 |
| `test_ui_option_selector` | `test_the_slide_runs_on_a_spring_without_reduced_motion` | 120 frames | 1000 and 480 |
| `test_ui_button_ring` | `test_keyboard_focus_lights_the_ring_and_pointer_focus_does_not` | 90 frames (and 60 for the "not lit" half) | 1000 |

`test_ui_button_ring` was not in the issue: a search of `game/tests/` for suites that read a spring's `value` found it.
The other readers of a spring (`test_settings_layout` waits in time, `test_ui_scroll` runs with reduced motion, which
snaps, `test_gds_ui_self` steps the spring by hand) were already right.

## Proof

`--fixed-fps N` makes every frame the same length, headless (`-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a <suite>
-c --ignoreHeadlessMode`) or in a window (`gds godot -- --path . --fixed-fps N ...`). The four suites, old then new:

- 1000 frames a second, headless: old 4 of 4 fail (one case each), new 4 of 4 pass. 480: old toggle and selector fail,
  slider and ring pass; new all pass. 240: old and new all pass.
- New, headless, at 480, 240, 120, 60, 10 and the unfixed rate: 24 of 24 runs pass; at 1000: 4 of 4.
- New, in a window, at 1000, 480, 10 and the window's own rate: 16 of 16 pass; old, in a window at 1000: 4 of 4 fail.
- Loaded (four suites at once, three rounds): headless 12 of 12, headless at 1000 12 of 12, windowed 12 of 12.
