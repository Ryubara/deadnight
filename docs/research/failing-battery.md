# The back lot's failing-battery lights

Issue #851 (the maintainer's decision: the back lot is lit but dimmed, its lights blinking as if the battery is going
out and struggling to stay on). The back lot's posts, `Lamp13` to `Lamp17`, hang on the `back_lot` circuit (they were
the field's), and every light of the group burns through `FailingBattery` (`world/drive_in/failing_battery.gd`).

## The shape

A pure function of the time and the lamp's number (`FailingBattery.level(seconds, lamp)`), seeded by
`LightTuning.failing_seed`; `LotLamps` keeps time by the frame's tick (60 a second), so a recording, a test and every
client see the same lights. The picture only: the rules' lit ground (`LotLamps.lit_at`) stays whole while the circuit
is on.

| Part | What it does |
| --- | --- |
| Base | 0.6 of the lamp's light, wandering by 0.08 over two slow sines (5.3 s and 2.1 s), a different phase for each lamp |
| Cycle | 3.6 s; one event at most, the same for every lamp (the battery is one): calm 30%, sag 25%, stutter 25%, dropout 20% |
| Sag | a slow dip of 55% and back in 0.9 s (smooth) |
| Stutter | two quick dips (0.08 s down, 0.14 s at the floor, 0.14 s up; then a second at 80%) |
| Dropout | out for 0.4 s, then a stumbling recovery (back to 35%, up to 80%, then smooth) over 0.65 s |
| Per lamp | a depth of 60 to 100% of the dip, a delay of up to 0.05 s, a one-in-four chance of sitting an event out |
| Floor | 12% of the base: the lights never go out, so a Compatibility mesh never changes its set of lights (and a pool and a halo never switch off) |

The look lives in `LightTuning` (`failing_base`, `failing_wander`, `failing_floor`, `failing_cycle`, `failing_seed`).

## Not a strobe

The common guidance (WCAG 2.3.1, Three Flashes or Below Threshold, and the Harding test's general flash) is no more than
three flashes in any second, a flash being an opposing pair of changes of at least 10% of the relative luminance. The
shape keeps it by construction: a cycle holds at most two dips, ends within 1.8 s of its start and the next starts at
least 1.5 s after (`REST_SECONDS`), and the lamps share the cycle's event, so the lamps together never make more
events than one lamp does. `tests/world/test_failing_battery.gd` counts the flashes of every lamp and of their mean over
15 minutes with a hysteresis counter (and shows that a 12-a-second strobe fails it, so the counter cannot pass by
seeing nothing): the most in a second is 3 for one lamp (a dropout's stumbling recovery) and 2 for the lamps together.
The fastest fall is 0.16 of the full light in one 60 Hz tick. From the player's camera the whole frame's mean
luminance moves by under 3% between the brightest and the deepest frame of an 11 s clip (the lamps are small in it),
far under the general flash threshold.

The tank's own brownout (`LotLamps.brightness`, the last tenth of the tank) changes each lamp 12 times a second, out of
step with the next lamp. It is not used on the back lot: a failing lamp under a low tank is `failing_brightness`, the
battery's flicker times the tank's sag, never both flickers.

## For a sign to follow

A sign follows the flicker by following a lamp of the group, as `LotNeonSign` follows its lamp: `LightFollower.level`
is the lamp's energy over its scene energy, and the lamp's energy is the circuit, the tank and `FailingBattery`
together. The back lot's `NeonSign` omni is already in the group (`BackLot/Lamps`, `metadata/flicker =
"failing_battery"`), so a `LotNeonSign` with `light_path` on it flickers with the lot and goes dark with the circuit.
A node that is not a lamp can call `FailingBattery.level(seconds, lamp_number)` itself.
`test_a_sign_follows_the_flicker_through_the_lamp_it_follows` is the example.

## From behind the wall (#832's method)

Compatibility has no shadows, so a light reaches through a wall by its range and a ground pool (a flat additive card)
by its size. The four posts near the back lot's walls (13, 17 by the east wall, 15, 16 by the field's south fence)
leaked: with the back lot's lamp parts hidden against shown (`tests/captures/back_lot_flicker_tour.tscn`
`--hide=Pool|Halo|Light`, the player's camera in the midway and in the field, the other side of the wall), pixels that
changed:

| View | Pool before | Pool after | Light before | Light after |
| --- | ---: | ---: | ---: | ---: |
| midway, 11 m from the east wall, z 25 | 28,346 | 0 | 148,293 | 0 |
| midway, z 15 | 41,366 | 0 | 303,102 | 0 |
| field, by the south fence, x -20 | 27,946 | 0 | 142,489 | 0 |
| field, by the south fence, x -44 | 67,854 | 0 | 327,622 | 0 |

The fix is on the post (`LampPost.away`, written by the generator for the posts within 10 m of a wall): its light is a
spot, in the same slot as the omni, with a 30 degree cone aimed down and away from the wall. A cone never crosses the
vertical plane of its apex when `sin(tilt) * c >= sin(30)`, `c` being how squarely the wall faces away from the aim: 32
degrees from straight down for a post by one wall, 47 for the two in a corner (16 and 17). The pool is smaller and
moved away so that it stops short of the wall (its half-size is `d / (1 - c/2)`). The halo still shows over the wall
top: it is the bulb's, and the bulb is seen. No new light, no new draw call. The aimed spot's box reaches the same
meshes as the omni's sphere did (`test_lot_light_cap.gd` holds the tile budget; a first try with a 38 degree cone
tilted 65 reached one tile more and failed it).

Not changed here: the field's posts near the same fences (the field's own lamps), room lamps (#841), the apron's (#850),
the back lot's `NeonSign` omni (#852 replaces it with a sign).
