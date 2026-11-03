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

## Bots fire it (#646)

What a bot that fires the flare at a spot far from a body (`BotFlare`, [bots](bots.md#phase-5-team-play-revives-and-edge-cases))
learned about the flare:

- **It is direct fire at what the view meets.** The server aims the barrel at the first thing the view ray meets
  (`AimResolver.aim_direction`: a wall, the ground, a zombie), or along the view when it meets nothing within 40 m,
  and the flare falls at 4 m/s^2 from there. From the eye (1.55 m) a flare to the ground 15 m away is a view pitch of
  -0.05 rad and one to 22 m is -0.07: a grazing angle, so one degree of pitch moves the landing by about 2.5 m at 15 m
  and 5.5 m at 22 m. A bot aims within a degree and checks the shot with the view turned about two degrees of
  yaw and one of pitch each way before it orders it.
- **It bursts on the first thing it meets**, wall or zombie (`projectile_burst` `kind`), at the height it met it, so a
  car or a dead in the way is the end of the flare, five metres out. The lure uses the flat distance, so a burst on a
  car roof draws the dead as well as one on the ground, and a flare that finds nothing in its 2.5 s bursts in the air
  up to 80 m on (the lure is where it was, along the ground).
- **The drive-in shuts most lanes.** The cars in the rows are 1.0 to 1.4 m tall, as high as the flare flies for the first
  part of its fall. From a scan of the field (24 headings by four distances from each place on a 3 m grid, the real
  flight against the real world), 7 to 50 of the 96 shots from a place land where they were aimed, and about a quarter
  of the places have fewer than 20. In the soak a bot that wanted a flare found no shot about two times in five.
  The flare is a tool for a lane, which is what a person needs too.
- **The dead do not chase the downed.** `ZombieSim` is given only the players that stand (`targets` leave out the
  downed), so a pack "at the body" walks to the nearest player who is up, the reviver. A test that parks a pack at a body
  gets a pack that walks away to the bot at once; it is the bot's trouble, not the body's, that the flare relieves.
- **The lure is worth about eight seconds.** The dead within 25 m of it start for it; a revive that begins inside the
  burn (the hold is 3.5 s) is held with the pack away. The risk check counts a lured zombie as starting for the body
  when the lure is out (`Threat.delay`).

The scenario (`tests/night/test_bot_flare.gd`) and the unit tests (`tests/bots/test_bot_flare.gd`) run on the real
server and the real lot. The capture is the downed person's own shoulder camera
(`tests/captures/bots_revive.tscn --scenario=flare`, through `gds godot` with Movie Maker at 10 fps, 220 frames): the
pack beside the person, the flare in flight over the bot's shoulder, the flare burning in the lane and the dead
walking off to it, and the bot at the body, "Player 2 is pulling you up", with nothing near.

## A pitfall

A test that read a weapon's number as "positive" (`damage > 0` for every shipped weapon, and a blast test that used
the flare as its only splash weapon) broke, or passed for nothing, when the flare's role changed. A test of the model
should build its own definition; a test of the catalogue should ask the weapon what it is (`is_lure()`).
