# Shot feedback: flash and impacts

What a shot looks like on screen, in the game's toon style: flat colours, hard edges, no textures. The code is
`game/gameplay/weapons/fx/` (`MuzzleFlash`, `ImpactFx` and two shaders) and `ShotEffects`, which `NightView` calls;
`game/tests/weapons/test_shot_feedback.gd` pins the behaviour. The view shake that goes with it is in
[Camera shake](camera-shake.md); the research is in [Shot feedback research](../research/shot-feedback.md).

## The muzzle flash

- **Three quads and one shader** (`flash_star.gdshader`), additive and unshaded, no light slot, no texture: a big spiky
  five-point star and a smaller one spun against it, both facing the camera, and a teardrop tongue along the barrel as
  the camera sees it. Two flat colours (an orange rim round a pale core), anti-aliased on the edge only.
- **Each shot differs:** a random spin and a random scale in 0.85 to 1.2 (`scale_range`), from a seeded generator, and it
  bursts and dies down: 1.15 times its size when it starts, 0.65 when it ends (`life_scale`).
- **At least three rendered frames and 60 ms** (`frames`, `seconds`): the later of the two. Counted in frames, so it is
  the same at 30 and 60 fps and in a capture; and in seconds, so a 144 Hz screen does not draw it for 14 ms. At 60 fps
  that is three frames; at 30 fps three; at 144 fps nine. Between shots it costs nothing: the node is hidden and not
  processed.
- **Drawn toward the camera** (`camera_lift`, 0.7 m, scaled down by the same ratio so it looks the same size): the quads
  lie in the muzzle's own plane, and the gun, the hand and the arm round the muzzle are nearer the shoulder camera than
  that plane and hid up to nine tenths of them. The star sits in a flat disc of glow (`halo`, `halo_fill`, the same quad
  and shader, no glow post effect: the Compatibility renderer has none).
