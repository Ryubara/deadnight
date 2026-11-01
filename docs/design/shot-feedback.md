# Shot feedback: flash and impacts

What a shot looks like on screen, in the game's toon style: flat colours, hard edges, no textures. The code is
`game/gameplay/weapons/fx/` (`MuzzleFlash`, `ImpactFx` and two shaders) and `ShotEffects`, which `NightView` calls;
`game/tests/weapons/test_shot_feedback.gd` pins the behaviour. The view shake that goes with it is in
[Camera shake](camera-shake.md); the research is in [Shot feedback research](../research/shot-feedback.md).

## The muzzle flash

- **Three quads and one shader** (`flash_star.gdshader`), additive and unshaded, no light slot, no texture: a big spiky
  five-point star and a smaller one spun against it, both facing the camera, and a teardrop tongue along the barrel as
  the camera sees it. Two flat colours (an orange rim round a pale core), anti-aliased on the edge only.
- **Each shot differs:** a random spin and a random scale in 0.8 to 1.25 (`scale_range`), from a seeded generator.
- **Two rendered frames** (`frames`, 1 to 3). It is counted in frames, not seconds, so it is the same at any frame rate
  and in a capture. Between shots it costs nothing: the node is hidden and not processed.
- **On the weapon's `Muzzle`.** Every firearm model carries a `Muzzle` node at the barrel tip, `-Z` out of the barrel
  ([the convention](weapon-hold.md#the-muzzle-node)); `PlayerAnimation.muzzle_point` finds it, or makes one at the
  hold's `muzzle` point for a model that has none yet. The flash is a child of that node, made the first time it is
  needed, and goes with the weapon when it is swapped. It is the same for the local player, remote players and bots. The
  class with no model yet (the pistol, the flare gun: the hand stays empty) flashes at the server's muzzle, 0.6 m along
  the barrel (`ShotEffects.BARE_REACH`), where the fist is, so the body does not hide it.
- **A weapon's size** is `WeaponDef.flash_size`, metres across: pistol 0.20, SMG 0.22, flare gun 0.24, rifle 0.30,
  shotgun 0.42, crowbar 0 (no flash).
- **The light** (`light_enabled`, energy 1.3, range 2.6 m, no shadow) lasts the same frames. At most one flash on the
  whole map holds it at a time (group `muzzle_flash_lit`), so a flash adds **one** light to a mesh's cap of 8 in the
  Compatibility renderer, whatever the number of players. It is off with `light_enabled = false`.

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

Per shot: three quads and at most one light for two frames, and up to 24 slots of three quads, hidden unless alive. No
textures, no per-frame allocation after a slot is made, no `Environment` features. The browser measure is in
[Shot feedback research](../research/shot-feedback.md#the-web-check).
