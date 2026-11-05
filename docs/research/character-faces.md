# Character faces

How Deadnight's survivors' faces are drawn so they read on a phone at the night's distances, and why the first face
looked like a mask (#895). The parts and their build are on [Soldier parts](soldier-parts.md); the look schema is on
[Characters](../design/characters.md).

## What other stylised low-poly games do

Studied for design only; nothing is copied. These are the habits of chunky, low-poly and chibi characters made to be
seen small (party games, mobile shooters, the Quaternius-style kits this game starts from):

- **The face is the whole front of the head.** The jaw and the cheeks are the head's own silhouette; there is no line
  inside the face from the chin to the ears. A line there reads as a strap, a mask or a helmet's opening.
- **Few features, big and dark.** Two eyes, brows, a mouth; sometimes no nose. Each is a solid shape several pixels
  across at the distance the player sees teammates, in a colour much darker than any skin tone, so it reads in the dark
  and on every skin. Thin lines and pale colours (a red dash on skin) vanish first.
- **The mouth has height.** An open mouth (a half-moon or a "D") stays a dot at a distance; a closed line of the same
  width disappears. A mouth carries the mood: a small open smile reads friendly, a flat bar reads determined.
- **Hair is a mass, not a texture.** Short hair is the scalp painted a colour with one clean hairline; longer cuts are
  separate shapes on top.
- **One face, many people.** Skin, hair colour, brows and hair pieces make the variety; the face's construction stays
  the same, so every hat and pair of glasses fits every head.

## The numbers that set the sizes

| Where | Head (0.54 m in the game) on a 1080 px tall screen | Mouth (0.108 x 0.045 m in the game, his) |
| --- | --- | --- |
| Menu, Loadout tab (measured on the capture) | about 260 px | about 50 x 20 px |
| Own player, shoulder camera (about 3 m, FOV 60) | about 170 px | about 34 x 14 px |
| A teammate at 10 m | about 50 px | about 10 x 4 px |
| The far level of detail starts (18 m) | about 28 px | about 6 x 2 px |

The mouths are whole in the far level of detail (they are small pieces that a collapse would cut to
slivers).

## The design

![Eight mouths on four faces](character-faces-designs.png)

*Rows, top to bottom: `smile` (the default), `line`, `grin`, `open`, `smirk`, `oh`, `frown`, `teeth`. Columns, four pairs:
the Greaser (him, peach), the Letterman worn by her (cocoa skin), the Pit crew (her, porcelain, freckles), the Ranger
(him, beard); each the face up close and the same face drawn at 64 px and scaled up (a teammate at about 15 m on a
phone). Rendered by `tools/blender/render_soldier_heads.py` with back faces culled.*

- **Head:** one closed, smooth shape: the outside of the kit hood (the convex hull of its hood, face panel and rim,
  relaxed twice and kept on the hull under the jaw so the tall collars still close on it), so every hat, hair piece
  and pair of glasses sits where it did. 216 quads before the hairline cuts.
- **Hair:** the scalp is painted `hair` above a hairline cut into the mesh: level across the forehead at z 2.03 (kit
  metres), a step at the temple (y -0.06), then falling 0.5 m a metre to the nape. Hair pieces sit on top as before.
- **Neck:** a 12-sided tube, r 0.125, from inside the head to inside the shoulders (Head above z 1.57, Neck below 1.46,
  blended between).
- **Eyes and brows:** the kit's, moved forward until each eye stands 6 mm out of the new face; hers keep the lashes and
  arched brows of #678.
- **Beard and stubble:** the jaw below z 1.74 and the sideburns (|x| > 0.27) up to the hairline, in `hair` or
  `skin_shade`, cut straight into the head; nothing is modelled, so no line shows on a clean-shaven face.

## The mouths

A mouth is a part of its own (#1061): the `mouth` slot, `mouth__<id>` and hers `mouth__<id>__female`, one mesh for every
head of a character (the heads share one shape, and a test holds each mouth on each). They are free to everyone: nothing
gates them, and the maintainer's words are the rule ("Customizing your character's features shouldn't be locked behind
progression"). Each is built from a shape seen from the front, in the fixed swatch `mouth` (#2a1414, as dark as the eyes
so it reads on every skin tone), its middle at z 1.672, standing 4 mm out of the face and 12 mm into it. His full width
is 0.135 m and hers 0.115 m.

| Id | Row reads | Shape, in kit metres | At 64 px |
| --- | --- | --- | --- |
| `smile` | Smile | an open half-moon 0.056 deep, flat on top. The shipped mouth of #895 and the default, so every look saved before this one keeps its face | a clear dark mark |
| `line` | Calm | a bar 0.038 tall whose corners turn up 12 mm | a short dash. The first `line` was 0.026 tall and vanished |
| `grin` | Grin | a crescent 1.22 times the full width (0.165 m), points up, 0.05 deep in the middle | a dark curve, the widest mouth |
| `open` | Open | a half-moon 0.075 deep with a tongue in `lips` low in it, its top 25 mm over the smile's | a big dark block with a warm spot |
| `smirk` | Smirk | a lopsided bar: 0.024 tall and level at one corner, 0.038 tall and 40 mm higher at the other | a slanted dash |
| `oh` | Surprised | an oval 0.068 wide, 0.084 tall, 12 mm over the others' middle | a dot, the smallest mark, still dark and tall |
| `frown` | Frown | a bar 0.038 tall, flat across the middle, the corners falling 26 mm | a flat dash with its ends down |
| `teeth` | Teeth | a dark rounded bar 0.058 tall with four teeth in `white` | a pale bar in a dark rim |

- **Height:** each dark shape is at least 30 mm tall at its tallest (a thin line is gone at 64 px, as the first `line`
  showed), and none is wider than about 0.17 m, so no line runs towards the ears (the mask of #895).
- **On the beard:** `beard` paints the jaw in `hair`, so on dark hair the dark mouths lose their edge, as the smile
  always has there. `open` and `teeth` hold at a teammate's distance, the others show close up and go at 10 m. That
  comes with the beard: no mouth gets a lip line to fight it.
- **Above the jaw:** the head turns under the jaw at a crease at z 1.637, and a mouth's front cannot follow it (a chord
  over a crease sinks however often it is cut). No mouth goes below z 1.64 (`MOUTH_LOW`, asserted in the build), so the
  tall ones stand higher.
- **Far away:** a mouth has no `__far` mesh. It was already one of the small pieces kept whole in the far level of
  detail, and sixteen copies would be sixteen more hidden nodes on every body; one mesh shows at every distance
  (`WHOLE_FAR` in the build, `SoldierLook.far_triangles` counts it). 68 to 144 triangles on the character's budget; the
heaviest look of every preset, on both bodies, with every mouth is 5 646 near and 1 792 far.
- **A decal follows the face.** A front flat between its outline's points sank behind the head's bulge on a wide or tall
  mouth and skin showed through it: `hug_face` cuts it wherever it comes within 1.5 mm of sinking and lifts the new
  corners onto the surface. The front is smooth-shaded: flat, the lamps picked out each triangle of a dark shape.

To try another mouth: add it to `SLOTS["mouth"]` (at the end, a part is an index on the wire) and to `mouth_layers`,
then `build_soldier_parts.py --preview <folder> --preview-mouths greaser,letterman,pit_crew,ranger` writes every mouth
on those four for `render_soldier_heads.py --across 4`. `game/tests/captures/mouth_tour.tscn` shows each in the Loadout
tab and in a night.

## Why the first face read as a mask

The kit Soldier's head is a balaclava: an 80-face skin panel set back in a hood, with a raised 52-face rim round the
opening. The first heads painted the rim and the hood's front skin coloured, but the rim was still modelled, and its
lit edges drew a line from the chin up both cheeks to the temples. Her mouth was a 0.10 x 0.03 box in `lips`, a red
dash. Recolouring a mesh does not change its shape: a face is designed and modelled, then checked lit, close and far.