- **On the weapon's `Muzzle`.** Every firearm model carries a `Muzzle` node at the barrel tip, `-Z` out of the barrel
  ([the convention](weapon-hold.md#the-muzzle-node)); `PlayerAnimation.muzzle_point` finds it, or makes one at the
  hold's `muzzle` point for a model that has none yet. The flash is a child of that node, made the first time it is
  needed, and goes with the weapon when it is swapped. It is the same for the local player, remote players and bots. The
  class with no model yet flashes at the server's muzzle, 0.6 m along the barrel (`ShotEffects.BARE_REACH`), where the
  fist is, so the body does not hide the flash.
- **A weapon's size** is `WeaponDef.flash_size`, metres across: pistol 0.30, SMG 0.32, flare gun 0.34, rifle 0.42,
  shotgun 0.58, crowbar 0 (no flash). Up to 1.5 times the size it had before the rework (#408).
- **The light** (`light_enabled`, warm, energy 2.0, range 3.4 m, no shadow, 0.25 m ahead of the muzzle) lasts the same
  time. At most one flash on the whole map holds it at a time (group `muzzle_flash_lit`), so a flash adds **one** light
  to a mesh's cap of 8 in the Compatibility renderer, whatever the number of players. It is off with
  `light_enabled = false`.

### How strong the flash must be

Measured on the screen, not in the scene (`game/tests/captures/flash_probe.gd` on the desktop, `tools/web_smoke/flash.py`
in the browser; how and why in [Muzzle flash research](../research/muzzle-flash.md)). The probe draws each frame again
without the flash and compares, so these are the flash's own pixels, at 1280 by 720, from the shoulder camera, hip and
aimed. The floors are in `game/tests/captures/flash_floors.json`, and a probe run (or the unit test of the floors) fails
under them:

| What | Floor | Why |
| --- | --- | --- |
| Frames the flash is seen on | at least 3 | 2 frames (33 ms at 60 fps) was the finding |
| Area of the flash's pixels | at least 0.25 % of the screen | before: 0.02 to 0.14 % |
| Height of the flash's pixels | at least 10 % of the screen height | before: 5.5 to 15 % |
| Hot pixels (luma 200 or more, risen by 16 or more) | at least 800 | before: 114 to 1 055 |
| Brightest pixel / mean rise of the flash's pixels | at least 240 / 55 of 255 | a flash is the brightest thing on the screen |
| The whole picture's brightening (flash and light) | at most 9 of 255 | it must not blind at night; before: 4.7 to 6.0 |

`game/tests/weapons/test_muzzle_flash_strength.gd` holds the numbers the probe cannot see in a headless run (how long at
30 to 240 fps, the star's share of the screen for every firearm, the lift, the light's energy and range) and that the
floors check itself fails a flash with two frames, a small one, a dim one and one that blinds.

## The impacts

Sizes are diameters in metres, and the old impact (a 0.2 m yellow sphere for a spark and a puff that swelled from 0.2
to 0.52) is the thing to beat: nothing drawn now passes 0.25 m, and the dust ends at 0.2 m.

| Where | Parts | Size | Life |
| --- | --- | --- | --- |
| Wall or anything else | spark (a four-point star, `flash_star`) | 0.09 | 2 frames |
| | dust puff, grey-tan with a light crescent | 0.09 growing to 0.20 | 0.28 s, fading from the first third |
| | dark mark, a dot (no decal) | 0.045 | 0.8 s, fading from 0.6 |
| Zombie | one small dark-red puff (0.42, 0.03, 0.05) | 0.06 growing to 0.14 | 0.22 s |

- The puff and the mark are billboards of one shader (`impact_puff.gdshader`): a disc with a lumpy edge and a crescent
  of light on one side, a flat colour, fading by `progress`. They are nudged 4 cm toward the camera so a wall does not
  cut them in half.
- **Pooled and capped.** `ImpactFx` makes slots (a spark, a puff and a mark each) when asked, up to `MAX_ACTIVE` = 24,
  reuses a finished one, and recycles the oldest alive past the cap. It stops processing when nothing is alive. A
  shotgun's eight pellets take eight slots; a whole machine-gun magazine never takes more than 24.
- **Zombie or wall.** The server's `shot_fired` event now carries `flesh`: the point of every zombie the shot hit. The
  view puffs red at each of those and draws the wall impact only at pellet ends that are not on a zombie and stopped
  short of the weapon's range (a rifle round that passes through a zombie puffs red and flies on). A swing that hits
  puffs red; a swing that misses draws nothing.
- A flare's burst and a board torn or mended use the wall impact (`ShotEffects.spark`): small, and short.

## Cost

Per shot: three quads and at most one light for three frames, and up to 24 slots of three quads, hidden unless alive. No
textures, no per-frame allocation after a slot is made, no `Environment` features. The browser measure is in
[Shot feedback research](../research/shot-feedback.md#the-web-check).

## Blood

A zombie that is hit bleeds where it was hit (#618): a **splash** at the wound and **marks** on the ground and the wall
behind it. The code is `BloodFx` (`game/gameplay/weapons/fx/blood_fx.gd`, two shaders: `blood_splash.gdshader` and
`blood_decal.gdshader`), reached through `ShotEffects.blood_hit` from the `damage_dealt` event; the numbers are in
`blood_tuning_default.tres` (`BloodTuning`, five `BloodClass` rows) and `game/tests/weapons/test_blood_fx.gd` pins them.

- **What the event carries.** `damage_dealt` has the wound's `point`, `headshot`, `melee`, `damage`, `pellets`, and now
  `weapon_id` and `dir` (the unit way the shot or blow went; ZERO for a burst). Events are plain dictionaries, so new
  keys need no `NetWire` version change (the policy is in `net_wire.gd`): every client that gets `damage_dealt` draws
  the same splash at the same point, and a client that has not got the keys (an older server) bleeds all round as a
  bullet does. A hit has no surface normal (a zombie is a set of hit shapes): the splash is flung along `dir`, and the
  marks ask the client's own world (`WorldCast`) for the ground and the wall.
- **By weapon** (`BloodTuning.kind_of`): a bullet (pistol, SMG), pellets (a gun that fires more than one: small drops, wide
  cone, more drops for each pellet that landed, two wall marks), a rifle (a gun of 60 damage or more: a narrow cone,
  long streaks, the farthest reach and two ground marks), a melee blow (a big blot and a tapering smear along the blow)
  and a blast (a burst all round, marks under it). Damage scales the size between 70 and 100 percent.
- **By headshot:** 1.5 times the drops, 1.3 times the reach and size, a third of the drops flung back as well, a brighter
  arterial red, and 1.4 times the marks, and a rifle shot or a headshot looks for the wall 1.6 times as far.
- **The splash** is one billboard quad and one shader, no texture and no particles (a `GPUParticles3D` costs two programs
  of its own on the web, [first-use hitches](../research/first-use-hitches.md)). The drops are drawn in the fragment
  shader as a function of `progress` and a seed, so a capture and a test see the same splash: up to 16 drops that fly on
  an eased path with gravity, round or stretched into streaks that shrink, a lumpy blot at the wound, and for a melee blow
  a smear. The shot's direction is taken into the camera's plane in `vertex()`; a shot straight away from the camera
  (the usual one from the shoulder) has no sideways part, so the cone opens to all round and the splash is a burst.
- **The marks** are flat quads lying on the surface (`+Z` is the normal) with a lumpy blot and satellite drops,
  stretched along the flow (dripping down a wall, thrown along the shot on the ground). They dry from wet red to dark
  and fade out over the last 40 percent of 30 s. They are lifted off the surface 1 cm plus 2 mm for each metre to the
  camera, or they flicker in the depth buffer.
- **Capped.** At most 24 splashes and `marks_desktop` = 64 / `marks_web` = 32 marks are alive; the one past the cap takes
  over the oldest, nothing is made while a night is played (the pools are made in `prewarm`), and `BloodFx` stops
  processing when nothing is alive. Both numbers name the platform they were measured on
  ([Hit blood research](../research/hit-blood.md)).
- **In the warm-up.** The warm-up replays a `damage_dealt` of a shotgun and of a rifle headshot, a mark and a blast burst
  (the stage has no ground to cast to), held still for three frames, so the two shaders' programs are built behind the
  loading screen.
