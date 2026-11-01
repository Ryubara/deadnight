# Weapons

How Deadnight's first original weapons were built in the Toon Shooter kit's style (issue #16), and what we learned.
The rules come from the [style bible](../design/style.md#weapons); this page records how to meet them by script.

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

All are within the budgets (world 1.5k, far 500) and in the kit's range (guns 1.0-1.45k, melee 660-760; the axe is
lighter, flat parts need few triangles).

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
