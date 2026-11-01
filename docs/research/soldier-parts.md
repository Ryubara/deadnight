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
