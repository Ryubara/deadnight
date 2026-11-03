# Soldier parts

How the modular Soldier was built from the kit Soldier (issue #100), and what we learned. The design (slots, the look
schema, the presets) is on [characters](../design/characters.md); the rules come from the
[style bible](../design/style.md).

## Building them

`tools/blender/build_soldier_parts.py` (pinned Blender 5.2.3, headless, about 30 s) runs `build_soldier.py`'s clean-up
and `soldier_clips.py`'s clips unchanged, then:

1. Tags every face of the kit `Body` mesh with its kit material, dominant bone, same-material island and centre, and
   sorts it into head, torso, legs or feet (bounds measured at rest, in kit metres).
2. Makes each part of those four slots as a copy of the whole body with the other regions' faces deleted and its
   own faces moved onto atlas swatches by rule (sleeves by bone, cuffs, collar, pouches by island and position).
3. Turns the kit's bone-parented helmet and shoulder pads into meshes skinned 100 % to their bone.
4. Builds the original pieces (hair, hats, eyewear, scarf, bow tie, armband, letter patch, elbow rolls) from cubes,
   cylinders and half spheres with a 20 mm one-segment chamfer, skinned 100 % to one bone.

## What the kit Soldier holds

| Part of the look | Where it is in the file |
| --- | --- |
| Hood (reads as short hair) | `Body`, a 388-face black island over the skull; its front below the eyes is the beard |
| Face | `Body`, an 80-face skin island, z 1.68-2.10 |
| Eyes and brows | the helmet mesh (`Head`): eyes two 96-face islands at z 1.75-1.89, brows small blocks at z 1.89-1.94 |
| Tall collar | `Body`, `Character_Main` faces weighted to `Head` (a funnel under the chin) |
| Sleeves | `Body`, one 192-face black island per arm: one long face per side from shoulder to elbow |
| Wrist cuffs, pouches | separate closed islands: the vest and arm are whole underneath |
| Trouser cuffs, belt | 24-face `Pants` rings at the ankle; a 46-face dark grey band at the waist |

## What broke

- **Pieces built in world space land at the feet, turned 90 degrees.** The cleaned armature keeps the import's X
  rotation (only its scale is applied), so a mesh parented to it needs `matrix_parent_inverse = arm.matrix_world
  .inverted()`.
- **Removing the helmet removed the eyes.** They live in the helmet mesh; they are split out and joined to every head.
- **Splitting a sleeve by face centre leaves a zigzag** (the long faces span the whole upper arm). Split by dominant
  bone (`UpperArm` against `LowerArm`) instead.
- **Deleting the wrist cuffs opens a gap** between the sleeve and the hand; colour them skin and pull them in to the
  arm instead.
- **A stripe painted by face centre zigzags** (#140): the trouser faces are long triangles, so colouring whole faces
  by where their centre falls leaves sawtooth teeth along both edges of the band. `cut_stripe` bisects the outer
  trouser faces of each leg with two planes 45 mm either side of the leg's outer face (`bmesh.ops.bisect_plane` on
  those faces only; the cut interpolates the skin weights) and paints what lies between: one straight band at every
  angle, 128 more triangles (Usher 4,716).
- **A box quiff reads as a cap** (#140): from the front a flat box on the crown, darker than the hair, looked like a
  hat. The pompadour is now two squashed spheres, a mass swept up from the hairline into the crown and a roll over
  the forehead, in the crown's `hair` swatch with `hair_shade` only on the faces that point down (`Piece.add(...,
  under=)`); 406 triangles (Greaser 4,632).
- **A decimated part counted one triangle more than Godot drew** (#139): a collapse leaves zero-area triangles and
  folded n-gons, which the glTF round trip drops or splits its own way, so `parts.json` disagreed with Godot by one.
  The far copy is triangulated in Blender and its zero-area faces removed before it is counted.
- **Small pieces do not survive a collapse** (#139): at the far ratio (about a third) the ball cap (254 triangles)
  turned to slivers and lost its peak. Pieces of 260 triangles or fewer keep every triangle in the far level; the
  kit-body parts and the big pieces carry the cut.

## The female Soldier (#678)

How her parts are made is on [characters](../design/characters.md#the-character) and in the kit's
[character variants](https://ryubara.github.io/gdstudio/blender/variants/#a-second-body-on-the-same-parts). What we
learned:

- **The file's clips are frozen.** `soldier_clips.py` grew after this file was last built (sprint, strike, downed,
  revive, aim-move clips, each shipped in its own file with the finger channels stripped). A rebuild exported them
  here too, and the controller only adds a clip a library lacks. `FILE_CLIPS` lists the 39 this file carries; they
  rebuilt sample for sample identical to the committed ones.
- **Her looks moved the far ratio** (0.333 to 0.299) of every part: the ratio is now solved over his eight looks, and
  every look of both is asserted against the far budget. Her face pieces are joined whole into her far heads (a
  collapse cut the lashes to slivers that the glTF round trip dropped, so Godot counted fewer triangles than
  `parts.json`).
- **The first bob sat inside the collar** in the grenade throw (26 of its vertices, against 17 for his ponytail): its
  ends at z 1.66 were r 0.32, inside the collar's top (r 0.36 at z 1.68). Flared to r 0.40 at z 1.72: 13.
- **A higher chest took the forearm of the sprint carries** (the shotgun carry laid it 14 mm deeper into her chest
  than his): the lobes moved down to z 1.145 and tightened.
- **The short-sleeved tops pushed the hands off the grips**, his as much as hers: the bare-arm push (25 mm along the
  normals of every `skin` face) took the hands too, 15-20 mm off every weapon's grip. Hands (faces of the finger
  bones) are no longer pushed, and `test_menu_grips.gd` holds every weapon in every top for both.
