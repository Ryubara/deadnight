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

The mouth is kept whole in the far level of detail (it is one of the small pieces that a collapse would cut to
slivers).

## The design

![Three mouths on four faces](character-faces-designs.png)

*Left to right: `smile` (chosen), `line`, `grin`; each the face up close and the same face drawn at 64 px and scaled
up (a teammate at about 15 m on a phone). Rows: the Greaser (him, peach), the Letterman worn by her (cocoa skin), the
Pit crew (her, porcelain, freckles), the Ranger (him, beard). Rendered by `tools/blender/render_soldier_heads.py`
with back faces culled.*

- **Head:** one closed, smooth shape: the outside of the kit hood (the convex hull of its hood, face panel and rim,
  relaxed twice and kept on the hull under the jaw so the tall collars still close on it), so every hat, hair piece
  and pair of glasses sits where it did. 216 quads before the hairline cuts.
- **Hair:** the scalp is painted `hair` above a hairline cut into the mesh: level across the forehead at z 2.03 (kit
  metres), a step at the temple (y -0.06), then falling 0.5 m a metre to the nape. Hair pieces sit on top as before.
- **Neck:** a 12-sided tube, r 0.125, from inside the head to inside the shoulders (Head above z 1.57, Neck below 1.46,
  blended between).
- **Eyes and brows:** the kit's, moved forward until each eye stands 6 mm out of the new face; hers keep the lashes and
  arched brows of #678.
- **Mouth (chosen, `smile`):** an open half-moon, 0.135 m wide for him and 0.115 m for her, 0.056 m deep, flat on top,
  its middle at z 1.672, in a new fixed swatch `mouth` (#2a1414, as dark as the eyes so it reads on every skin tone),
  standing 4 mm out of the face. It stays a clear dark mark at 64 px.
- **Beard and stubble:** the jaw below z 1.74 and the sideburns (|x| > 0.27) up to the hairline, in `hair` or
  `skin_shade`, cut straight into the head; nothing is modelled, so no line shows on a clean-shaven face.

### The two set aside

- **`line`**, a closed mouth: a bar 0.026 m tall whose corners turn up 12 mm. Calm and readable at the menu, but at
  64 px it is one or two pixels tall and often gone.
- **`grin`**, a wider, shallower half-moon (0.04 m deep). Reads at a distance, but looks the same as the smile up close
  and a little flat.

Either is one argument away: `build_soldier_parts.py --mouth line` (or `grin`) builds the same parts with the other
mouth, and `MOUTH_STYLE` makes it the shipped one.

## Why the first face read as a mask

The kit Soldier's head is a balaclava: an 80-face skin panel set back in a hood, with a raised 52-face rim round the
opening. The first heads painted the rim and the hood's front skin coloured, but the rim was still modelled, and its
lit edges drew a line from the chin up both cheeks to the temples. Her mouth was a 0.10 x 0.03 box in `lips`, a red
dash. Recolouring a mesh does not change its shape: a face is designed and modelled, then checked lit, close and far.
