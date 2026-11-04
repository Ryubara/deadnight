# The arrival: what it costs, and what building it taught

Issue #1057. What the helicopter drop is, and how to tune it, is in [the arrival](../design/arrival.md); this page is the
measured side. Kit page for the next cutscene of this kind: [A cutscene one client plays](https://github.com/Ryubara/gdstudio/blob/main/docs/godot/client-cutscene.md).

## The budget

The show is a fixed set of parts, built when it begins and freed when it ends: the helicopter (1,264 triangles, three
meshes: body, main rotor, tail rotor), a rope (one box), a Soldier of the player's look (the parts of the look only; the
far levels stay hidden), one unshadowed spot lamp and its haze (one cone, one draw, the lot's `beam.gdshader`), and a
canvas layer of three black rectangles. About 20 visible meshes, 1 light, 4 draws of its own; the rest of its cost is
**what the high camera sees of the lot**, which is more than the player's own.

Measured with `game/tests/captures/arrival_budget.tscn` (the engine's counts in each physics frame of the show, one
arm to a process, windowed on an RTX 5080), and in the web build with `tools/web_smoke/arrival_web.py` (WebGL calls in
each page frame, Chrome with the GPU, [the web docs' method](web-export.md)):

| | Draw calls (engine) | Triangles | Notes |
| --- | --- | --- | --- |
| The lot, the player's own camera | 31 | 21 k | at the first spawn, facing the wall |
| The lot, the show | 234 (max 247) | 100 k (max 107 k) | the camera sees the cars of the field |
| The lot, the show, lamp and haze out | 233 | 100 k | the light is about 1 draw; it is not what costs |
| The lot, a late join over 20 dead (round 1 at 5 times the usual count, 70 s in) | 242, against 47 | 129 k, against 85 k | the dead are far from the high camera, so far levels |
| The back rooms, the player's own camera | 605 | 81 k | |
| The back rooms, the show | 379 (max 465) | 61 k | the roof and ceilings are hidden for the show, so less is drawn |

| In the browser (WebGL draws a frame) | The show | The night after |
| --- | --- | --- |
| The lot, desktop window | 448 (437 to 464) | 108 |
| The lot, phone size 844 x 390 | 525 (489 to 543) | 112 |
| The back rooms, desktop window | 795 (744 to 851) | 1,170 |
| The lot, a late join on a live server | 201 mean over the window (102 to 481, it begins in the window) | 121 |

The lot's show is about four times the lot's own view for 3.8 to 6.5 s, at the level of a night with 40 dead on the web
(about 490, [crowd budget](crowd-budget.md)), and the HUD (125 draws, [performance](performance.md)) is hidden meanwhile.
The dead stay far from the high camera (about 35 m), so they are drawn at their far levels, which is why 20 of them add
8 draws. The back rooms' show is cheaper than the map's own view.

What it leaves behind: nodes return to the count before it (3,451 before and after on the lot, 1,708 on the back
rooms), orphans 0, objects +9 and resources +6 (the helicopter's mesh and materials and its three sounds, cached for the
next show). `tools/perf/budget.json` is unaffected: the autopilot never plays the show.

Loading: the `arrival` sound bank (57 KB of Ogg Vorbis) is `on_demand`, so the night's loading bar, the background
decode and the warm-up manifest skip it (`SoundCatalog.ids_for_night`, tested); the model and the three sounds load at
the black the show starts from. A player who never meets the show (a bot, a test, `?noarrival`) loads none of it.

## The web

Played in the browser as a person plays it, on the lot, on the back rooms, phone size with a skip two seconds in (the
night's show ended 0.8 s after the press) and as a late join to a live server with a bot in the night (the page's show
was 3.8 s, no fly-in): HUD hidden for the show and back after, no console error.

A page that asks for the probes skips the show unless it asks for it too (`WebProbe.asked`; `?arrival`): the 55 probes of
`tools/web_smoke/` start a night and act from its first frame, and none needed an edit.

## The sound

Synthesised (`tools/audio/arrival_recipes.py`): a 4 s seamless loop of ten rotor beats a second (a low thump from 105 to
58 Hz, a mid slap, a trace of crack; each beat's place jittered, the last beat wrapping to the first), the blades' wash
(noise from 220 Hz to 3.2 kHz pulsing at the beat), a 60 Hz engine saw low-passed at 700 Hz and the tail rotor's 400 Hz
whine, all in whole cycles, so the seam is 0.008 against a 99th percentile step of 0.027. The weight is kept above 55 Hz
so a phone's speaker carries the beat. In a recording of the show the loop is 50 dB under its level at the first half
second (far off, and the helicopter 70 m away) and at its level by 1.5 s, and falls with the fade. That is judged by
numbers, not by ear: the sound is for the maintainer's ears.

## What went wrong on the way

- The first camera sat behind the drive-in's screen (the spot is by it), and the helicopter was cropped by the top edge
  ([lesson in the kit](https://github.com/Ryubara/gdstudio/blob/main/docs/lessons/2026-11-04-a-cutscene-camera-at-a-fixed-offset-stood-behind-the-lots-screen.md)).
- A new rules action needs a sample in `test_validation.gd` ([lesson](../lessons/2026-11-04-a-new-rules-action-had-no-sample-in-the-validation-suite.md)).
- A new run-time light, sound export and sound group each failed a suite that pins the lights and sound tables
  ([lesson](../lessons/2026-11-04-pinning-tests-in-other-folders-failed-for-a-new-light-and-a-new-sound-field.md)).
- A test that named `WarmupManifest` left scripts in use at exit and failed its shard on the leak gate
  ([lesson](../lessons/2026-11-04-a-test-that-named-the-warm-up-manifest-failed-the-leak-gate.md)).
