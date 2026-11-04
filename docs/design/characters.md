# Characters

Every player is the Soldier on one shared rig, dressed from swappable parts, as him or as her (#678). A look is data:
one part id per slot and one palette index per colour channel. The customization screen (#101) edits that data; the game
assembles it on the model. Everything here is built by one script, `tools/blender/build_soldier_parts.py`, which also
writes the catalog `parts.json` beside the model, so this page, the file and the screen cannot drift.

## The files

| File | What it holds |
| --- | --- |
| `game/assets/characters/soldier_parts/soldier_parts.glb` | `CharacterArmature` (the Soldier's 43 bones), every clip of the Soldier (from `tools/blender/soldier_clips.py`, untouched) and one skinned mesh per part, all named `<slot>__<part>` |
| `game/assets/characters/soldier_parts/soldier_parts_atlas.png` | the one palette atlas every part uses: a row of colour-channel swatches the game repaints per look, and rows of fixed colours |
| `game/assets/characters/soldier_parts/parts.json` | the catalog: slots, parts, channels, palettes, the character choice and the twelve presets |
| `game/assets/characters/soldier_parts/soldier_look.gd` | `SoldierLook`: reads the catalog, applies a look to an instanced model, picks a default preset per player |

## A look

```json
{
  "parts": {
    "head": "plain", "hair": "pompadour", "headwear": "none", "torso": "jacket",
    "legs": "cuffed", "feet": "boots", "eyewear": "none", "neck": "none", "arm": "none", "body": "male",
    "mouth": "smile"
  },
  "colours": {"skin": 2, "hair": 0, "primary": 0, "secondary": 9, "accent": 1}
}
```

- `parts`: every slot has exactly one part id from `parts.json`; `none` is a part (it shows nothing) in every slot
  that allows it. A missing slot takes the slot's `default`.
- `colours`: an index into the channel's palette (`skin` into `palettes.skin`, `hair` into `palettes.hair`,
  `primary`, `secondary` and `accent` into `palettes.cloth`). An index out of range wraps (`index % size`).
- A preset is a look with an `id` and a `name`. A saved or sent look is the two dictionaries above; it is a few dozen
  bytes, so it travels in the lobby state as it is.
- Headwear that covers the head (`hides_hair: true` in the catalog) hides the hair part; the look keeps its hair id. A
  one-piece top (`hides_legs: true`, the Coveralls) has legs of its own and hides the trousers the same way.
- `body` is the character (below). A look saved before it existed has none and is his.

## Slots

| Slot | Bone(s) | Parts |
| --- | --- | --- |
| head | Head, Neck | one closed head with its own neck, a buzz of hair, the kit's eyes and brows (#895, [Character faces](../research/character-faces.md)): `plain`, `stubble`, `beard` |
| hair | Head | `none`, `crew`, `pompadour`, `flattop`, `ponytail`, `bob`, `curls`, `bun` |
| headwear | Head | `none`, `helmet` (the kit Soldier's), `pillbox`, `ballcap`, `papercap`, `ranger`, `visor` |
| torso | spine, arms, hands | `vest` (the kit Soldier's), `jacket`, `shirt`, `rolled`, `tank`, `letterman`, `usher`, `coveralls` (with its own legs) |
| legs | hips, legs (the bib: the trunk) | `trousers`, `cuffed`, `shorts`, `striped`, `overalls` |
| feet | feet | `boots`, `sneakers`, `shoes`, `saddle` |
| eyewear | Head | `none`, `sunglasses`, `glasses`, `goggles`, `cinema` |
| neck | Neck, trunk | `none`, `scarf`, `bowtie`, `lanyard`, `bolo` |
| arm | UpperArm.L | `none`, `armband` |
| body | - | `male`, `female`: the character (no mesh of its own) |
| mouth | Head | `smile`, `line`, `grin`, `open`, `smirk`, `oh`, `frown`, `teeth`: free to everyone, on every head (#1061). One mesh at every distance, no `__far` copy |

Names: slot and part ids are lower-case ASCII words; the mesh node is `<slot>__<part>` (two underscores), so
`torso__letterman`. A new part is a new entry in the build script's tables and a rebuild; ids are never renamed once
shipped (saved looks refer to them).

## The character

The female Soldier (#678) is the same skeleton and every same clip with her own face, torso and legs. The `body`
slot came last on the wire at version 2, the `mouth` slot after it at version 3. A part with a variant for her has a
`female` entry in `parts.json` (`mesh`, `tris`, `mesh_far`, `tris_far`: the node `<slot>__<part>__female`), and
`SoldierLook.visible_meshes` shows it when the look's `body` is `female`; every other part (hair, hats, eyewear,
neckwear, the armband, the shoes) is shared, so every outfit fits both.

| Part | Hers |
| --- | --- |
| Face | his head with lashes over each eye, brows half as tall and arched, smaller mouths (0.115 m against his 0.135 where a mouth is full width). Her names for the three head choices: Natural, Freckles (dots of `skin_shade` under the eyes) and Rosy (`blush` cheeks): no beard |
| Torso, legs | his six tops and four trousers moved at rest by one warp (`female_shape`): a chest of two soft lobes, a 13 % narrower waist, 5 % wider hips. The chest's weights lean 60 % to `Torso`, so the shoulders do not pull it. Arms and hands do not move |
| Hair | three cuts of hers, `bob` (ends flared clear of the collar), `curls` (two rolls on top, the back to the nape) and `bun`; each hair part names the character it belongs to (`body`), and the ponytail is either's |

In the Loadout tab (and the wardrobe) the first row is **Character** (Male, Female). Switching it keeps the outfit and
the colours and swaps a cut of the other character's for this one's own (crew cut for him, bob for her,
`CharacterLook.set_body`); the Preset row offers that character's presets; Randomize keeps the character. The choice
is part of the look, so it is saved with it when the player leaves the tab (#489), sent on join and drawn by every
client, and the menu's soldier wears it at once.

**Voice.** A soldier speaks with their character's voice: her lines are the female takes (`voxf_`, #679), his the male
ones (`vox_`). `SoldierVoice` gives a player whose frame entry names no `voice` the voice of the character they chose
(`look_voice`, read from the night's look table), so choosing her is all it takes; a `voice` in the frame wins, and a
player whose look has not arrived yet speaks as the male Soldier.

**Checked** (`tools/blender/measure_soldier_body.py`, all 55 clips of the Soldier's files, his against hers): her
trunk stretches no more than his (the 99th percentile edge, within 10 %) in every clip; her cuts sit in the collar no
more than his (the bob 13 vertices in the grenade throw, his ponytail 17); her forearms go no deeper into her chest
than his into his (the ten deepest vertices, within 12 mm) in 53 clips. Walk and Run_Gun flag two vertices of her
left forearm at the side of her waist (12 and 18 mm on that mean): the kit's own arm swing grazes the trunk there
(his short-sleeved tops have one 61 mm vertex in Run_Gun), and nothing shows in the
`tools/blender/render_soldier_views.py` sheets. Every
weapon sits on its grips in every top for both (`test_menu_grips.gd`); no hair or hat reaches the lens before the
camera hides the body (`test_hair_and_the_camera.gd`).

## Proportions

The arm is in proportion to the body (#978): the upper arm 0.388, the forearm 0.352 and the hand 0.384 kit metres
(0.310, 0.282 and 0.307 in the game), 1.124 in all, 0.507 of the height (2.216, sole to the top of the head, hair and
hats left out), the forearm 0.91 of the upper arm, and standing (Idle) the fingertips hang at 0.198 of the height, at
the knee. The kit Soldier's arm (and the Hazmat's and the Enemy's: one skeleton) was 1.212, 0.547 of the height, its
forearm (0.440) longer than its upper arm, and the fingertips hung below the knee; every look of both characters wore
it unchanged, and it read longest on her bare-armed looks (Carhop, Pit crew), where a thin skin-coloured arm ran from
the sleeve to the knee beside her narrower waist.

| | Upper arm | Forearm | Hand | Arm / height | Forearm / upper arm | Idle fingertips / height |
| --- | --- | --- | --- | --- | --- | --- |
| Kit Soldier, and every look before #978 | 0.388 | 0.440 | 0.384 | 0.547 | 1.13 | 0.165 |
| Every look, his and hers, since #978 | 0.388 | 0.352 | 0.384 | 0.507 | 0.91 | 0.198 |

`tools/blender/soldier_arms.py` shortens the forearm to `FOREARM` (0.80) of the kit's at rest, on the imported kit
Soldier, before any clip is authored, in `build_soldier.py` and `build_soldier_parts.py` alike: each wrist moves along
the forearm toward the elbow with the hand's bones and skin, and the forearm's skin is drawn in along it. The hand
(the grips are solved on it) and the upper arm keep their size. The parts build's places along the arm (the cuff, the
bare wrist's seam) are written in the kit's numbers and read through `soldier_arms.along`. Her arm is his: the
skeleton is one, and the clips are shared. Measured by `tools/blender/measure_arms.py` (an `ARM` line per look and per
kit character); held by `game/tests/character/test_arm_proportions.gd` (each look's arm over its height, the forearm
against the upper arm, hers against his, and every hold of the menu keeping the bones' lengths with the left hand on
its fore-end).

## Colour channels

Faces of every part sit on one swatch of the atlas. Channel swatches are repainted per look; fixed swatches (black,
greys, white, leather, lens, metal, lips, blush, mouth) never change. `mouth` (#2a1414, #895) is as dark as the eyes,
so the mouth reads on every skin tone; `lips` is the `open` mouth's tongue, and `white` the `teeth` mouth's teeth.

| Channel | Palette | Used for |
| --- | --- | --- |
| skin | `skin` (6 tones) | face, hands, bare arms and legs; `skin_shade` (stubble, freckles) is the same colour times `shade` |
| hair | `hair` (6) | hair, beard, brows |
| primary | `cloth` (16) | the main garment: jacket, shirt, vest |
| secondary | `cloth` | trousers, contrasting sleeves, hat |
| accent | `cloth` | trim, letters, scarf, bow tie, armband, sneakers |

Each channel also has a `_shade` swatch (the colour times `shade`, 0.75) for pockets, folds and soles, so one choice
gives two tones. The palettes, the swatch positions and `shade` are in `parts.json`; the game builds each look's
material by copying the atlas image and filling the channel swatches (16 px squares, sampled with nearest filtering),
one material per character for all its parts.

## Budget

The [style bible](style.md#budgets-proposed-for-the-web) gives a player 6k triangles and one material. Every part's
count and each preset's total are in `parts.json` (`tris`); the build fails if a preset, as built or worn by the
other character, goes over 6,000 near or 2,000 far.

| Measured | Tris |
| --- | --- |
| Presets | his 4,672 (Lifeguard) to 5,360 (Projectionist); hers 5,076 (Carhop) to 5,566 (Pit crew); before #895 his 4,490 to 5,080 and hers 4,748 to 5,428; the kit Soldier is 5,828 |
| Far presets | 1,407 (Greaser) to 1,715 (Usher); every preset worn by either character 1,787 at most (2,000 before #895, at the budget); the far ratio is solved over all of them (0.284) |
| Torso | 2,382 (shirt, tank) to 3,117 (vest, with the kit's shoulder pads); jacket 2,651, letterman 2,707, rolled 2,614: the tall collars' lining (about 330) and the bridged bare wrists (#895) |
| Head | his 824 (plain) and 922 (stubble, beard: the beard's edges are cut in); legs 500, feet 702 |
| Helmet | 1,136 (the kit's, eyes and brows moved to the head); original hats 88-292, hair 44-278, eyewear 220-436, scarf 152, bow tie 84, armband 92 |
| Hers | face 896 (Natural) and 968 (Freckles, Rosy); her torso and legs as many as his; bob 424, pin curls 448, bun 354 |
| The ladder's pieces (#1078), near / far | Usher's jacket 2,961 / 723, Coveralls 3,424 / 898 (with its legs), Overalls 844 / 217, Saddle shoes 1,038 / 274, Cinema glasses 120 / 120, Projectionist's visor 212 / 212, Press lanyard 228 / 228, Bolo tie 224 / 224 |

The build and `test_soldier_ladder_parts.gd` also hold each of the ladder's pieces to both budgets in the place of its
slot's part in every preset, on both bodies, with every mouth (worst 5,993 near, Pit crew in Usher's jacket with the
teeth; 1,994 far, the Projectionist on her in the Press lanyard); the far ratio stays solved over the presets alone, so
a new piece does not recut every far mesh. Other looks are not held to the budget: the heaviest possible look (vest,
helmet, a beard, goggles, scarf, armband, striped trousers) is over it: 7,231 (6,824 before #895).

Draw calls: one per visible part (5-7) with one shared material per character, near or far. The far level of detail
(#139) is a copy of every part in the same file: `SoldierLook.apply` shows the far mesh of each shown part with the
same material and swaps them by visibility ranges at `SoldierLook.FAR_FROM` (18 m, the zombies' distance).

The file holds every part of the catalogue (136 meshes after wave one), and a hidden mesh still costs a node and a mesh
instance. So `CharacterAssembler.dress` keeps what the look wears and frees the rest (`SoldierLook.trim`, 11 to 15 meshes
a soldier); `SoldierLook.apply` takes a part it needs back from a fresh copy of the file, about 2 ms, on a look change
only. A dressed soldier's mesh count does not grow with the wardrobe (`test_soldier_worn_meshes.gd`).

## The starting looks

Directions from a 1958 drive-in's staff and crowd, all original: his eight, then her four (#678), after his so a
preset's index never moves. Each player who joins takes the next preset not already in use
(`SoldierLook.default_preset(taken)`), so a group of up to eight starts out all different.

| Preset | Head, hair | Headwear | Torso | Legs, feet | Extras |
| --- | --- | --- | --- | --- | --- |
| Greaser | plain, pompadour | none | black jacket | cuffed denim, boots | - |
| Usher | plain, crew | pillbox | red jacket, gold trim | striped, shoes | bow tie |
| Mechanic | stubble, crew | none | rolled sleeves | trousers, boots | goggles |
| Lifeguard | plain, flattop | none | tank | shorts, sneakers | sunglasses |
| Soda jerk | plain, ponytail | papercap | shirt | trousers, shoes | bow tie |
| Ranger | beard, crew | ranger | olive shirt | tan trousers, boots | scarf |
| Letterman | plain, crew | ballcap | letterman | cuffed, sneakers | - |
| Projectionist | stubble, crew | none | rolled sleeves | trousers, shoes | glasses, armband |
| Carhop (her) | natural, bob | papercap | pink shirt | cuffed cream, sneakers | bow tie |
| Usherette (her) | natural, pin curls | pillbox | blue jacket, gold trim | striped, shoes | - |
| Pit crew (her) | freckles, bun | none | green rolled sleeves | trousers, boots | goggles |
| Pep squad (her) | rosy, ponytail | none | cherry letterman | cuffed, sneakers | - |

## Assembling in Godot

```gdscript
var model := SoldierLook.instantiate()            # every part hidden
var look := SoldierLook.default_preset(taken_ids)  # or a saved / sent look
SoldierLook.apply(model, look)                     # shows its parts, builds its material, returns tris
```

The model carries the same `CharacterArmature` and the same clips as the Soldier (`soldier.glb`), bone for bone, so
the player's AnimationTree and the weapon holds of [Animation](animation.md) work on it unchanged. How the parts were
made and what broke: [Soldier parts](../research/soldier-parts.md).

## Rebuilding

```sh
blender -b --factory-startup -P tools/blender/build_soldier_parts.py -- \
    --soldier <bundle>/models/PpLF4rt4ah.glb --out game/assets/characters/soldier_parts \
    --preview <scratch>/previews          # optional: one .glb per preset, for render_sheet.py
godot --headless --path game --import
godot --headless --path game -s res://tests/art/check_soldier_looks.gd   # LOOK lines, exit 0
```
