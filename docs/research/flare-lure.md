# The flare lure

What building the flare as a lure (#439) taught us. The design is in
[Zombies: the flare lure](../design/zombies.md#the-flare-lure).

## Shape that worked

- **A lure is data the sim steps, not a target.** `ZombieLure` is a `RefCounted` (id, position, radius, seconds left)
  held in `ZombieSim.lures`. The zombie's own target logic is untouched: while a lure calls it, the sim skips the retarget
  and hands the brain the lure's position as the place to walk to. When the lure ends the old logic is simply back.
- **Zombies remember which lure they follow** (`ZombieBody.lure_id`). A change of lure sets the repath timer to 0, so the
  zombie finds a new way at once instead of finishing the old path.
- **The standing-about distance must be inside the swing's reach.** At the flare the zombie has nothing to hit; it
  stops 2.5 m out and turns to face it (`ZombieBrain.face`), rather than walking onto it and shuffling.
- **The exceptions are tuning flags**, not code branches: boards, bosses and swings are each one `ZombieTuning` bool, so
  the maintainer's call is a number to change.
- **The client draws and decides nothing.** `LureView` takes the server's `seconds`, flickers a halo, rises embers and
  fades out over the last second. It makes no light: the lot's light cap (`test_lot_light_cap`) leaves room for a
  flash and a blast only.

## Tests

The sim tests step `ZombieSim` by hand; the night test runs a whole night with `Night.Mode.MANUAL`, puts a zombie 12 m
from the burst and watches 6 simulated seconds. `NightFixture` and a tick of 1/60 s keep it free of real time.
The capture (`game/tests/captures/flare_lure.tscn`) fires from the player's shoulder camera, then cuts to a camera
17 m straight up over the flare: four zombies put 8 to 10 m to either side of it, across the line to the player, so
walking to the flare and walking to the player look different. It prints each zombie's distance to the flare and to
the player every second: they close from 7 to 9 m to about 2 m of the flare while the distance to the player stays
about 7 m, hold there for the 8 s, then turn to the player. A level shot flies over the roofs (60 m), so the flare is
aimed slightly down to land in view; from 40 m up a zombie is a speck, 17 m reads.

The HUD's bottom-left line is the equipment slot (the weapon put away), not the weapon in hand: during the capture the
ammunition card read "Flare gun 0 / 6" and the slot "Revolver", which is right.

## A pitfall

A test that read a weapon's number as "positive" (`damage > 0` for every shipped weapon, and a blast test that used
the flare as its only splash weapon) broke, or passed for nothing, when the flare's role changed. A test of the model
should build its own definition; a test of the catalogue should ask the weapon what it is (`is_lure()`).
