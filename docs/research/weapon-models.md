# Weapon models: the measured style and the plan for nine more

How the ten models in `game/assets/weapons/` are made, measured from their files (#786), and the plan the three
model batches follow: #795 (PPSh, MP5, M4A1), #796 (M249, .50 calibre rifle, 870-style pump), #797 (the pistol the
dual pistols carry, the ray gun, the freeze gun). The batches build in parallel, so every number they must agree on is
here: size, palette, budget, hold points, moving parts. The design numbers (damage, prices, the re-cut's effects)
are #785's; the build history of the first ten is [Weapons](weapons.md); the rules they follow are the
[style bible](../design/style.md#weapons) and [Weapons in the hands](../design/weapon-hold.md).

**Measure again:**
`blender -b --factory-startup -P tools/blender/measure_weapons.py -- --out <json>` (every glb: triangles, parts,
bounds, origin, palette cells by area, sockets, moving nodes, size in the game from the hold files).
**The captures** (attached to #786's pull request, not committed):
`blender -b --factory-startup -P tools/blender/render_weapon_plan.py -- --out <png>` draws the set side by side at its
size in the game with its hand points; `--plan <json>` adds the nine as boxes of their planned size;
`--silhouette --px-per-m 42` (or 130) draws what a phone shows.

## The ten, measured

Every model is drawn by `tools/blender/build_weapons.py` (parts in `weaponlib.py`), never by hand. Sizes are the model
in Blender's axes (length along X, height Z, width Y; the melee weapons stand up along Z); "in the game" is model x
the hold's `model_scale` x the Soldier's 0.8.

| Model | Tris near / far (far %) | Parts | Model L x H x W (m) | `model_scale` | In the game | Origin (% from muzzle, % up) | Grip to muzzle | Cells by area | Moving nodes | Ammo glb |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Revolver | 760 / 280 (37) | 30 | 0.31 x 0.21 x 0.07 | 2.275 | 0.57 m | 77, 51 | 0.29 | Grey 63, DarkGrey 13, Black 13, Wood 11 | `Cylinder` 164 tris | speedloader 304 |
| Flare gun | 524 / 260 (50) | 19 | 0.26 x 0.21 x 0.07 | 2.21 | 0.46 m | 75, 52 | 0.24 | Red 74, Grey 13, Black 13 | `Barrel` 240 | cartridge 152 |
| Tommy gun | 1,108 / 360 (32) | 37 | 0.88 x 0.31 x 0.09 | 1.3 | 0.92 m | 63, 58 | 0.60 | DarkGrey 40, Grey 29, Wood 24, Black 7 | `Drum` 172 | the drum 172 |
| Lever rifle | 1,060 / 352 (33) | 49 | 1.65 x 0.50 x 0.15 | 0.84 | 1.11 m | 74, 59 | 1.29 | DarkGrey 36, Grey 31, Wood 30, Black 4 | `Lever` 168 | round 148 |
| Double shotgun | 1,092 / 348 (32) | 35 | 1.51 x 0.39 x 0.22 | 0.96 | 1.16 m | 72, 56 | 1.15 | DarkGrey 43, Wood 24, Grey 22, Black 11 | `Barrels` 420 | two shells 304 |
| Baseball bat | 920 / 218 (24) | 18 | 1.11 tall, 0.29 across | 1.01 | 0.89 m | 15 up | - | Wood 69, Black 25, Grey 6 | - | - |
| Crowbar | 484 / 144 (30) | 8 | 0.75 tall, 0.18 across | 1.3 | 0.78 m | 19 up | - | Red 61, Black 21, Grey 19 | - | - |
| Fire axe | 432 / 108 (25) | 14 | 1.24 tall, 0.52 across | 0.95 | 0.94 m | 14 up | - | Wood 47, Red 27, Black 17, Grey 9 | - | - |
| Claw hammer (tool) | 508 / 168 (33) | 15 | 0.73 tall, 0.47 across | 0.85 | 0.50 m | 15 up | - | Grey 60, Wood 37, DarkGrey 4 | - | - |
| Grenade | 1,172 / 374 (32) | 25 | 0.61 tall, 0.42 across | 0.51 | 0.25 m | 44 up | - | Green 47, Yellow 17, DarkGrey 14, Grey 13, Grey2 10 | `Spoon` 60, `Pin` 140 | - |

What that says, as rules a new model keeps:

| Rule | Measured |
| --- | --- |
| Axes | muzzle along -X, up +Z, thin across Y, the gun's right side +Y; the origin is the grip. A melee weapon stands up along +Z with its striking side on -X |
| Drawn length | the first four (lever rifle, double, bat, axe) were drawn 1.3-1.5x real and fattened by `chunk`; the five of #285 (revolver, Tommy gun, flare gun, crowbar, hammer) are drawn at their **real length** with chunky cross-sections in the drawing (1.5-2x real across) and `chunk` (1, 1, 1). New models do the second: then `model_scale` is simply 1.3 x the size factor ([the size rule](../design/weapon-hold.md#the-size-rule)) |
| Triangles | guns 524-1,108 near, 260-360 far; melee 432-920 near, 108-218 far. Budget 1.5k near, 500 far ([style](../design/style.md#budgets-proposed-for-the-web)) |
| Far level | 24-50 % of the near count from the same script: no chamfers, half the sides on round parts, `detail=True` parts dropped. The far glb is built and tested (the `Muzzle` test) but the game draws the near model only today, and Godot's import makes its own LODs (`meshes/generate_lods=true`) |
| Parts | 8-49 separate closed pieces joined into one mesh per node, never welded (the kit's 62-386 count its many tiny pieces) |
| Materials | one, `Weapons`, on every face of every model: roughness 0.415, metallic 0.4 |
| UVs | 100 % of faces collapsed onto the centre of one palette swatch (so no texel density: the colour is flat) |
| Smoothing | 100 % flat (the grenade 98 %); the soft look is chamfers, not smoothing |
| Chamfers | one segment, angle limit 40 degrees: 17 mm on receivers, stocks and barrel ends; 4-12 mm on small parts (frames, rims, bands); none on screws, pins, sights, lever and guard bars |
| Modelled, not painted | every detail is geometry in a palette colour: screws are 6-18 mm Black boxes, slots and bores are Black discs or boxes 3-4 mm proud, flutes are boxes. Nothing is painted into a texture. Detail parts are `detail=True` so the far level drops them (they are most of the Black: the lever rifle's Black falls from 4 % to 1 % of the area in its far level) |
| Round parts | cylinders of 8-16 sides (12 for barrels, 16 for the Tommy drum), lathes of 14 |
| Colour | a neutral mass (Grey, DarkGrey, Black: 47-80 % of a gun) with Wood furniture or one painted accent (the flare gun's Red, the crowbar's, the axe head) |
| Moving parts | the reload's part is its own node at its pivot under the weapon's node (`NODES`); the ammunition the left hand brings is `<model>_ammo.glb` beside the gun, at the gun's scale (`AMMO`) |

Captures: `set_side.png` (the ten at their size in the game, `Grip` green, `Trigger` yellow, `Support` blue, `Muzzle`
red, the Soldier's 1.4 m as the ruler), `set_far.png` (the far levels).

## The palette

`game/assets/weapons/weapons_palette.png`: 32 x 32, a 4 x 4 grid of 8 px swatches in the order of
`weaponlib.PALETTE`, lossless, no mipmaps, Detect 3D off, sampled Closest. Each glb embeds a copy that Godot extracts
beside it (`<model>_weapons_palette.png`).

**In Godot a face's cell is `floor(UV.x * 4) + 4 * floor(UV.y * 4)`** (checked by reading every UV of four models in
Godot and sampling the palette there: cell 0 Grey at UV (0.125, 0.125), cell 8 Yellow at (0.125, 0.625)). The glTF
flips V, so in Blender the same cell is `floor(u * 4) + 4 * floor((1 - v) * 4)`.

| Cell | Name | Hex | Used by |
| --- | --- | --- | --- |
| 0 | Grey | `#818491` | every gun's receiver or frame, steel parts |
| 1 | DarkGrey | `#414141` | barrels, the Tommy drum, the grenade fuze |
| 2 | Black | `#252525` | screws, bores, triggers, grips, butt pads |
| 3 | Wood | `#95703d` | stocks, forends, grips, the bat, the hafts |
| 4 | Grey2 | `#5f5f5f` | the grenade's fuze parts |
| 5 | Red | `#8c3735` | the flare gun, the crowbar, the axe head, shells |
| 6 | DarkWood | `#6b4f2c` | nothing yet |
| 7 | Green | `#496321` | the grenade body |
| 8 | Yellow | `#d1ab46` | brass: cartridges, the grenade's band |
| 9 | **Blue** | `#34609e` | new: the ray gun's painted body |
| 10 | **Glow** | `#7fe3ff` | new: what burns (the ray gun's cell, lens and vents; the freeze gun's gauge, strip and nozzle) |
| 11 | **Frost** | `#c6dce4` | new: the freeze gun's tank and fins |
| 12 | **Tan** | `#9c8562` | new: polymer furniture (the M4A1) |
| 13-15 | free | | |

The four new cells are appended (#786), so no older swatch moved and no model changed; the batches only use them.
`palette_cells_before.png` and `palette_cells_after.png` show the grid with each cell's UV.

**The Glow cell does not glow by itself:** the palette is a base colour. The game lights it the way the drive-in lights
its amber bulbs (`ModelGlow`, `game/world/drive_in/model_glow.gd`): an emission texture of the atlas's layout, black
but for cell 10, on a copy of the weapon's material. That is gameplay work (#788 for the two wonder weapons); until
then the cell reads as a flat bright cyan, which already reads as "lit" at night.

## Hand and effect points

Every point is an empty under the weapon's node, placed in Blender by the modeller, never an offset in game code
([attachment points](../design/style.md#attachment-points)); all are in drawing units like the parts.

| Empty | Who has it | Where | Turn | Read by |
| --- | --- | --- | --- | --- |
| `Grip` | every held model | the right hand's handle, where the middle finger wraps; the origin sits there or within about 9 cm | +Z up the handle toward the index finger, +Y the way the fingers point | the grip solver |
| `Trigger` | guns | the middle of the trigger's front face | +Y the press (+X) | the grip solver |
| `Support` | two-handed guns | the left hand's handle: the fore-end's rear (0.36-0.37 m ahead of the grip on the three long guns), or a vertical foregrip | on a fore-end +Z toward the muzzle, +Y to the gun's right and up | the grip solver, the hold |
| `Muzzle` | firearms | the centre of the barrel's open end, at the front face of the bounds (within 1 cm; nothing may stick out further forward, a folded bipod included) | its -Z out of the barrel in Godot (+Y in Blender, turned 90 degrees about Z) | the flash, the shot, `test_weapon_muzzle.gd` |
| `Eject` | **new (#786)**, guns with a port | the centre of the ejection port | the weapon's own axes: +Y in Blender, so -Z in Godot, points out of the gun's right side | nothing yet (a case effect later) |
| `Face` | the hammer | the striking face's centre | -Z out of the face | the repair |

`Eject` is built by `EJECTS` in `build_weapons.py` (or a module's `eject`, below); a gun with no port (a revolver, the
ray gun, the freeze gun) has none. The grip fit, measured by `WeaponFit` against the Soldier's hand (fist 0.20 m, the
three fingers under the index 0.167 m, index 5.7 cm thick), is the [hold page's table](../design/weapon-hold.md#the-size-rule):
pistol grips need about 1.2 of the three fingers below the trigger's level and a guard opening of about 1 index
finger, which is why the revolver and flare gun are held at 1.7-1.75 times the rule. Long guns held at the wrist
like a stick (the lever rifle, the double) need no grip ratio.

## What reads: silhouettes on a phone

From the shoulder camera in the aim pose every gun is a fist and a barrel tip ([the hold page](../design/weapon-hold.md#which-weapon-is-which)):
a weapon is recognised in the side views, at the hip, running, reloading, and in other players' hands. The camera's
vertical field of view is 60 degrees; a landscape phone is about 390 logical pixels tall. So a weapon is drawn at
about 390 / (2 x d x tan 30) pixels a metre: **130 px/m** for the player's own weapon (2.6 m from the camera) and
**42 px/m** for a teammate 8 m away. `sil_130.png` and `sil_42.png` draw the ten flat black at those sizes
(`sil_42_x8.png` enlarged 8 times to look at):

- At 42 px/m one pixel is 2.4 cm in the game. **The thin bars vanish**: trigger guards (1.2-1.8 cm in the game), the
  lever rifle's loop, sights and screws are gone or one grey pixel. What reads is mass: the Tommy gun's drum (19 cm)
  and its two grips, the pistols' L, the double's thick barrel block, the axe head.
- **The lever rifle and the double shotgun are one shape at 42 px/m**: a bar and a stock, told apart only by the
  rifle's two-line barrel and its loop (1-2 px). Four more long guns are coming; each needs its own outline.
- **The revolver and the flare gun differ by colour**, not outline (the cylinder's step is a few pixels). Colour mass carries
  identity where the outline cannot.

The rules for the nine:

1. **One signature mass per weapon, at least 7 cm in the game across its short side** (3 px at 42 px/m): in drawing
   units 0.067 m on a long gun (`model_scale` 1.3), 0.04 m on a pistol (2.275). It must change the outline seen from
   the side: a drum, a curved magazine, a carry handle, a scope, a brake, a tank. Not a thin bar.
2. **No two weapons of one class share their outline**: the new long guns differ from the lever rifle and the double
   and from each other in a signature mass, not in detail.
3. **A colour mass of its own where the outline is close** (Tan on the M4A1 against the black MP5; Blue on the ray gun
   against the revolver).
4. Detail parts (`detail=True`) are for the close view only: nothing of a weapon's identity may be a detail part,
   because the far level drops them.

## Into Godot

1. Draw the weapon in its own module, `tools/blender/weapon_specs/<id>.py` (below), and build it:
   `blender -b --factory-startup -P tools/blender/build_weapons.py -- --only <id>`. It writes `<id>.glb`,
   `<id>_far.glb` and `<id>_ammo.glb` into `game/assets/weapons/<id>/` and prints the triangles, parts, size and every
   socket.
2. Import headless (`godot --headless --path game --import`), with no `ERROR`. The glb's `.import` keeps the defaults
   the others have (`generate_lods=true`, embedded images extracted); the extracted palette's `.import` is fixed to
   lossless with no mipmaps by `tools/check_texture_imports.py` (the pre-commit hook). glTF buffers are LFS files.
3. Say whether it shoots: add the folder to `FIREARMS` or `NOT_FIREARMS` in `game/tests/art/test_weapon_muzzle.gd` (the
   test fails on a folder in neither) and run it.
4. The hold file `game/gameplay/player/holds/<weapon id>.tres` (`WeaponHold`: class, `scene`, `model_scale` = 1.3 x
   the size factor, `real_length`, `model_length`, `grip_offset`, `support`, `muzzle`, `butt`, `stance_turn_deg`),
   the grip solved from the sockets (`solve_grips.gd`, add the model to `MODELS`; `measure_weapon_fit.gd` and
   `test_hand_grips.gd` list the models too), then `test_weapon_hold.gd` and `test_hand_grips.gd`. A model batch may
   stop at the model and its captures (the issues say so); the build issues (#788, #789 and the roster's) wire the
   definition, the reload file (`gameplay/player/reload/<id>.tres`) and `test_every_weapon.gd`.
5. **Conflicts:** the three batches each add lines to the same few lists (the two firearm lists, `MODELS`, the grip
   tests). Add your ids on lines of your own, merge main before each push (`gds merge-main`) and keep both sides.

## One module a weapon

`build_weapons.py` loads every `tools/blender/weapon_specs/<id>.py` whose name does not start with `_` (#786), so the
batches never edit the same lines of the build script. A module defines its builders and one `SPEC` dict with the
same values the script's tables hold for the first ten: `build`, `chunk`, `nodes`, `muzzle`, `eject`, `grip`,
`trigger`, `support`, `ammo` (unknown keys, an id that is already a weapon, or ammunition without a builder stop the
build). `weapon_specs/_template.py` is a working example (a box gun, never built); copy it. Checked by building the
template under another name: its three files came out with the `Magazine` node, `Muzzle` and `Eject` where the spec
put them, and the revolver and the Tommy gun rebuilt with their old counts (760 / 280 and 1,108 / 360).

## What to reuse

The builders are functions: call them or copy their profiles, scaled, rather than drawing again.

| From | Part | Into |
| --- | --- | --- |
| `tommy_gun` | the pistol grip prism, the deepened guard (fits the Soldier's finger, #460), the trigger bar, `GRIPS`/`TRIGGERS` numbers | MP5, M4A1, M249, .50, 870, freeze gun: start from the Tommy's grip and socket numbers |
| `revolver` | the raked wood grip prism and its backstrap, the round guard, `GRIPS` (up `(-0.38, 0, 0.92)`) | the service pistol's grip (with a straighter rake), the ray gun's grip |
| `flare_gun` | the grip with proud plates, the hammer bar | the ray gun |
| `tommy_gun_drum` | a drum as its own node and as the ammo (`ammo_is_part` in the reload) | the PPSh's drum (smaller across, Grey2, its own builder) |
| `lever_rifle` | the stock prism with the slanted butt and the plate, the straight-wrist `GRIPS` | the PPSh's stock (held at the wrist, no pistol grip) |
| `shotgun_shells`, `rifle_round` | a red shell with a brass head; a brass round | the 870's one shell; the M249's belt rounds; the .50's round, larger |
| `revolver_speedloader` | ammo drawn chunky so it reads in the fist | every magazine's ammo glb |

## The re-cut look (#787)

Issue #787 is building the re-cut skin in parallel; as it stands on its branch the shader replaces the weapon's
material on every mesh of the held weapon (the moving nodes too) and draws a lattice of cells in the model's own units
(a cell 0.03 m), a pulse that runs along X from the butt (+X) to the muzzle, a fresnel rim and a breath, keeping each
swatch's brightness. What that asks of the models, all already true of the first ten and required of the nine:

- The muzzle along -X and the butt at +X, so the pulse runs to the muzzle.
- **Big flat faces on the metal:** the lattice shows on faces at least three cells across (0.09 m in drawing units):
  receivers, jackets, magazines, drums, the tank. A receiver made of many small boxes loses it.
- A pistol is held 2.275 times its drawing (a long gun 1.3 times): its lattice cells come out 1.75 times larger in the
  game unless the shader scales `cell_size` by the hold's `model_scale`. Worth a line in #787.
- The Glow cell (10) should stay lit under the skin: it is where the wonder weapons' energy is.

Each plan below names the parts the skin should light (the faces that carry the pattern) and the ones it should leave
dark, for #787 to check its captures against.

## The nine

Sizes: in the game = real length x 0.8 x 1.3 x the size factor; drawn at real length, so `model_scale` = 1.3 x the
size factor. Coordinates are drawing units (metres at real length), the origin at the grip, muzzle along -X. The
numbers are a starting layout from the reference photos; a batch may move a part a few centimetres to fit the hand,
but keeps the length, the signature mass, the cells and the budget. `set_plan.png` shows each planned size as a box
beside the ten. Reference photos are in the workspace's `refs/weapons/<id>/` with a `meta.json` (licence, author,
source) each; they are never committed. The real weapons are modelled as generic types: no maker's marks, logos or
names on any part.

| Id | Batch | Hold class | Real, drawn (m) | Size factor | `model_scale` | In the game | Tris near / far (target, cap 1,500 / 500) | Signature mass | Main cells |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ppsh` | #795 | Rifle | 0.84 | 1 | 1.3 | 0.88 m | 1,150 / 380 | the drum ahead of the guard, no pistol grip | Wood, DarkGrey, Grey2 |
| `mp5` | #795 | Rifle | 0.68 | 1 | 1.3 | 0.71 m | 1,050 / 360 | the curved magazine and the ring sight hood | Black, DarkGrey, Grey |
| `m4a1` | #795 | Rifle | 0.80 | 1 | 1.3 | 0.83 m | 1,200 / 400 | the carry handle and the triangle front sight | Tan, Black, DarkGrey |
| `m249` | #796 | Rifle | 1.04 | 1 | 1.3 | 1.08 m | 1,450 / 480 | the ammo box under the left side, the carry handle | Black, DarkGrey, Green |
| `fifty_cal` | #796 | Rifle | 1.45 | 0.93 | 1.21 | 1.40 m (the Soldier's height) | 1,400 / 460 | the scope and the muzzle brake block | DarkGrey, Black, Grey |
| `pump_870` | #796 | Shotgun | 0.98 | 1 | 1.3 | 1.02 m | 1,000 / 340 | the ribbed pump under one barrel, a pistol-grip stock | Black, Grey, DarkGrey |
| `service_pistol` | #797 | Pistol (two, #789) | 0.21 | 1.75 | 2.275 | 0.38 m | 700 / 250 (two in hand: 1,400 / 500) | the slide's long block over a straight grip | Black, DarkGrey, Wood |
| `ray_gun` | #797 | Pistol | 0.30 (ours) | 1.75 | 2.275 | 0.55 m | 900 / 320 | the wide lens barrel, all Blue | Blue, Grey, Black, Glow |
| `freeze_gun` | #797 | Rifle | 0.90 (ours) | 1 | 1.3 | 0.94 m | 1,300 / 440 | the tank on top, square fins on the barrel | Frost, Grey, DarkGrey, Glow |

Three more rules for all nine:

- **Neutral mass first:** Grey, DarkGrey and Black (with Tan on the M4A1) cover at least 55 % of a firearm's area,
  except the two wonder weapons, which are painted (Blue, Frost) as the flare gun is Red.
- **The size factor is the grip's call:** measure the grip with `measure_weapon_fit.gd` after the first build; a pistol
  grip short of about 1.0 of the fingers gets a larger factor (as the revolver's 1.75), a long gun's stays 1 unless its
  support cannot be reached. The .50's 0.93 makes it as long as the Soldier is tall, the kit's own sniper rule
  ([style](../design/style.md#weapons)).
- **The reload moves one part today:** `ReloadMotion` has one `part_node` (and `ammo_is_part`). Each plan names the
  reload's part first; the other moving nodes are built now so a later reload can use them, and cost little.

### PPSh (`ppsh`, #795)

A WWII drum-fed submachine gun (references: four side views, `refs/weapons/ppsh/`). Its read against the Tommy gun,
the other drum gun: **a full wood rifle stock with no pistol grip and no foregrip**, the drum set forward against the
guard, and a perforated barrel jacket with a slanted front.

- **Layout:** muzzle -0.50 (the jacket's slanted front, bore z 0.04); jacket -0.50 to -0.24, radius 0.032, DarkGrey,
  with 4 x 2 Black slots each side (detail); receiver -0.24 to +0.02, 0.07 wide, 0.09 high, DarkGrey, the cocking
  handle in a slot on the right; wood stock from under the receiver (-0.20) back through the wrist to the butt at
  +0.34, the lever rifle's slanted butt with a Grey plate; trigger guard and trigger at -0.05 to 0.0.
- **Drum:** centre (-0.15, 0, -0.10), radius 0.095, 0.07 across Y, Grey2 with a DarkGrey rim; its seat in the stock.
- **Sockets:** `Grip` at the wrist (0.07, 0, -0.02), up (-1, 0, 0.25), front (0, 0, -1) (the lever rifle's stick
  hold); `Trigger` (-0.03, 0, -0.06); `Support` on the jacket's rear, below (-0.33, 0, 0.0), up (-1, 0, 0), front
  (0, 1, 0.6); `Muzzle` (-0.50, 0, 0.04); `Eject` (-0.10, 0.036, 0.05).
- **Nodes:** `Drum` (the reload's part: off down and forward, `ammo_is_part`, as the Tommy's), `Bolt` (the cocking
  handle, slides +X 0.08).
- **Ammo glb:** the drum.
- **Re-cut lights:** the jacket and the receiver (the pulse runs down the jacket), the drum's face; the wood stays
  dark.

### MP5 (`mp5`, #795)

A compact 9 mm submachine gun with a fixed stock (references: two side views and one in use, `refs/weapons/mp5/`).
Read: **short and straight, a strongly curved magazine, the round hood over the front sight.**

- **Layout:** muzzle -0.40 (a short barrel stub with three lugs, bore z 0.045); the front sight hood, a ring of
  radius 0.03 on a post, at -0.36 (signature); the receiver a long tube -0.33 to +0.03, radius 0.035, Black, with the
  cocking tube above the barrel (-0.33 to -0.15, radius 0.016) and its handle on the left (-0.25, -0.04, 0.07); a slim
  Black hand guard -0.31 to -0.13 under the barrel; the drum-type rear sight at 0.0, z 0.09; a fixed Black stock
  +0.06 to +0.28, its butt slanted.
- **Magazine:** from the well at (-0.10, 0, -0.02) down 0.20 and curving forward 0.06 at its foot, Grey (so it
  reads against the Black gun), drawn as four boxes along an arc (the `bar` helper).
- **Sockets:** `Grip`, `Trigger`: the Tommy gun's, (0.036, 0, -0.085) and (-0.018, 0, -0.038); `Support` on the hand
  guard (-0.24, 0, 0.0), up (-1, 0, 0), front (0, 1, 0.6); `Muzzle` (-0.40, 0, 0.045); `Eject` (-0.07, 0.036, 0.05).
- **Nodes:** `Magazine` (the reload's part: out down along its own axis, pivot at the well), `Bolt` (the cocking
  handle, back +X 0.09 and up into its notch).
- **Ammo glb:** the magazine.
- **Re-cut lights:** the receiver tube, the hand guard, the magazine; the stock and the grip stay dark.

### M4A1 (`m4a1`, #795)

A 5.56 mm carbine (references: two PEO photos, `refs/weapons/m4a1/`). Read: **the carry handle on top, the triangle
front sight, the straight magazine and a tube stock**, and Tan furniture against the black MP5.

- **Layout:** muzzle -0.47 (a birdcage flash hider -0.47 to -0.42, bore z 0.045); the triangle front sight -0.33
  (base on the barrel, peak z 0.12, 0.07 tall: signature); a round ribbed Tan hand guard -0.32 to -0.13, radius 0.04;
  the upper receiver -0.13 to +0.07, Black, with the carry handle over it (-0.11 to +0.05, top z 0.13, its rear
  sight at the back); the lower with the magazine well; the buffer tube +0.06 to +0.24 (radius 0.018, Black) and a
  Tan stock on it +0.12 to +0.33.
- **Magazine:** Tan, from the well at (-0.07, 0, -0.03) down 0.17, a slight forward curve at the foot.
- **Sockets:** `Grip` and `Trigger` from the Tommy gun; `Support` on the hand guard (-0.25, 0, 0.0), up (-1, 0, 0),
  front (0, 1, 0.6); `Muzzle` (-0.47, 0, 0.045); `Eject` (-0.03, 0.036, 0.05) at the dust cover.
- **Nodes:** `Magazine` (the reload's part), `Bolt` (the charging handle under the carry handle's rear, back +X 0.06).
- **Ammo glb:** the magazine.
- **Re-cut lights:** the hand guard, the upper receiver and the carry handle; the Tan stock and grip dimmed.

### M249 (`m249`, #796)

A belt-fed 5.56 mm light machine gun (references: two side views, `refs/weapons/m249/`). Read: **the ammo box under
the left side, the carry handle over the barrel, a long heavy body**. The heaviest of the nine.

- **Layout:** muzzle -0.62 (a flash hider, bore z 0.05); barrel to -0.30 with the gas tube under it and the carry
  handle over it at -0.32 (top z 0.15); the bipod folded under the barrel, pivot (-0.52, 0, 0.0), legs back to
  -0.24 (never past the muzzle: the `Muzzle` test wants nothing further forward); the receiver -0.30 to +0.03, 0.08
  wide, 0.13 high, Black, with the feed cover on top; a fixed Black stock +0.06 to +0.42.
- **Box:** a Green soft pouch (or a DarkGrey box) hanging under the left of the receiver, centre (-0.14, -0.02,
  -0.12), 0.14 x 0.10 x 0.12; the belt rising from it into the feed tray on the left: five Yellow rounds on DarkGrey
  links.
- **Sockets:** `Grip`, `Trigger` from the Tommy gun; `Support` under the receiver's front (-0.34, 0, -0.03), up
  (-1, 0, 0), front (0, 1, 0.6) (the hand under the gun, as a gunner holds it from the hip); `Muzzle` (-0.62, 0,
  0.05); `Eject` (-0.10, 0.03, -0.04) (the port is low on the right).
- **Nodes:** `Cover` (the feed cover, the reload's part: turns 70 degrees up about Y on its front hinge, pivot
  (-0.27, 0, 0.11)), `Box` (off down), `Belt` (shown and hidden with the box), `Bolt` (the charging handle on the
  right, back +X 0.10).
- **Ammo glb:** the box with a belt stub.
- **Re-cut lights:** the receiver and the feed cover (a big flat top), the barrel and the carry handle; the pouch and
  the stock stay dark.
- **Built (#796):** `weapon_specs/m249.py`, **1,324 / 476 tris** (target 1,450 / 480), 59 parts, 0.94 x 0.35 x 0.14 m
  drawn, 0.98 m in the game at `model_scale` 1.3; cells Black 47 %, DarkGrey 36, Green 15, Yellow 3 (neutral 83 %).
  Moved from the plan: **the stock ends at +0.31 (with its plate), not +0.42, and the hand guard runs back to -0.25 with
  `Support` at (-0.30, 0, -0.025)** ([reach](#the-left-hands-reach)); the receiver is 0.12 high (bottom at z -0.02, the
  Tommy gun's, so the guard keeps the finger's opening); the carry handle runs forward of the cover's hinge (-0.29 to
  -0.40) so the opening cover never meets it; the folded bipod's legs stop at -0.45, clear of the left hand; the belt's
  links are close-up detail (the five rounds stay in the far level). `Eject` (-0.10, 0.0435, 0.0) on the right face. The
  ammo glb is the box and two rounds (132 tris).

### .50 calibre rifle (`fifty_cal`, #796)

A semi-automatic anti-materiel rifle (references: six photos, `refs/weapons/fifty_cal/`). Read: **the longest gun,
the scope on top, the big double-chamber brake.**

- **Layout:** muzzle -1.05, the brake -1.05 to -0.92 (a block 0.10 tall x 0.08 wide with two side ports each side,
  Black: signature); barrel -0.92 to -0.42, radius 0.028, DarkGrey; the upper receiver (the long slotted box) -0.42 to
  +0.08 at z 0.05, 0.10 high, DarkGrey with Black slots (detail); the scope -0.24 to +0.06 at z 0.17 (tube radius
  0.03, objective bell 0.045, eyepiece 0.04, two Grey rings), Black; the lower with the magazine well; the stock +0.08
  to +0.40 with a Black pad. The stock is shorter than the real one's so the butt stays at the shoulder (0.39 m behind
  the grip in the game; the Tommy's is 0.34): the hold's `grip_offset` will sit about 0.45 forward.
- **Magazine:** a box (-0.10, 0, -0.07), 0.14 long, 0.07 wide, 0.14 high, Grey, leaning forward a little.
- **Bipod:** folded forward under the barrel, pivot (-0.42, 0, -0.02), legs to -0.74 (behind the brake).
- **Sockets:** `Grip`, `Trigger` from the Tommy gun; `Support` under the receiver ahead of the magazine (-0.32, 0,
  -0.02), up (-1, 0, 0), front (0, 1, 0.6); `Muzzle` (-1.05, 0, 0.05) on the brake's front face; `Eject` (-0.05, 0.04,
  0.06).
- **Nodes:** `Magazine` (the reload's part), `Bolt` (the big charging handle on the right, back +X 0.12).
- **Ammo glb:** the magazine.
- **Re-cut lights:** the upper receiver (the longest flat face of the nine), the barrel, the brake; the scope's lens
  ends could take the Glow cell (a lit lens reads far).
- **Built (#796):** `weapon_specs/fifty_cal.py`, **1,332 / 460 tris** (target 1,400 / 460), 56 parts, 1.41 x 0.39 x 0.13
  m drawn, 1.36 m in the game at `model_scale` 1.21; cells DarkGrey 45 %, Black 45, Grey 9, Glow 1 (the objective lens;
  neutral 99 %). The brake is built as two slabs and three walls, so its two windows each side are open and show in the
  outline at 42 px/m. Moved from the plan: **the stock ends at +0.345 (with its pad), not +0.40, and `Support` is at
  (-0.28, 0, -0.01), not -0.32** ([reach](#the-left-hands-reach)), inside the upper receiver, which is 0.12 high (z
  -0.02 to 0.10); the magazine sits at -0.125 (0.12 long), ahead of the guard; the scope's rings, the flutes and the
  bolt's knob are close-up detail. The ammo glb is the magazine (56 tris).

### 870-style pump shotgun (`pump_870`, #796)

A pump-action 12 gauge (references: three photos, `refs/weapons/pump_870/`, the police one with a pistol-grip stock).
Read against the double: **one barrel over a full-length tube, the ribbed pump with gaps either side, a black
pistol-grip stock** (the double is wood with a straight stock and two fat barrels).

- **Layout:** muzzle -0.62 (bead sight, bore z 0.05); barrel -0.62 to -0.20, radius 0.026; the magazine tube under it
  -0.58 to -0.20 at z 0.0, radius 0.024, with its cap; the pump (Black, ribbed with Black rings as detail) -0.43 to
  -0.25 around the tube; the receiver -0.22 to +0.04, Grey, the ejection port on the right, the loading port
  underneath; a Black pistol grip and stock to +0.36.
- **Sockets:** `Grip`, `Trigger` from the Tommy gun; `Support` on the pump (-0.34, 0, -0.01), up (-1, 0, 0), front
  (0, 1, 0.6) (the hand rides the pump: the hold's `support` follows the `Pump` node's slide); `Muzzle` (-0.62, 0,
  0.05); `Eject` (-0.08, 0.036, 0.05).
- **Nodes:** `Pump` (slides +X 0.09 and back: the pump after each shot and at the end of the reload).
- **Ammo glb:** one red shell with a brass head (the double's `shotgun_shells`, one of them); shells go in one by one
  through the loading port at (-0.10, 0, -0.045), a new mechanism for the reload (`shells`).
- **Re-cut lights:** the receiver's sides (a big Grey slab), the barrel and the tube; the pump and the stock stay
  dark.
- **Built (#796):** `weapon_specs/pump_870.py`, **948 / 280 tris** (target 1,000 / 340), 37 parts, 0.93 x 0.23 x 0.11 m
  drawn, 0.97 m in the game at `model_scale` 1.3; cells Black 50 %, DarkGrey 29, Grey 17, Red 3, Yellow 1 (neutral
  96 %). The pump was first drawn just round the tube (6.4 cm deep): at 42 px/m the gun was a bar and a stock, the
  double's outline. It is 8.8 cm deep now and hangs below the tube with bare tube either side, so the outline is its
  own. **The stock ends at +0.30 (with its pad), not +0.36, the pump spans -0.43 to -0.27 and `Support` is at (-0.32, 0,
  -0.02)** ([reach](#the-left-hands-reach)); the pump travels +X 0.045, its rear then 5 mm short of the receiver. Added:
  a side saddle of four shells on the left (Red with Yellow heads, close-up detail), as on the police gun in the photos.
  The ammo glb is one shell (152 tris).

### Service pistol (`service_pistol`, #797, for `dual_pistols`)

A period semi-automatic service pistol of the 1911 type (references: five photos, `refs/weapons/service_pistol/`):
fits the drive-in's 1958 and reads apart from the revolver. One model, held in both hands (#789); the left hand's copy
is the same mesh, not mirrored (its port still faces right). The model folder is `service_pistol`, not `pistol`: that
id is the revolver's.

- **Layout:** muzzle -0.17 (bore z 0.045); the slide -0.17 to +0.04, top z 0.075, 0.045 deep, 0.04 wide (twice
  real), Black, rear serrations as detail; the frame under it, DarkGrey, the dust cover to -0.14; a round hammer spur
  at the rear; the grip raked 18 degrees back, its foot at (0.06, 0, -0.105), Wood panels on a DarkGrey frame, a
  magazine floor plate at the foot; a round guard deep enough for the finger (#460, as the revolver's).
- **Sockets:** `Grip` (0.032, 0, -0.058), up (-0.31, 0, 0.95), front (-1, 0, 0) (the revolver's, the rake a little
  straighter); `Trigger` (-0.03, 0, -0.015); no `Support`; `Muzzle` (-0.17, 0, 0.045); `Eject` (-0.06, 0.02, 0.065)
  on the slide's right.
- **Nodes:** `Magazine` (the reload's part: out the bottom of the grip, pivot (0.035, 0, -0.10), slides -Z), `Slide`
  (back +X 0.05 at the shot and locked back on empty).
- **Ammo glb:** the magazine.
- **Budget:** two are drawn at once, so 700 / 250 each keeps the pair inside one weapon's 1.5k / 500.
- **Re-cut lights:** the slide's sides (its biggest flat faces); the grips stay dark.

### Ray gun (`ray_gun`, #797)

Our own design (no reference photos): a **projection pistol**, the drive-in's wonder weapon, a blue energy pistol
that throws its bolt through a lens like the projector throws the film. Not the genre's ray gun: no ring stack or fins
round the barrel, no dish, no green; its read is the wide round lens barrel and the cell lying in the open body.

- **Layout:** muzzle -0.20 (the lens face, bore z 0.05); the lens barrel -0.20 to -0.11, radius 0.04 (signature:
  0.08 across, 2x the pistols' rule of 0.04), Blue, with a Grey bezel ring at its front and the Glow lens disc set 3 mm
  inside it; the body -0.11 to +0.06, z 0.005 to 0.10, two Blue side plates with an open top where the cell lies;
  three Glow vent slits on top of the barrel (detail); a Grey hinged lid over the body's rear; a raked Black grip
  (the flare gun's, with proud plates) and a round Grey guard.
- **Cell:** a Glow cylinder with Grey end caps lying along the body, centre (-0.03, 0, 0.065), radius 0.022, 0.12
  long: seen from the side through the open top and from above.
- **Sockets:** `Grip` the flare gun's (0.026, 0, -0.056), up (-0.37, 0, 0.93); `Trigger` (-0.025, 0, -0.012); no
  `Support`; `Muzzle` (-0.20, 0, 0.05) on the lens; no `Eject`.
- **Nodes:** `Lid` (turns 80 degrees up on its front edge, pivot (0.0, 0, 0.10)), `Cell` (the reload's part: slides
  out back and up, +X 0.10).
- **Ammo glb:** a cell.
- **Cells:** Blue about 55 %, Grey 20, Black 15, Glow 10 or less.
- **Re-cut lights:** the Blue plates and the lens barrel; the Glow cell stays its own glow.

### Freeze gun (`freeze_gun`, #797)

Our own design (no reference photos): a **cold-store rifle**, 1950s refrigeration made a weapon: a pressure tank of
coolant on top, a condenser of square fins along the barrel, a flared nozzle. Not the genre's freeze or lightning
guns: no glass bulb, no copper coils.

- **Layout:** muzzle -0.60 (the nozzle's front, bore z 0.05); the nozzle -0.60 to -0.53, a cone flaring to radius
  0.04, Grey outside, a Glow disc inside; the barrel -0.53 to -0.22, DarkGrey, carrying six square Frost fins
  (0.08 x 0.08 x 0.008, every 0.045 from -0.50); the receiver -0.22 to +0.04, Grey, a round Glow gauge on its left
  side; the tank on top, -0.30 to +0.02 at z 0.14, radius 0.045 (signature), Frost, rounded ends (a lathe), a Glow
  sight strip along its right side, a Grey valve wheel at its rear and a DarkGrey pipe down into the receiver; a Black
  vertical foregrip under the barrel's root; a Black pistol grip; a DarkGrey stock to +0.30 with a Black pad.
- **Sockets:** `Grip`, `Trigger` from the Tommy gun; `Support` on the foregrip (-0.30, 0, -0.06), up (0.08, 0, 1),
  front (-1, 0, 0) (the Tommy's vertical foregrip turn); `Muzzle` (-0.60, 0, 0.05); no `Eject`.
- **Nodes:** `Tank` (the reload's part: unclipped up and off, pivot at its rear clamp (0.0, 0, 0.14)).
- **Ammo glb:** a full tank.
- **Cells:** Frost about 35 %, Grey 30, DarkGrey 20, Black 10, Glow 5-8.
- **Re-cut lights:** the receiver, the tank and the fins; the Glow parts stay their own glow.

### The left hand's reach

Measured on #796's first build: with the plan's supports (0.32-0.34 ahead of the grip) the three guns were held in
the capture's holds with the left hand **3 to 29 mm into the weapon** (`HandContact`, the grip test's measure), while
the Tommy gun and the double held clean. The plan's numbers are drawing units, and these guns are held at 1.3 (the
.50 at 1.21), where the first long guns are at 0.84-0.96: 0.34 is 0.35 m in the game, against 0.24-0.28 m on the lever
rifle and the double. Add a stock long enough to put the butt 0.44 m behind the grip and the support was 0.75-0.85 m
from the shoulder; the Soldier's arm is 0.66 m with the chest turn giving some more, and the IK stopped short, inside
the gun. The capture prints the gap (`left_gap`: the left hand bone to where `WeaponHandsIK` sent it): 3.4 cm on the
.50 and 3 cm on the M249 still at 0.71 m, 1.7 cm on the pump at 0.72 m, 0 on the Tommy gun and the double.

**The rule:** the shoulder to the support, `|grip_offset.z| + |support.x| x model_scale x 0.8`, about **0.70 m or
less**, then measure the gap: the support's height and the chest turn move the limit by a few centimetres. Here
`grip_offset.z` is the butt's distance behind the grip in the game and 5 cm (the Tommy gun's margin; the rifle's and
the double's are 8). So on a gun held at 1.3: the support about 0.27-0.32 ahead of the grip and the butt at most
about 0.30-0.34 behind it, whatever the real gun's stock is. The support can only come back as far as the hand
clears the magazine or the box: at -0.26 on the .50 and -0.27 on the M249 the hand met them and the solver's left grip
left the thumb 80 mm off. So the support moved back to just ahead of them, and the stock took the rest:

| Model | `model_scale` | Butt (drawn) | `grip_offset.z` | Support (drawn) | Shoulder to support | `left_gap` |
| --- | --- | --- | --- | --- | --- | --- |
| Double shotgun | 0.96 | 0.43 | -0.41 | -0.36 | 0.69 m | 0 |
| `m249` | 1.3 | 0.31 | -0.37 | -0.30 | 0.68 m | 0.2 cm |
| `fifty_cal` | 1.21 | 0.345 | -0.385 | -0.28 | 0.66 m | 0 |
| `pump_870` | 1.3 | 0.30 | -0.365 | -0.32 | 0.70 m | 0 |

These `grip_offset`s are the ones `game/tests/captures/model_hold_sheet.gd` holds the three with; the holds of #793
should start from them, and keep the `model_scale` the grips were solved at (the grip test compares the two).

## What a batch hands back

Per weapon, in the pull request: the module in `weapon_specs/`, the three glb files, the `WEAPON` lines (triangles near
and far against the table above), `measure_weapons.py`'s line for it, a capture of it beside the ten at the same scale
(`render_weapon_plan.py`, then its silhouette at 42 px/m showing the signature mass), the Soldier holding it from the
side and from the shoulder camera, the headless import with no `ERROR`, and `test_weapon_muzzle.gd` passing.

Before the build issue writes a model's hold, `game/tests/captures/model_hold_sheet.tscn` films it in the Soldier's
hands (#796): its `HOLDS` table builds the hold from the plan's numbers and hands it to `PlayerAnimation` the way
`equip` does, beside catalogue weapons equipped the normal way, and prints `HANDS` per pose (`HandContact`, the grip
test's measure, and `left_gap`, how far the left hand stopped from where the IK sent it). `render_weapon_plan.py --add
<id>=<model_scale>@<row>` draws a model no hold file names yet.

## Reference photos

Downloaded from Wikimedia Commons into the workspace's `refs/weapons/<id>/` (never committed; each folder's
`meta.json` has the licence, author and source). Studied for shape and proportion only.

| Model | Photo | Licence | Author | Source |
| --- | --- | --- | --- | --- |
| `fifty_cal` | M107-M82A1 Long Range Rifle (7414625614) | Public domain | US Air Force | <https://commons.wikimedia.org/wiki/File:M107-M82A1_Long_Range_Rifle_(7414625614).jpg> |
| `fifty_cal` | M82A1 afmil | Public domain | Airman magazine | <https://commons.wikimedia.org/wiki/File:M82A1_afmil.jpg> |
| `fifty_cal` | Barrett M82A1 | Public domain | US Army | <https://commons.wikimedia.org/wiki/File:Barrett_M82A1.jpg> |
| `fifty_cal` | M107 1 | Public domain | unknown | <https://commons.wikimedia.org/wiki/File:M107_1.jpg> |
| `fifty_cal` | 191003-Z-XK920-1049 (image 7 of 14) | Public domain | Thomas Alvarez | <https://commons.wikimedia.org/wiki/File:191003-Z-XK920-1049_-_M107_.50_Caliber_Sniper_Rifle_(Image_7_of_14).jpg> |
| `fifty_cal` | 191003-Z-XK920-1048 (image 6 of 14) | Public domain | Thomas Alvarez | <https://commons.wikimedia.org/wiki/File:191003-Z-XK920-1048_-_M107_.50_Caliber_Sniper_Rifle_(Image_6_of_14).jpg> |
| `m249` | PEO M249 Para ACOG | Public domain | PEO Soldier | <https://commons.wikimedia.org/wiki/File:PEO_M249_Para_ACOG.jpg> |
| `m249` | M249 FN MINIMI DA-SC-85-11586 c1 | Public domain | US DoD | <https://commons.wikimedia.org/wiki/File:M249_FN_MINIMI_DA-SC-85-11586_c1.jpg> |
| `m4a1` | PEO M4 Carbine RAS M68 CCO | Public domain | PEO Soldier | <https://commons.wikimedia.org/wiki/File:PEO_M4_Carbine_RAS_M68_CCO.png> |
| `m4a1` | M4 PEO Soldier | Public domain | PEO Soldier | <https://commons.wikimedia.org/wiki/File:M4_PEO_Soldier.jpg> |
| `mp5` | Police MP5 (33507069243) | CC BY 2.0 | Tony Hisgett | <https://commons.wikimedia.org/wiki/File:Police_Heckler_%26_Koch_MP5_(33507069243).jpg> |
| `mp5` | MP5-1 | CC BY-SA 3.0 | Samuli Silvennoinen (derivative) | <https://commons.wikimedia.org/wiki/File:Heckler_%26_Koch_MP5-1.jpg> |
| `mp5` | DF-ST-82-10100 (an MP5 fired, 1982) | Public domain | MSGT Don Sutherland | <https://commons.wikimedia.org/wiki/File:A_U.S._Air_Force_SSGT_fires_a_9-mm_HK_MP5_sub-machine_gun_at_a_firearms_demonstration_during_exercise_Bright_Star_%2782_DF-ST-82-10100.jpg> |
| `ppsh` | PPSh-41 right side | CC BY-SA 2.5 | Makthorpe | <https://commons.wikimedia.org/wiki/File:Soviet_machine_gun_PPSh-41_right_side.jpg> |
| `ppsh` | PPSh-41 at the National Museum of Scotland | CC0 | 501ghost | <https://commons.wikimedia.org/wiki/File:PPsh-41_at_the_National_Museum_of_Scotland.jpg> |
| `ppsh` | PPSh-41 from soviet | CC BY-SA 3.0 | Lposka | <https://commons.wikimedia.org/wiki/File:PPSh-41_from_soviet.jpg> |
| `ppsh` | PPSh-41 from soviet (no background) | CC BY-SA 3.0 | Lposka | <https://commons.wikimedia.org/wiki/File:PPSh-41_from_soviet_noBG.png> |
| `pump_870` | 870 Police (55284788188) | CC BY-SA 4.0 | Mitch Barrie | <https://commons.wikimedia.org/wiki/File:Remington_870_Police_(55284788188).jpg> |
| `pump_870` | 870 Wingmaster (55416717369) | CC BY-SA 4.0 | Mitch Barrie | <https://commons.wikimedia.org/wiki/File:Remington_870_Wingmaster_(55416717369).jpg> |
| `pump_870` | 870 Wingmaster (55416542561) | CC BY-SA 4.0 | Mitch Barrie | <https://commons.wikimedia.org/wiki/File:Remington_870_Wingmaster_(55416542561).jpg> |
| `service_pistol` | M1911 from the 1912 Army manual | Public domain | US Army Ordnance Department | <https://commons.wikimedia.org/wiki/File:Colt_M1911_Pistol_from_1912_Army_manual.png> |
| `service_pistol` | Pistol, automatic (AM 775601-14) | CC BY 4.0 | Colt's Manufacturing Company | <https://commons.wikimedia.org/wiki/File:Pistol,_automatic_(AM_775601-14).jpg> |
| `service_pistol` | M1911A1 (NHHC 1968-141) | Public domain | US Naval History and Heritage Command | <https://commons.wikimedia.org/wiki/File:M1911A1_Pistol,_Belt,_Holster,_Magazine_Pocket_(NHHC_1968-141)_(Pistol_only).jpg> |
| `service_pistol` | Beretta 92FS Compact, right side | CC BY-SA 4.0 | Leo Tante | <https://commons.wikimedia.org/wiki/File:Beretta-92FS_Compact_Type_M_(right_side).jpg> |
| `service_pistol` | Beretta 92FS Compact, left side | CC BY-SA 4.0 | Leo Tante | <https://commons.wikimedia.org/wiki/File:Beretta-92FS_Compact_Type_M_(left_side).jpg> |

Real lengths (the published figures): PPSh-41 843 mm; MP5 (fixed stock) 680 mm; M4A1 757-838 mm (stock in and
out); M249 about 1,040 mm; M82A1 1,448 mm; 870 with an 18.5 inch barrel about 980 mm; M1911 216 mm.
