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
The capture (`game/tests/captures/flare_lure.tscn`, from the player's shoulder camera) shows the muzzle flash, the
burning flare and a zombie coming in; the flare must be aimed slightly down to land in view (a level shot flies over the
roofs, 60 m).

## A pitfall

A test that read a weapon's number as "positive" (`damage > 0` for every shipped weapon, and a blast test that used
the flare as its only splash weapon) broke, or passed for nothing, when the flare's role changed. A test of the model
should build its own definition; a test of the catalogue should ask the weapon what it is (`is_lure()`).
