# Zombie variants

How the zombie variants were built from the kit zombie (issue #40), and what we learned. The design (which variants,
the animation set, playback variety) is on [zombies](../design/zombies.md); the rules come from the
[style bible](../design/style.md).

## Building them

`tools/blender/build_zombies.py` (pinned Blender 5.2.3, headless; how to run it is at the top of the file) builds all
seven variants from `refs/polypizza/VlXjG0N8Eg/model.glb` in about 15 s. The outputs are derived from a third-party
model; the maintainer approved committing them (issue #90), so they live in `game/assets/characters/zombies/` with
their licence entry, built with `--out game/assets/characters/zombies`. The script rebuilds them byte for byte.

In Godot the seven files share one material: each `.glb.import` maps the glTF material `Atlas` to the external
`zombie_atlas.tres` (which uses the one `zombie_atlas.png`) and discards the embedded copy of the atlas
(`gltf/embedded_image_handling=0`). Left at the defaults, the import extracts seven identical atlas PNGs and makes
seven materials. Remap again if a rebuild ever renames the material.

Per variant, in order:

1. **Clean** with the kit's rig-sharing recipe (kit `docs/blender/rig-sharing.md`): TEMPERANCE import, armature as
   the root, the 100x scale applied with the location keys scaled to match, one clip per name, pose bones cleared with
   `pose_position` left at `POSE`.
2. **Fill missing arm channels** (below).
3. **Join the eyelid mesh into the body**: one mesh per zombie (the crowds spike measured the second mesh at 30 % of
   the browser frame with 80 zombies).
4. **Remove parts**: faces whose vertices follow the named bones by more than half their weight are deleted.
5. **Push** vertices along their normals, scaled by their weight to a group of bones (brute +30-50 mm on torso and
   arms, runner -12 mm on limbs, at kit scale).
6. **Accessories**: a chunky 10-sided pillbox cap with a one-segment chamfer, skinned 100 % to `Head`, joined into the
   body (76 tris).
7. **Recolour**: faces move from kit swatches to new ones; skin faces under the torso and arm bones become a painted
   top.
8. **Height** is the armature object's scale; **decimate** (collapse) a copy to 4,000 and another to 1,500 tris.
9. **Export** one glb: the skeleton, 16 clips and both meshes.

## Measured

| Variant | Full tris | Gameplay | Far | Faces removed | Height |
| --- | ---: | ---: | ---: | ---: | ---: |
| Walker | 7,822 | 4,000 | 1,500 | | 1.00 |
| Greaser | 7,822 | 4,000 | 1,500 | | 1.02 |
| Usher | 7,898 | 3,999 | 1,500 | | 0.97 |
| Farmhand | 7,107 | 3,999 | 1,500 | 715 (left forearm and hand) | 1.00 |
| Runner | 7,822 | 3,999 | 1,500 | | 1.07 |
| Brute | 7,822 | 3,999 | 1,500 | | 1.18 |
| Crawler | 6,579 | 3,999 | 1,500 | 1,243 (both lower legs and feet) | 1.00 |

Each file is about 1.47 MB, nearly all of it the 16 sampled clips; the atlas is 8 KB. Godot 4.7.2 imports all seven
with no error or warning, each to `CharacterArmature/Skeleton3D` with 50 bones and the height on the `CharacterArmature`
node; the walker's `Walk`, put in one AnimationLibrary, plays on every variant (checked headless: the legs move on all
seven).

## What worked

- **Height as a node scale, never baked into the bones.** Every variant keeps the kit zombie's rest pose, so clips
  share with no rebasing of position keys (the kit's Godot rig-sharing page needs it only when rest poses differ).
  The glTF keeps the armature object's scale as the node's scale and Godot puts it on the `CharacterArmature` node.
- **Collapse decimation keeps the palette.** Every face of the kit zombie sits on one atlas swatch; collapsing to 51 %
  and to 19 % of the triangles left every colour block in place (contact sheets on the pull request). The far level
  is faceted on the head and hands, which does not show past 15 m.
- **Painted tops cost nothing.** Recolouring skin faces whose vertices follow `Torso`, `Abdomen`, `Shoulder` (vest),
  plus `UpperArm` (short sleeves) and `LowerArm` (long sleeves) gives clean collar and sleeve lines, because the kit
  mesh already has edge loops at the joints.
- **The body is closed shells per limb.** Removing the forearm or the lower legs left no open edge to cap: the
  wound-coloured fill the script makes for a new hole created no faces on either variant. It is kept for meshes that
  need it.
- **New swatches in the atlas's empty corner.** The kit atlas uses 11 swatches in one row; 26 new 16 px swatches
  (two rows from x = 256 px at the bottom) hold every variant's colours, so all variants share one atlas and one
  material.

## What broke

- **The kit Idle, Yes and No have no channels for the shoulders and arms.** In Blender the arms keep whatever pose the
  previous clip left; a sampled glTF export (the recipe forces sampling) writes the rest pose there, so the exported
  Idle stood in a T-pose. The build now gives every clip a held channel, from Walk's first frame, for each bone Walk
  turns and the clip does not (Idle gained 27 bones, HitReact 23, Death 18).
- **The style bible's zombie Idle height is the Crawl pose.** `measure_kit.py` and `render_sheet.py` show a clip by
  making it active over the import's own active action (Crawl). Bones the Idle does not key keep Crawl's pose, so the
  "Idle height 1.06 m" and the hunched kit zombie on the sheets are part crawl. With the fix above the walker's Idle
  stands 1.25 m (kit scale). The style bible row needs a re-measure with the arm fix.
- **A part-recolour by palette is not enough.** The kit swatch at column 8 (a light bone colour) is both the teeth and
  the belt buckle; recolouring it as "shirt" painted the teeth blue. Recolour by swatch only for colours that mean one
  thing (skin, trousers, belt), and by bone weights for clothing.
- **Git Bash only converts paths at the start of an argument.** `--model Title=/c/...` reached Blender unconverted
  ("Please select a file"); `C:/...` paths work everywhere.

## Next

- Measure each clip's ground speed (stride per cycle) so play speed can follow move speed (zombies page).
- Author the seven new clips on the kit rig.
- Import clips from one file only: the six other variants can skip their animations at import and take the walker's
  library, saving about 1.3 MB each in the web build (to measure).
