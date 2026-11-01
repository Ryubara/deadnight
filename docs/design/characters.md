# Characters

Every player is the Soldier on one shared rig, dressed from swappable parts. A look is data: one part id per slot and
one palette index per colour channel. The customization screen (#101) edits that data; the game assembles it on the
model. Everything here is built by one script, `tools/blender/build_soldier_parts.py`, which also writes the catalog
`parts.json` beside the model, so this page, the file and the screen cannot drift.

## The files

| File | What it holds |
| --- | --- |
| `game/assets/characters/soldier_parts/soldier_parts.glb` | `CharacterArmature` (the Soldier's 43 bones), every clip of the Soldier (from `tools/blender/soldier_clips.py`, untouched) and one skinned mesh per part, all named `<slot>__<part>` |
| `game/assets/characters/soldier_parts/soldier_parts_atlas.png` | the one palette atlas every part uses: a row of colour-channel swatches the game repaints per look, and rows of fixed colours |
| `game/assets/characters/soldier_parts/parts.json` | the catalog: slots, parts, channels, palettes and the eight presets |
| `game/assets/characters/soldier_parts/soldier_look.gd` | `SoldierLook`: reads the catalog, applies a look to an instanced model, picks a default preset per player |

## A look

```json
{
  "parts": {
    "head": "plain", "hair": "pompadour", "headwear": "none", "torso": "jacket",
    "legs": "cuffed", "feet": "boots", "eyewear": "none", "neck": "none", "arm": "none"
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
- Headwear that covers the head (`hides_hair: true` in the catalog) hides the hair part; the look keeps its hair id.

## Slots

| Slot | Bone(s) | Parts |
| --- | --- | --- |
| head | Head, Neck | the face and neck: `plain`, `stubble`, `beard` |
| hair | Head | `none`, `crew`, `pompadour`, `flattop`, `ponytail` |
| headwear | Head | `none`, `helmet` (the kit Soldier's), `pillbox`, `ballcap`, `papercap`, `ranger` |
| torso | spine, arms, hands | `vest` (the kit Soldier's), `jacket`, `shirt`, `rolled`, `tank`, `letterman` |
| legs | hips, legs | `trousers`, `cuffed`, `shorts`, `striped` |
| feet | feet | `boots`, `sneakers`, `shoes` |
| eyewear | Head | `none`, `sunglasses`, `glasses`, `goggles` |
| neck | Neck, Torso | `none`, `scarf`, `bowtie` |
| arm | UpperArm.L | `none`, `armband` |

Names: slot and part ids are lower-case ASCII words; the mesh node is `<slot>__<part>` (two underscores), so
`torso__letterman`. A new part is a new entry in the build script's tables and a rebuild; ids are never renamed once
shipped (saved looks refer to them).

## Colour channels

Faces of every part sit on one swatch of the atlas. Channel swatches are repainted per look; fixed swatches (black,
greys, white, leather, lens, metal) never change.

| Channel | Palette | Used for |
| --- | --- | --- |
| skin | `skin` (6 tones) | face, hands, bare arms and legs; `skin_shade` (stubble, lips) is the same colour times `shade` |
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
count and each preset's total are in `parts.json` (`tris`); the build fails if a preset goes over 6,000.

| Measured | Tris |
| --- | --- |
| Presets | 4,490 (Lifeguard) to 5,080 (Projectionist); the kit Soldier is 5,828 |
| Torso | 2,288 (jacket, shirt, tank) to 2,754 (vest, with the kit's shoulder pads); letterman 2,344, rolled 2,520 |
| Head, legs, feet | 736, 500, 702 (the kit Soldier's own faces, recoloured) |
| Helmet | 1,136 (the kit's, eyes and brows moved to the head); original hats 88-292, hair 44-278, eyewear 220-436, scarf 152, bow tie 84, armband 92 |

Draw calls: one per visible part (5-7) with one shared material per character. No far level of detail yet: the
style bible's 2k far budget is a follow-up.

## The eight starting looks

Directions from a 1958 drive-in's staff and crowd, all original. Each player who joins takes the next preset not
already in use (`SoldierLook.default_preset(taken)`), so a group of up to eight starts out all different.

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
