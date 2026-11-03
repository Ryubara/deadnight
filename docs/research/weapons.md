# Weapons

How Deadnight's first original weapons were built in the Toon Shooter kit's style (issue #16), and what we learned.
The rules come from the [style bible](../design/style.md#weapons); this page records how to meet them by script.
The ten measured from their files, and the plan for the nine that follow (#786), are
[Weapon models](weapon-models.md).

## Third-person view

Deadnight is third-person, over the shoulder. There is no first-person weapon view and no 3k first-person budget:
each weapon has **one held and world model** at the world budget (1.5k tris) and a far level (500), seen in the
character's hands from behind the shoulder.

## The weapons

Built by `tools/blender/build_weapons.py` (helpers in `tools/blender/weaponlib.py`) into
`game/assets/weapons/<name>/<name>.glb` and `<name>_far.glb`:

| Weapon | Tris (held and world) | Tris (far) | Loose parts | Length | Colours |
| --- | --- | --- | --- | --- | --- |
| Lever rifle | 1,060 | 352 | 49 | 1.65 m | Grey, DarkGrey, Black, Wood |
| Double shotgun | 1,092 | 348 | 35 | 1.51 m | Grey, DarkGrey, Black, Wood |
| Baseball bat | 920 | 218 | 18 | 1.11 m | Wood, Black, Grey |
| Fire axe | 432 | 108 | 14 | 1.24 m | Red, Grey, Wood, Black |
| Grenade | 1,172 | 374 | 25 | 0.61 m tall | Green, Yellow, DarkGrey, Grey2, Grey |
| Claw hammer (a tool, not a weapon) | 508 | 168 | 15 | 0.73 m | Grey, Wood, DarkGrey |
| Crowbar | 484 | 144 | 8 | 0.75 m | Red, Black, Grey |
| Revolver | 760 | 280 | 30 | 0.31 m | Grey, DarkGrey, Black, Wood |
| Tommy gun | 1,108 | 360 | 37 | 0.88 m | Grey, DarkGrey, Black, Wood |
| Flare gun | 524 | 260 | 19 | 0.26 m | Red, Grey, Black |

All are within the budgets (world 1.5k, far 500) and in the kit's range (guns 1.0-1.45k, melee 660-760; the axe is
lighter, flat parts need few triangles).

## The held weapons of #285

The crowbar, the revolver (the `pistol` id), the tommy gun (the `smg` id) and the flare gun, built by `crowbar()`,
`revolver()`, `tommy_gun()` and `flare_gun()` in `build_weapons.py` into `game/assets/weapons/<name>/`. Same setup as
the older weapons, measured on the files: one `Weapons` material, the shared 32 x 32 palette (Closest filtering),
roughness 0.415, metallic 0.4, every face's UVs on one swatch centre (so no texel density to match: the colours are
flat), 11-76 KB a file.

- **Drawn at their real length.** Unlike the older weapons (drawn 1.3-1.5 times real), each is its real length with
  its chunky cross-sections already in the drawing (about 1.5-2 times real across; `chunk` 1, so round parts stay
  round). The size rule then gives one `model_scale` for all four: the rule is 0.88 x real, the Soldier's own scale
  is 0.8, so **`model_scale` = 1.1** (the bat's 0.86 is the same sum on a model drawn 1.29 times real).

| Model | Real length (= model) | Rule in the game | Muzzle (glTF, Y up) | Grip origin from the muzzle |
| --- | --- | --- | --- | --- |
| Crowbar | 0.75 m (head 0.61, butt -0.14 along +Y) | 0.66 m | none (melee); the hook strikes on -X | 19 % up from the butt |
| Revolver | 0.31 m | 0.27 m | (-0.235, 0.045, 0) | 76 % |
| Tommy gun | 0.88 m | 0.78 m | (-0.55, 0.05, 0) | 63 % (the pistol grip; the foregrip's middle is (-0.365, -0.04, 0)) |
| Flare gun | 0.26 m | 0.23 m | (-0.19, 0.045, 0) | 74 % |

- **Bends by sweep.** A gooseneck of overlapping boxes (`bar`, `arc`) showed a saw-tooth at the bend once it was
  0.05 m thick; `Builder.tube` sweeps one hex ring along the shaft and the bend (mitred), one closed part.
- **Far levels** are 30-50 % of the held count (the pistols have few chamfers to drop), all under 500.
- **Small guns in the fist.** Held on the kit's grip at the rule's size, the revolver (0.27 m) and the flare gun (0.23
  m) show only their barrels past the Soldier's 0.15 m fist; at 1.6 times the rule they read as guns. The same case
  as the hammer's exception ([the size rule](../design/weapon-hold.md#the-size-rule)); the hold decides.
- **The kit Revolver's hold does not carry over:** its copy in the Soldier file is rescaled (scale 0.001 against the
  Shotgun's 0.010), like the AK's, so the hold renders use the Shotgun's for every gun.

## The grenade

An original 1950s-flavoured hand grenade (#102): an olive egg ringed by three raised bands (period, without copying
any one real grenade's pattern), a yellow band under the fuze (the period marking for an explosive filler; the kit
`Yellow` is a new swatch in the shared palette), a squat grey fuze, a long spoon down the right side and a pull ring.
Drawn at 0.5 m and fattened 1.2x to the kit grenade's 0.6 m (kit grenades: 0.56-0.57 m, 820-916 tris, no bevels).

- **Nodes:** `grenade` (the body, origin at its centre: the grip) with two children, `Spoon` (origin at its hinge on
  the fuze, so it can swing off) and `Pin` (origin in the fuze, pulls out along glTF +Z, the ring's side). They come
  from `NODES` in `build_weapons.py`: each node is joined on its own and parented to the weapon's main node.
- **Held:** a grenade stands in the hand the gun hold's way only after a 90-degree turn about its X; the transform is
  `HOLD_GRENADE` in [Animation](../design/animation.md#grenade).
- **Proof:** a turntable with the kit grenades (`render_turntable.py --upright` keeps it standing) and the Godot
  capture of the clips with the grenade in hand, attached to the pull request.

## The hammer

The claw hammer the player nails boards back with while repairing a breach (#297's hold to repair). It is a tool,
not in the catalogue: nobody buys or swings it, and it shows only while the repair clip holds the arms
([Animation](../design/animation.md#repair)). Built by `hammer()` in `build_weapons.py`, like the others.

- **Shape:** a wood handle, wider in the swing plane than across it, swelling at the grip and flaring at the butt
  (one prism, 12 mm chamfer, as the axe's haft); a Grey steel head: a chamfered eye block, a tapering neck, a round
  face (12 sides) with a DarkGrey worn disc, and a split claw curling back toward the handle (two prongs of four
  tapering prisms each, a V between them); a wood wedge and a steel one in the top of the eye.
- **Size:** drawn at 0.56 m and enlarged 1.3 times (1.5 across) to 0.73 m, 2.2 times a real 16 oz hammer (0.33 m):
  the kit draws its small things large (its knife is 1.35-1.41 m, longer than its 1.11 m shovel). Beside the bat
  (1.11 m) and the axe (1.24 m) it reads as the smaller tool. In the hand its hold file scales it to 0.50 m, above
  the size rule's 0.29 m, which the Soldier's fist hides ([the exception](../design/weapon-hold.md#the-size-rule)).
- **Axes and grip:** the melee frame: standing up along +Z (glTF +Y), the face along -X (the axe's blade side), the
  claw along +X, thin across Y. The origin is the grip, 15 % up from the butt (0.11 m). The model carries a `Face`
  empty at the centre of the striking face, (-0.2145, 0.5395, 0) in the glTF, its -Z out of the face, added by
  `FACES` in `build_weapons.py` beside `MUZZLES` ([attachment points](../design/style.md#attachment-points)): the
  test reads the blow from it, and a nail spark or a knock can start there. Head top (0, 0.62, 0), butt (0, -0.11, 0).
- **Far level:** 168 tris (33 %): no chamfers, the face 6-sided, the worn disc, the claw tips and the wedges left out.
- **Held:** `game/gameplay/player/holds/hammer.tres` (size and ends) on `PlayerAnimation.HOLD_HAMMER`, the melee
  grip tipped 20 degrees about the hammer's Z, chosen by tracing the face through the repair loop for turns about the
  handle (-30 to 30 degrees) and tips (-60 to 60): the turn the bat uses already points the face at the board, and
  the tip brings it square to the downward blow.
- **Proof:** the turntable beside the bat, the axe and the kit Shovel and Knife, and a Movie Maker capture of the
  `repair_hold` scene from the player's camera, attached to the pull request.

## Holding them: grip origin and axes

The kit Soldier carries every kit weapon as a mesh parented to the `Index1.R` bone, origin on the bone. The copy in
the hand uses the standalone file's own mesh data, so a weapon whose origin and axes follow the kit file drops into
the same hold:

| Kind | Axes (Blender; the glTF is the same with Y up) | Origin |
| --- | --- | --- |
| Guns | muzzle along -X, up +Z, thin across Y | the grip (the wrist of the stock, behind the trigger) |
| Melee | standing up along +Z, blade or head at the top | the grip, near the handle end (13-15 % of the length) |

`tools/blender/render_hold.py` proves it: it reads the hold of a kit weapon in `Index1.R` space and attaches ours with
the same transform. Use the kit **Shotgun** hold for long guns and the **Shovel** hold for melee: both are unit-scale
(offset about 2 mm from the bone). The Shovel's copy matches its file exactly; the Shotgun's sits within the same hold
by eye. The AK and Sniper copies in the Soldier file carry rescaled mesh data (object scale 0.21-0.42), so their
transform does not carry over to a weapon at true size. In Godot: a `BoneAttachment3D` on `Index1.R` with the
Shotgun's (or Shovel's) local transform, then any of our weapon scenes as its child.

## The muzzle

Every firearm has a `Muzzle` empty under its root ([the rule](../design/style.md#attachment-points)), added by
`MUZZLES` in `build_weapons.py` (drawing units, scaled by the weapon's `chunk` like the `NODES` pivots), so the flash
and the shot leave the barrel instead of a fixed offset from the body. In the glTF and in Godot (Y up, origin the grip):

| Weapon | `Muzzle` position (m) | -Z (forward) | Front face of the bounds | Note |
| --- | --- | --- | --- | --- |
| Lever rifle | (-1.220, 0.0675, 0) | (-1, 0, 0) | -1.224 held, -1.220 far | the barrel's end face; the black bore disc stands 4 mm proud on the held level |
| Double shotgun | (-1.080, 0.0525, 0) | (-1, 0, 0) | -1.084 held, -1.080 far | centred between the two barrels (0.05 m either side) |
| Revolver | (-0.235, 0.045, 0) | (-1, 0, 0) | -0.238 held, -0.235 far | the barrel's end face; the bore disc 3 mm proud |
| Tommy gun | (-0.550, 0.050, 0) | (-1, 0, 0) | -0.554 held, -0.550 far | the compensator's front face |
| Flare gun | (-0.190, 0.045, 0) | (-1, 0, 0) | -0.193 both | the muzzle ring's front face; the wide bore disc 3 mm proud |

- **Turned so -Z is forward:** in Blender the empty is turned 90 degrees about Z (`rotation_euler = (0, 0, pi/2)`), so
  its local +Y points along -X, out of the barrel. The glTF export turns Blender +Y into -Z, so the node arrives in
  Godot turned 90 degrees about Y (quaternion `(0, 0.7071, 0, 0.7071)`), with -Z along the barrel's -X.
- **Both levels agree:** the far level uses the same point (it has no bore disc, so its front face is the barrel's).
- **The test:** `game/tests/art/test_weapon_muzzle.gd` loads both levels of every firearm and checks the `Muzzle`
  exists once, sits within 1 cm of the bounds' front face along the barrel with mesh within 6 cm across it, points
  within 1 degree of the barrel and has unit scale; melee weapons and the grenade must have none, and every weapon
  folder must be listed as a firearm or not.
- **The capture:** `tools/blender/render_muzzle.py` draws a red ball and arrow at each `Muzzle` (side view and
  barrel close-up).
- **Rebuilding is safe but not byte-identical:** two runs of `build_weapons.py` give the same vertices and the same
  triangles in a different order (the fire axe differs between two runs of one script). Compare a rebuilt file with
  the old one by its nodes, vertex buffers and triangle set, not its bytes. Rebuilding the four older weapons also
  brings the shared palette's `Yellow` swatch (added with the grenade) into their embedded copy.

## How to build in the kit style

| Lesson | Detail |
| --- | --- |
| Draw real, then fatten | Drawn at real proportions, a gun looks spindly beside the kit. Scaling every part 1.4-1.5x across its length (Y and Z for guns; X and Y for the bat) before chamfering gives the kit's chunky cross-sections without retuning every number (`Builder(chunk=...)`) |
| Big receiver | The kit's guns read as a large grey block with a barrel and a stock attached; make the receiver at least 0.26 m long at kit scale |
| Shallow, slanted stock | After the fattening, a stock deeper than about 0.18 m turns into a wedge; slant the butt back at the bottom |
| Chamfer only the big parts | A one-segment 17 mm chamfer costs a box 44 tris instead of 12. Chamfer receivers, stocks and barrel ends; leave screws, pins, sights and lever segments hard, as the kit does |
| Bent parts from straight boxes | Levers, guards and loops are overlapping boxes along a path (`bar`, `arc`): they stay separate parts, as the kit kitbashes |
| Round parts by lathe | The bat is one turned profile (14 sides) with its chamfers in the profile; flat shading keeps the facets that match the kit |
| Far level from the same script | `lod="far"`: no chamfers, half the sides on round parts, `detail=True` parts left out. 22-32 % of the held count |
| One material | All four share one `Weapons` material, a 32 x 32 palette atlas (`weapons_palette.png`, the kit's weapon colours) with every face's UVs collapsed on its swatch, roughness 0.415, metallic 0.4 |

## Proof

Turntable contact sheets (each weapon, its far level and two kit weapons at the same scale; `render_turntable.py`)
and the hold sheets (`render_hold.py`) are attached to the pull request; renders are not committed. The Godot 4.7.2
headless import of the eight files prints no `ERROR`.

## Open

- Godot extracts the embedded palette once per file (eight copies of one 32 x 32 image). Point every weapon at one
  shared material and texture when the weapon scenes are made, so the family batches as the style bible decided.
- The parts are fewer than the kit's 62-386 per gun (35-49): the kit's counts include many small pieces; ours meet the
  look and the budget with fewer.
- The guns' barrels are still a little longer and thinner than the kit's; the axe's haft is thinner than the shovel's.
