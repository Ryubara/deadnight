# Style bible

The look of Deadnight's 3D art, measured from our starting kit: the Quaternius Toon Shooter Game Kit (73 models,
CC0) and the Quaternius Zombie. Every number here comes from `tools/blender/measure_kit.py`; the contact sheets come
from `tools/blender/render_sheet.py` (both headless Blender scripts, how to run them is at the top of each) and are
attached to the pull request that added this page; renders of the kit are not committed. New assets follow these
numbers; when the kit and this page disagree, rerun the scripts and update the page.

All sizes are in metres at the kit's own scale (1 Blender unit = 1 m after the glTF import), unless a row says
otherwise. [Scale](#scale) gives the factor to Deadnight's game scale.

## Characters

Measured without the 14 weapons every kit character file carries in its right hand, in the rest pose (a T-pose)
unless the column says Idle (the first frame of the Idle clip, standing).
The zombie's Idle is measured on our built walker (`zombie_walker.glb`, whose Idle holds the arms the kit's lacks, see
[what broke](../research/zombie-variants.md#what-broke)), not on the kit file, where the Idle keeps part of the Crawl
pose.

| Character | Tris | Rest height | Idle height | T-pose span | Heads tall | Head % of height | Head width | Hips % | Neck % | Bones | Clips |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Soldier | 5,828 | 2.31 | 2.15 | 2.73 | 2.8 | 36 | 1.07 | 40 | 64 | 43 | 14 |
| Hazmat | 5,462 | 2.14 | 1.99 | 2.72 | 3.3 | 31 | 0.98 | 43 | 69 | 43 | 17 |
| Enemy | 4,594 | 2.30 | 2.18 | 2.72 | 2.8 | 36 | 0.92 | 40 | 64 | 43 | 17 |
| Zombie | 7,822 | 1.36 | 1.25 | 1.89 | 2.8 | 36 | 0.83 | 38 | 65 | 50 | 16 |

What the numbers say:

| Rule | Measured |
| --- | --- |
| Proportions | about 3 heads tall (2.8-3.3): the head is a third of the height and 0.9-1.1 m wide, three times the spacing of the shoulder joints (0.30 m) |
| Legs | short: hips at 38-43 % of the height |
| Hands | oversized mitts with three-joint fingers and a thumb; after the head, the second read of the silhouette |
| Arms | the kit's are long: 0.53-0.57 of the height (upper arm 0.388, forearm 0.440, hand 0.384 m on all three), the forearm longer than the upper arm, the fingertips hanging below the knee. Ours are 0.507: the forearm no longer than the upper arm, the fingertips at the knee standing ([Proportions](characters.md#proportions), #978) |
| Rig | one `CharacterArmature`: 43 bones on the kit characters (`Root`, `Body`, `Hips`, `Abdomen`, `Torso`, `Neck`, `Head`, shoulders, arms, three-joint fingers, legs, IK pole targets); the zombie has the same 43 plus `Tongue1-5`, `Eyelid.L/R` |
| Clips | shared by bone name: Idle, Run, Jump (three parts), HitReact, Death, Punch, Wave, Yes, No on all; Walk on all but the Soldier; Run_Gun, Idle_Shoot, Duck on the kit characters; Crawl, Run_Arms, Run_Attack, Idle_Attack on the zombie |
| Animation | 24 fps, in place (no root motion); the kit clips key only the bones they move (7-19 of 43), the rest hold the file's standing pose; new clips start from the kit's poses (`Idle_Shoot` frame 0 for every weapon hold) and split at `Abdomen` (32 upper bones, 11 lower): [Animation](animation.md) |
| Meshes | a skinned body plus a bone-parented head piece (helmet, hood, visor) and, on the Soldier, two 44-tri shoulder pads |
| Strays | every rigged file carries an unparented 80-tri `Icosphere`; strip it on import |
| Zombie scale | the zombie file is 0.59 the kit characters' size (1.36 against 2.31 m at rest) |

The index lists the kit characters at 7.9-12.1k tris; 14.9k of each file is the weapons, not the body.

## Weapons

| Weapon | Tris | Length | Height | Loose parts | Materials | Bevel mm | Origin % (along, up) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sniper | 1,441 | 2.05 | 0.76 | 327 | 3 | 16 | 77, 40 |
| Sniper (2) | 1,298 | 1.74 | 0.79 | 155 | 3 | 17 | 73, 40 |
| Shotgun | 1,264 | 1.55 | 0.33 | 74 | 4 | 16 | 81, 48 |
| Ak47 | 1,120 | 1.42 | 0.73 | 386 | 4 | 14 | 72, 44 |
| Rocket Launcher | 1,228 | 1.30 | 0.75 | 81 | 4 | 89 | 60, 15 |
| Short Cannon | 462 | 1.21 | 0.31 | 62 | 3 | 17 | 75, 51 |
| Grenade Launcher | 1,259 | 1.21 | 0.56 | 113 | 4 | 36 | 57, 51 |
| Smg | 1,006 | 1.14 | 0.62 | 85 | 4 | 24 | 89, 42 |
| Revolver | 1,354 | 0.99 | 0.53 | 148 | 4 | 25 | 84, 34 |
| Pistol | 990 | 0.79 | 0.48 | 101 | 3 | 29 | 86, 26 |
| Revolver Small | 1,350 | 0.66 | 0.51 | 85 | 4 | 16 | 81, 28 |
| Knife | 687 | 1.41 | 0.26 | 62 | 4 | 23 | 17, 41 |
| Knife (2) | 761 | 1.35 | 0.25 | 61 | 3 | - | 14, 50 |
| Shovel | 662 | 1.11 | 0.35 | 19 | 3 | 16 | 40, 50 |
| Fire Grenade | 916 | 0.85 | 0.57 | 46 | 4 | - | 61, 59 |
| Grenade | 820 | 0.61 | 0.56 | 42 | 3 | - | 46, 59 |

How they are built:

| Rule | Measured |
| --- | --- |
| Scale | toy-like: weapons are modelled at the characters' scale and held at that size (the copies inside a character file measure the same as the standalone files). A sniper is as long as the Soldier is tall; a pistol is 0.79 m |
| Triangles | guns 1.0-1.45k (the Short Cannon 462); melee 660-760; grenades 820-920 |
| Parts | kitbashed from many separate closed pieces (62-386 loose parts per gun), never welded into one shell |
| Silhouette | a side view reads first: the length runs along X, thin across (0.12-0.19 m for long guns) |
| Origin | at the grip: guns 72-89 % along from the muzzle, 26-51 % up; blades and the shovel near the handle end (14-40 %). The hand bone holds them with no offset |
| Colours | 3-4 flat materials: Grey `#818491` or `#8f92a0`, DarkGrey `#414141`, Black `#252525`, Wood `#95703d`; red or green only as an accent |
| Handedness | every held copy is parented to the right hand's `Index1.R` bone |

### Attachment points

Where an effect or a hand meets a model is part of the model, placed by the modeller who owns it, never an offset
typed into gameplay code. **Every firearm carries an empty named `Muzzle`**, a child of the weapon's root, at the
centre of the barrel's open end, turned so its **-Z points out of the barrel** (Godot's forward; in Blender that is the
empty's local +Y, because the glTF export turns Z up into Y up). A gun with two barrels side by side gets one `Muzzle`
centred between them. Melee weapons and grenades get none. The held and far levels carry it at the same place. The
flash and the shot leave from it; the numbers and the test are in [Weapons](../research/weapons.md#the-muzzle). A
tool carries the point it strikes with the same way: the repair hammer's `Face`, -Z out of the face.
A gun with an ejection port carries `Eject` at the port's centre, keeping the weapon's axes, so its -Z in Godot
points out of the gun's right side ([Weapon models](../research/weapon-models.md#hand-and-effect-points)).

## Bevels

Bevel width is the short side of narrow quads (at least 3:1) folded 15-75 degrees against both long neighbours,
after welding the glTF's split vertices and rebuilding quads from its triangles. Medians per class:

| Class | Models with bevels | Bevel width median | Bevel strips per model (median) |
| --- | --- | --- | --- |
| Characters | 4 of 4 | 23 mm (18-28) | 119 |
| Guns | 11 of 11 | 17 mm (14-36; Rocket Launcher 89) | 48 |
| Melee | 2 of 3 | 19 mm | 1 |
| Grenades | 0 of 2 | - (round shapes, no strips) | 0 |
| Props under 1 m | 1 of 9 | - | 0 |
| Props 1-3 m | 6 of 24 | 30 mm | 0 |
| Props over 3 m | 16 of 21 | 99 mm | 26 |

Rule: bevel the edges that face the camera on characters and weapons, about 15-25 mm at kit scale (one segment, a
single chamfer); small and medium props keep hard edges; buildings and large props chamfer about 100 mm. The soft
look comes from chunky shapes and one-segment chamfers, not from smoothing.

## Triangles per class

| Class | Count | Min | Median | Max | Size median (m) |
| --- | --- | --- | --- | --- | --- |
| Character (body only) | 4 | 4,594 | 5,645 | 7,822 | 2.72 (T-pose span) |
| Gun | 11 | 462 | 1,259 | 1,441 | 1.21 |
| Melee | 3 | 662 | 687 | 761 | 1.35 |
| Grenade | 2 | 820 | 868 | 916 | 0.73 |
| Prop under 1 m | 9 | 6 | 108 | 732 | 0.86 |
| Prop 1-3 m | 24 | 108 | 424 | 3,584 | 1.89 |
| Prop over 3 m | 21 | 218 | 1,374 | 7,168 | 4.57 |

The heavy props are repeats of one shape: Sack Trench (7,168) and Sack Trench Small (3,584) are rows of sandbags;
Structures are 5.1-5.6k; Broken Car 5.4k.

## Colour and materials

| Rule | Measured |
| --- | --- |
| Kit characters, weapons, props | flat-colour materials, no textures: 2-4 per asset (median), at most 8 (a building) |
| Shading values | roughness 0.415 and metallic 0.4 on every kit material |
| Zombie | one material, `Atlas`, a 512 x 512 `Zombie_Atlas.png` palette: 100 % of faces have a UV area under one texel (each face is collapsed onto one colour swatch), 11 swatches used |
| Kit palette | 40 distinct flat colours across the kit; the ten that cover most area are below |
| Defaults left in | a few materials keep Blender's default 0.8 grey (`#e7e7e7`: the grenades' DarkGreen, the Gas Can's DarkRed, the Street Light's Light); do not copy them |
| Vertex colours | some weapons carry a `COLOR_0` attribute; the colour lives in the material, not in it |

| Name | sRGB | Use |
| --- | --- | --- |
| Grey | `#818491` | metal, concrete, the most-used colour |
| Yellow | `#d1ab46` | hazard paint, barriers |
| Green | `#496321` | military paint, crates |
| Red | `#8c3735` | barrels, accents |
| Blue | `#3b4b8c` | containers |
| Tree_Green | `#6b7f26` | foliage |
| Cardboard | `#9b7048` | boxes |
| Wood | `#95703d` | stocks, pallets |
| Grey2 | `#5f5f5f` | darker metal |
| Black | `#252525` | rubber, grips |
| Zombie skin | `#769751` | 71 % of the zombie's area |
| Zombie clothes | `#3f5363`, `#664531` | trousers, belt |
| Character skin | `#a68450`, `#b89359` | Soldier, Enemy |
| Character mains | `#5c6d37`, `#c79b17`, `#991c22` | Soldier olive, Hazmat yellow, Enemy red |

### Palette imports

Every palette or atlas PNG (the weapons', props', drive-in's, zombies' and Soldier's, and the images Godot extracts
from a glb) is imported **lossless, without mipmaps, with Detect 3D off** (`compress/mode=0`,
`mipmaps/generate=false`, `detect_3d/compress_to=0`). Faces sit on one swatch each, so nothing is gained by mipmaps,
and block compression or a mip blends neighbouring swatches: the editor then showed other colours than the build. The
lot's tiling textures are the one exception (mipmapped, see [Lot surfaces](#lot-surfaces)).

| What | Measured (pinned Godot 4.7.2, issue #441) |
| --- | --- |
| Detect 3D on (Godot's default `compress_to=1`) | opening the editor on the drive-in rewrote 11 `.import` files: VRAM compression (`s3tc_bptc`, `etc2_astc`), mipmaps on; a headless import never does, so the checkout was dirty after every editor session |
| Detect 3D off | the same editor session leaves `git status` clean |
| A glb's extracted image | Godot rewrites the PNG only when the image inside the glb changes (`generator_parameters` md5 in the `.import`); it keeps `compress/mode` and Detect 3D but turns mipmaps back on |

`tools/check_texture_imports.py` holds the rule (tiling textures listed by path, everything else a palette). The
Blender builds write each palette's `.import` as they save it (`tools/blender/palette_import.py`), the pre-commit hook
`texture-imports` corrects any other (an extracted image after a rebuild) and fails, and CI runs the check.

## Scale

The kit is oversized for a game where players stand about 1.8 m tall, and the zombie file is smaller than the kit.
Scale on import, the same factor for a character and what it holds:

| Model | Rest height | Factor to 1.8 m | Proposed factor |
| --- | --- | --- | --- |
| Kit characters and weapons | 2.14-2.31 | 0.78-0.84 | 0.8 (keeps their height differences: 1.71-1.85 m) |
| Zombie | 1.36 | 1.32 | 1.3 (1.77 m at rest; it stands 1.63 m in Idle, hunched) |

At 0.8 a gun bevel becomes about 14 mm and the AK 1.14 m long: still toy-sized, which is the look.

## Budgets (proposed for the web)

The web build renders with Godot's Compatibility renderer under WebGL2, where draw calls cost more than triangles.

| Class | Gameplay LOD | Far LOD | Materials | Notes |
| --- | --- | --- | --- | --- |
| Player character | 6k tris | 2k | 1 (atlas) | the kit bodies are 4.6-5.8k; one held weapon at a time, never the whole set |
| Zombie | 4k | 1.5k | 1 (shared atlas) | crowds of 20 or more: 20 x 4k = 80k tris; the kit zombie (7.8k) needs about half its triangles removed |
| First-person weapon | 3k | - | 1 | seen up close; the kit's 1.0-1.45k already reads well |
| Third-person and world weapon | 1.5k | 500 | 1 | the kit's own range |
| Prop under 1 m | 800 | 300 | 1 | kit median 108, max 732 |
| Prop 1-3 m | 1.5k | 500 | 1 | kit median 424; Sack Trench Small (3.6k) would be split or rebuilt |
| Prop over 3 m, building | 5k | 1.5k | 1-2 | kit median 1.4k; Structures 5.1-5.6k, Broken Car 5.4k |

Decision: one shared palette atlas and one material per asset family (characters, zombies, weapons, props), the
zombie's pattern, instead of the kit's 2-4 flat materials per asset. Faces collapse onto colour swatches, so the
look stays flat and the colours above stay the palette, and a whole family batches into fewer draw calls. Converting
a kit asset is a palette remap: each flat material becomes a swatch in the family atlas.

## Lot surfaces

The lot's CSG boxes are painted, not modelled: `tools/world/build_lot_textures.py` writes eight greyscale patterns,
the 30 materials that tint them and the small shader that draws them (`game/assets/lot/`). The kit has no textures,
so a pattern only says what a surface is, in two to four flat tones with hard edges; the colour is the material's
tint, from the palette above.

| Rule | Value |
| --- | --- |
| Textures | 256 x 256 greyscale PNG, lossless, mipmapped, Detect 3D off (set in the `.import` and listed as tiling in `tools/check_texture_imports.py`), 0.4-4.6 KB each |
| Patterns and tile | asphalt 4 m (three blotch tones, chips, cracks), gravel 2 m, concrete 4 m (2 m slabs), planks 2 m (0.25 m boards), corrugated 2 m (0.125 m ribs), blocks 3.2 m (0.4 x 0.2 m, running bond), diner tiles 2 m (0.5 m), shutter 2 m (0.125 m slats) |
| Tones | the lightest tone is 250 of 255, so the tint is the surface's colour; seams and gaps 100-150, never black |
| Projection | the lot shader (`game/assets/lot/lot_surface.gdshader`) projects the pattern in world space onto each face's own plane: a box of any size keeps its pattern at true scale and needs no UVs. One texture read a pixel; Godot's triplanar (three reads) cost about 10 ms a night frame in the software-rendered web build |
| Shading | matte: Lambert diffuse, no specular term (cheaper per light), metallic 0; the kit's 0.4 metallic only darkens a surface with nothing to reflect |
| Tints | ground: asphalt `#5a5d66` (field) and `#4a4c54` (road), gravel `#7a705a` (yard), `#544c3c` (back lot); walls: blocks `#d8b67a` (stand), `#9a9ca6` (booth); corrugated Grey (midway), Tree_Green (yard), Blue (containers); planks `#7d6446` (fence) |
| Doors | the purchase doors are Yellow `#d1ab46` shutters, and nothing else is: no surface keeps the greybox's debug red |
| Paint | parking lines `#d8d2bc`, 0.12 x 5 m, between every two stalls of a row; the road's centre line Yellow, 3 m dashes every 6 m; each set one `MultiMesh` (one draw call) |

## Props

The lot's props (`tools/blender/build_props.py`, [the lot](map.md#props)) follow these numbers:

| Rule | Value |
| --- | --- |
| Scale | 0.8, the kit's factor: a Broken Car is 4.4 m long (the lot's cars are 4.5 m), a shipping container 3.5 x 1.7 x 1.7 m (the kit's container is shorter than its characters; kept, it is the kit's look) |
| Origin | the middle of the footprint, on the ground |
| Atlas | one family palette, 40 x 40, 8 px swatches: the kit's 17 prop colours and a DarkRed for the Gas Can's default grey; each kit material takes the nearest swatch; roughness 0.415, metallic 0 (the kit's 0.4 reads dark at night with nothing to reflect) |
| Files | `.gltf` + `.bin` per prop, all pointing at one `props_palette.png`, so the texture is loaded once |
| Triangles | 108-1,454 for props under 3 m (budget 800 / 1.5k), Shipping Container 1,336 (budget 5k); the Tires (1,776) are cut with a collapse decimation to just under the budget, and the Broken Car (5,432) to 2,327, because the lot has 19 wrecks; the far level is Godot's generated LOD |
| Web cost | the field the night starts on went from 164 draw calls and 2k triangles to 109 and 28k (a car is one model over two hidden blocks, where it was two drawn boxes). On a GPU (Chrome, no frame cap) the night's frame p50 stayed at about 3 ms; in Chromium's software renderer (SwiftShader, CI) it went from 83 to 100 ms, one 60 Hz frame |
| Tiny props of a model | a small copy of a weapon (the prize crane's case) is the weapon's far level at half its length in the hands (0.24-0.56 m), and all of them are merged into one mesh with the weapons' palette: 20 in the case are 5,352 tris and one draw call (#830, [the crane](../research/mystery-box.md#how-it-looks-and-how-to-film-it)) |
| Something the player must read | at the camera's eye height or the camera's side, never in front of the Soldier's chest or head: from 2.3 m behind him the head covers the middle of what he faces below about 1.65 m (the prize board's bottom is 1.72 m) |
| Parked car | the lot's own sedan, 424 tris, five paints: chamfers of 80 mm on body and cabin (the big-prop rule), the rest hard; 76 of them stand on the field, so every part is a plain box or an 8-sided wheel |

## Modular characters

The Soldier's parts (`tools/blender/build_soldier_parts.py`, [characters](characters.md)) follow these numbers:

| Rule | Value |
| --- | --- |
| Head landmarks (kit metres, at rest, front is -Y) | hood x +-0.35, y -0.36..0.32, top z 2.20; eyes z 1.75-1.89 at x +-0.12..0.23; face front y -0.37; collar ring z 1.40-1.68, r 0.36 |
| Added pieces | primitives with a 20 mm one-segment chamfer (10-15 mm on small rims), 44-436 tris each, skinned 100 % to one bone; hair is rounded (spheres and domes, no chamfer) in the crown's `hair` swatch, `hair_shade` only on faces that point down, never a box (a box on the crown read as a cap) |
| Painted bands | a stripe or band on a kit-body part is cut into the mesh between two planes (`cut_stripe`: the Usher's trouser stripe, 2 x 45 mm at kit scale), never painted by face centre (that leaves sawtooth edges) |
| Atlas | 256 x 64, 16 px swatches: row 0 the five look channels and their shades (x 0.75), row 1 eleven fixed colours |
| Assembled presets | 4,490-5,080 tris against the 6k player budget, one material, 5-7 meshes |
| Far level of detail | 1,515-1,812 tris against the 2k far budget (the build fails over it): every part over 260 tris collapse-decimated to one ratio (0.333) solved for the heaviest preset, smaller pieces kept whole; same skeleton, atlas UVs and material, swapped at 18 m. In Godot at the swap 0.24 % of pixels change |

## Drive-in props

The kit has nothing a drive-in needs, so these are ours (`tools/blender/build_drivein_props.py`, headless Blender):
chamfered boxes and 6-12-sided cylinders at game scale (a player is 1.8 m), one material on a 5 x 5 palette atlas of
16 px swatches (`game/assets/drivein/drivein_palette.png`: the kit colours above plus cream `#e6d8b0`, amber
`#e8a33a`, sign red `#b8322e`, teal, chrome, glass, popcorn, concrete), roughness 0.415, metallic 0. Each has a scene
in `game/world/drive_in/fixtures/` with hidden CSG collision (what the navigation and the camera tests read).

The atlas stores every swatch as its sRGB value, the hex the builder's `PALETTE` names (a byte image's `pixels` in
Blender are the stored values: `palette_image()` writes the hex as it is, as `build_props.py` and `smallmap_kit.py`
do). Until #651 it stored the linear value, so every prop drew far darker than its colour (Concrete `#9a968c` as
`#524e43`); `game/tests/world/test_drivein_palette.gd` reads cells back against the hex. To check a lot capture
after a palette change, `game/tests/captures/drivein_props_night.tscn` frames the props up close at night.

| Prop | Tris | Budget | Size (m, w x d x h) |
| --- | ---: | ---: | --- |
| Speaker post (player-only collision) | 328 | 800 | 0.83 x 0.32 x 1.46 |
| Trash can | 240 | 800 | 0.6 x 0.6 x 1.04 |
| Popcorn machine (counter top) | 344 | 800 | 0.74 x 0.54 x 1.03 |
| Picnic table | 316 | 1,500 | 1.8 x 1.5 x 0.8 |
| Projector | 416 | 1,500 | 0.9 x 1.72 x 2.04 |
| Menu board | 416 | 1,500 | 4.2 x 0.16 x 1.6 |
| Ticket booth | 628 | 1,500 | 2.6 x 2.7 x 3.64 |
| Concession counter | 564 | 5,000 | 10.2 x 2.0 x 1.2 |
| Marquee | 980 | 5,000 | 6.2 x 0.6 x 6.3 |
| Screen frame, truss, legs, stays | 1,448 | 5,000 | 33.6 x 9.7 x 16.8 |
| Generator set (yard cage, #853) | 1,872 | 5,000 | 3.2 x 1.52 x 5.51 |

Chamfers: 30 mm on props of 1-3 m, 80 mm on the booth, the screen and the marquee; none on parts under 0.1 m. No
emissive: the marquee's bulbs and the booth's sign are amber and cream swatches; lighting them is the lighting pass's.
`tools/blender/render_drivein_sheet.py` renders the contact sheet beside the kit Soldier at 0.8.

The generator set stands in the greybox's 3.2 x 1.6 x 1.8 m `Generator` block, which stays where it was, hidden, as its
collision: nothing of the model below 1.8 m leaves the block, and the frame, day tank and stack above it have no
collision (the cage's openings, the camera probes, the slot scan and the walking mesh's key are unchanged). Its parts
are sized by the sight line over the cage's 3.0 m walls: from the gate (19 m off, the camera about 2.2 m up) the line
over the wall reaches 3.1 m at the generator, so the red day tank sits with its belly at 3.18 m (axis 3.68 m), the
amber running light at 4.68 m and the stack's lip at 5.3 m. Below the wall the radiator faces the west opening (the
midway link sees its fan ring) and the control panel the east one. The running light is the model's amber swatch lit
by `ModelGlow` from `GeneratorGlow` (`steady`: no shimmer of its own, so it is steady on a healthy tank, flickers with
the brown-out and is dark when dry), with a 1.6 m halo whose lowest edge (3.88 m) stays over the walls from any side.
Cost: one surface where the block was one, plus the halo (one draw while lit): +1 draw call, +1,860 triangles in every
view that sees it (`game/tests/captures/generator_views.tscn` prints the renderer's counts at nine views).

## Small-map kit

The second map's modular building kit ([small map: art and kit](../research/maps/small-map-art.md), where each
number comes from) follows these numbers. They live in `tools/blender/smallmap_kit.py`:

| Rule | Value |
| --- | --- |
| Grid | 0.5 m snap. Wall modules 1, 2 and 3 m wide, 2.8 m tall, 0.3 m thick (ground) or 0.2 m (upper). A storey is 3.4 m: 3.2 m clear (the formula's ceiling, 3.0 to 3.6 m) and a 0.2 m slab, so a wall module takes a 0.4 m band on top ([the second map](smallmap.md#where-it-parts-from-the-kit-page)) |
| Openings | purchase doorway 2.0 x 2.4 m (the kit's wide opening: the formula asks every camera passage 1.8 m and doors 2.0 m), zombie window 1.2 x 1.3 m with its sill at 0.9 m in a 2 m gap, stair 2.0 m wide with 17 risers of 0.2 m and 0.3 m treads |
| Atlas | the drive-in palette in its own cells plus Plaster `#b3a588`, Sandbag `#a88d62`, Chalk `#ece6d2`, Rust `#7d4b2f` and Soot `#2f2c2a` in its five empty cells, so drive-in props share it |
| Chamfers | 60 mm on wall pieces and frames, 30 mm on props of 1-3 m |
| Flat surfaces | plain walls, floors and ceilings stay CSG with a lot pattern, cut per room for the light cap; only shaped pieces are modelled |
| Shell materials | `smallmap_wall_ground` (`blocks`, Concrete), `smallmap_wall_upper` (`plaster`, Plaster), `smallmap_floor_ground` (`concrete`), `smallmap_floor_upper` (`planks`), `smallmap_ceiling` (`plaster`) |
| Files | `game/assets/smallmap/<name>.gltf` + `.bin` on `smallmap_palette.png` (sRGB swatches, 16 px, lossless, no mipmaps, Detect 3D off), a fixture each in `game/world/smallmap/fixtures/` with hidden CSG collision, written by the build script |
| Walls and openings | 108-992 tris against 1.5k (`tools/blender/build_smallmap_walls.py`); openings in a ground (0.3 m, Concrete) and an `_upper` (0.2 m, Plaster) variant |
| Stairs | timber treads (Wood) on DarkWood stringers, Grey pipe rails 1.0 m over the nosings with Rust shoes; the collision is one hidden ramp per flight through the treads' middles, the rail a player-only blocker on the open side (`build_kit_stairs.py`) |
| Debris blocker | furniture and rubble filling the opening in parts named in the order they come away, gaps at the top for the far room's light, 1,300 tris |
| Cover and clutter | 16 props from `tools/blender/build_smallmap_props.py`, 44-1,320 tris against the 800 / 1.5k budgets (a 2 m sandbag line 1,320, a tall cabinet 420, a chair 184); sizes in [the parts list](../research/maps/small-map-art.md#modular-kit-parts-list) |
| Lamps | a bulb is the lamp's Popcorn swatch, lit by an emission texture of the atlas's layout (`KitLamp`), never a second material; a pendant's shade is 0.6 m with its rim at 2.15 m, under 600 triangles |
| Light | one or two real lights a room; every other light is an additive card on the lot's `glow.gdshader` or `beam.gdshader` (pools, haze, moon shafts with bar shadows, the far room's glow, chalk), so it takes no light slot and builds no new GL program ([lamps and light cards](../research/maps/small-map-art.md#lamps-and-light-cards)) |
| Roof | 2 m bays along the ridge, an 8 m span outside to outside at 30 degrees, a 0.4 m overhang, the ridge 2.59 m over the wall top; rafters at 1 m centres; boards at a bay's end lap 20 mm into the next so no crack shows the sky |
| Outside | bare trees 4.7 to 8.4 m, a utility pole 7 m with 12 m wire spans, wire fence runs of 2 m with a post, coils 2 m; a far level of detail of 300 tris or fewer for what the backdrop repeats |
| Backdrop | past the yard's fence, unshaded (`backdrop_haze.gdshader`: lit by the moon and ambient, its own capped haze), one MultiMesh a model; at most 75k triangles and 40 drawing nodes in all ([the backdrop](../research/maps/small-map-art.md#the-backdrop)) |

## Measuring again

| Step | Command (pinned Blender, headless) |
| --- | --- |
| Measure the kit | `blender -b --factory-startup -P tools/blender/measure_kit.py -- --bundle <bundle> --extra Zombie=<zombie.glb> --out <scratch>/kit.json` |
| Character sheet | `blender -b --factory-startup -P tools/blender/render_sheet.py -- --model Soldier=<glb> ... --view front --pose Idle --out <png>` |
| Weapon sheet | `... render_sheet.py -- --model Sniper=<glb> ... --view side --row-width 7.5 --row-height 1.25 --px-per-m 360 --out <png>` |

Import kit files with `bone_heuristic="TEMPERANCE"` (the scripts do, in `kitlib.gltf_import`): Blender's default
re-orients the bones and puts every bone-parented mesh in the wrong place (the Soldier's shoulder pads float beside
his helmet).

## UI look

The UI is a 1958 drive-in at night: lit signs, painted lettering, ticket and poster print. It must not read as default
Godot or as generated UI. Type candidates and the maintainer's choice are in [typography](typography.md).

| Reads as default or AI UI | Deadnight does instead |
| --- | --- |
| Inter, Poppins, Montserrat, Bebas Neue, Orbitron; one family at one weight | A signage display face plus a condensed text face, both with a drawn or printed character |
| Frosted glass panels, blur, soft inner glow | Flat, opaque paper and sign surfaces with a hard offset shadow, as on a printed poster |
| Purple-to-blue gradients, aurora blobs | A near-black night with one warm light source (the screen's glow) and the token amber and hot orange |
| Pill buttons and rounded cards on every screen | Rectangles with square or notched corners: marquee boards, tickets with tear lines and notches |
| Evenly spaced, centred cards in a grid | Left-aligned stacks on a strong margin, one big title, uneven scale (huge number, small caption) |
| Wide, airy letter-spacing on bold type | Tight tracking on condensed capitals; wide tracking only on tiny overlines |
| Even neon glow on everything | Neon only on the sign (title, focused item): a layered glow with a hot edge; the rest is unlit |
| Emoji or stock icon sets as decoration | Drawn marks: the focus arrow, bulbs, stars, ticket numbers |
| Sparkle or gradient on every number | Plain, large numerals in the display or text face; colour carries meaning (round in hot orange, points in amber) |
| A glow on every hovered card | The focus mark (a lit arrow) moves to the item and the item brightens; nothing else changes |

Rules:

- **Two faces** (display and text); a third only as one accent (a script on the lit sign).
- **Hierarchy by scale and case.** The title and big numbers are several times the size of menu text; captions are
  small capitals with wide tracking.
- **Paper and light.** Cream (`ink`) and ticket paper for print, amber and hot orange for light, the night background
  for everything else; no new hues.
- **Layout.** Align to a left margin; put settings and the HUD on a separate axis from the menu so the screen is not
  one centred column; leave the lower fifth to the dark lot and its parked cars.
- **Motion** keeps to the [UI foundation](../research/ui-foundation.md) values: no easing is linear, reduced motion
  snaps.
