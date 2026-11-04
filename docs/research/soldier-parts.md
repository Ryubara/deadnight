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
  every look of both is asserted against the far budget (every mouth too, since #1061: 0.269). Her face pieces are
  joined whole into her far heads (a collapse cut the lashes to slivers that the glTF round trip dropped, so Godot
  counted fewer triangles than `parts.json`).
- **The first bob sat inside the collar** in the grenade throw (26 of its vertices, against 17 for his ponytail): its
  ends at z 1.66 were r 0.32, inside the collar's top (r 0.36 at z 1.68). Flared to r 0.40 at z 1.72: 13.
- **A higher chest took the forearm of the sprint carries** (the shotgun carry laid it 14 mm deeper into her chest
  than his): the lobes moved down to z 1.145 and tightened.
- **The short-sleeved tops pushed the hands off the grips**, his as much as hers: the bare-arm push (25 mm along the
  normals of every `skin` face) took the hands too, 15-20 mm off every weapon's grip. Hands (faces of the finger
  bones) are no longer pushed, and `test_menu_grips.gd` holds every weapon in every top for both.

## Fit: no holes, no mask, no clipping (#895)

The maintainer saw the Pit crew (her, green rolled sleeves) in the menu with a see-through neck, a line round the face
like a mask, a red dash for a mouth and arms through each other. The causes and what changed:

- **The kit has no neck.** Its head is a hood open underneath (a 32-edge ring, z 1.53-1.68, r 0.34), closed only by the
  vest's tall collar, whose top is the same ring. The open-necked tops folded that collar down and left the ring open:
  Godot culls back faces, so from behind the eye looked through the head (the mouth showed from the back). Every
  earlier render was Workbench without back-face culling, which draws the inside of a shell as if it were outside.
  Now each head is one closed shape with its own neck ([Character faces](character-faces.md)); the trunk's own neck
  hole is capped, facing up (`holes_fill` faced it down into the trunk).
- **The open collars** lay the kit collar on a slope from the shoulders to a band just inside the neck, on the Neck
  bone (on Head it swung through the shoulders); its lip and front flap, inside out once laid down, are dropped.
- **Every collar has an inside**: a reversed copy of its faces (`primary_shade`, the tank's in skin). A ray between a
  tall collar and the jaw, or under an open collar, looked into the collar and out through it. The lining is about
  330 triangles on the tall collars; lining only their top half opened the chest-level rays again.
- **The bare-arm push cracked the arms.** The kit body is split at every seam, so a vertex is several vertices in one
  place; pushed along their own normals they parted all along the forearms and shins. The push moves every copy alike
  (`push_faces`) and tapers to nothing at the wrist and the ankle (the shorts' shins pulled away from the shoe tops).
- **Bare wrists** dropped the kit's three cuff rings (pulled into the arm they bared the open end of the sleeve tube
  and the hand's open wrist) and join the two openings with one band of skin (`bridge_wrist`).
- **Clipping**: the seat armband sat at the middle of the upper arm and sank up to 6 cm into the chest in the menu's
  pistol hold: now 0.65 along the arm. The bow tie and scarf follow Neck, not Head. The long sleeves' forearms are 20 mm
  slimmer (the right forearm crossed the jacket's chest 46 mm deep in the long guns' carried hold; now 30-39 mm).
- **A far triangle dropped by the export** (the letterman's far mesh counted 759, Godot 758): the far copy also drops
  faces with two corners under 0.01 mm apart, under 1e-8 m² or repeating another face.

### The checks

| Check | What it does | Where |
| --- | --- | --- |
| Combination sweep | Every head x top x neckwear, top x trousers, trousers x shoes, top x armwear on both bodies, and every part alone: rays from 60 directions over each junction (neck, waist, ankles, wrists, shoulders); fails where the first face a ray meets faces away and nothing facing it lies within 6 cm behind. A closed and an opened ball check the probe itself | `tests/character/test_soldier_watertight.gd`, `tests/art/body_fit.gd` (`BodyFit.see_through`) |
| Clip sampler | Every clip of the player's library (the parts file's and the player's own files', as `PlayerAnimation` loads them), 8 frames each, on her in rolled sleeves and him in a jacket: forearm and hand vertices inside the trunk, head, legs or the other arm, head pieces inside the trunk, armbands inside the trunk, deeper than 3 cm | `tests/character/test_soldier_clip_fit.gd`, `tests/art/clip_fit.gd` |
| Menu pose | The menu soldier with every weapon (`MenuHero`, read at `skeleton_updated` with the hand pose on) | the same suite |
| Turntables | 360 degrees, the menu pose, red dots where the eye sees through | `tests/captures/soldier_turntable.tscn --probe` |
| Heads | Close-ups with back faces culled, and drawn small | `tools/blender/render_soldier_heads.py` |

On main the sweep failed 133 combinations (the Pit crew's neck: 48 rays); now none. The probes are physics rays
against `ConcavePolygonShape3D` pairs (both sides, front only) on layers no game body uses; a shape's faces front the
way the mesh draws them. New faces reach the broadphase only after two physics steps (with one, a sample met the
last pose's surface), so the suites step physics at 480 Hz. A clip that does not key the fingers keeps whatever the
last clip left: the sampler resets the bones before each sample. The sampler loads the player's clip files by name
(`ClipFit.add_player_clips`): a new clip file is added there in the same change, or the clip is measured only when an
earlier suite has put it in the library every model shares (the perk drink, #912, passed alone and failed in CI's run).

The arms in the clips were not all clean: the dual pistols' hands through each other in the equip and the quick melee,
the revive's hands through each other, the downed hand through the thigh and the crawl's knee through it, the strikes'
free hand in the knee (up to 14 cm, 22 clips). #939 reworked them (docs/design/animation.md, the clips' sections):
no clip puts a forearm or hand into the body now, nothing may be recorded for the arms, and the test samples eight
frames a clip (four missed a windup). The night's own poses, after the hand IK, are measured by
`tests/captures/clip_arms_tour.tscn -- --measure`: the clips' beats are at 3 cm or under but for the start of the
crawl and his SMG carry (31-38 mm); the IK's reload and long-gun hold are not (#987). Only the armbands
(33-50 mm) and the menu's holds are recorded. The menu's long-gun holds keep
a long sleeve's right forearm 30-39 mm into the chest (recorded, at most 4 cm); her rolled sleeves (the maintainer's
look) are clean with every weapon.

## The arm's length (#978)

The maintainer saw the female Soldier's arms as too long ("maybe double check it for males as well"). Measured
(`tools/blender/measure_arms.py`, kit metres; `game/tests/art/measure_arms.tscn` for the menu's holds, game metres):

- Nothing stretched an arm. The parts skeleton is the kit's bone for bone (the Soldier, Hazmat and Enemy share the
  joints), no clip of any Soldier file keys a position or a scale on an arm or hand bone (only `Shoulder.L/R`, 19 mm
  at most in Punch), and in every hold of the menu the upper arm and forearm are 0.310 and 0.352, as at rest: the
  hand IK only turns bones.
- Hers was not longer than his: every look of both characters wore the kit Soldier's arm, upper arm 0.388, forearm
  0.440, hand 0.384, 1.212 in all, 0.547 of the 2.216 height (the kit's span is 1.23 times its height), the forearm
  longer than the upper arm; standing, the fingertips hung at 0.165 of the height, below the knees, 0.45 under the
  crotch. It read longest on her: her body is his with the waist 13 % narrower and his shoulders, arms and hands, and
  two of her four presets wear bare-armed tops whose skin is pushed 25 mm in, a thin skin-coloured arm from the
  sleeve to a fingertip at the knee.
- The long guns were held at that arm's full reach: the left arm used 0.90-0.98 of its length on the fore-ends at the
  low ready (and fell 8-13 mm short of the M249's, the PPSh's and the pump's at 40 degrees down).

What changed: the forearm is 0.80 of the kit's (0.352; the arm 1.124, 0.507 of the height; the fingertips at 0.198,
at the knee), a two-handed hold's elbows bend further out, and the weapon slides back along its barrel when the
fore-end is out of the left arm's reach ([How a gun is held](../design/weapon-hold.md#how-a-gun-is-held)). Tried
first at run time (`measure_arms.tscn -- --forearm=0.88 --stance=10 --pitch=-0.7`, the skeleton's rest shortened in
the probe): a forearm of 0.88 needed 10 degrees of stance at the low ready, 0.80 needed 20 (or 10 and the slide);
looking down 57 degrees no stance reached without the slide. More stance put the seat's armband 2-3 cm deeper into
the chest when firing the pump and the M249 (night probe, 66-83 mm against 45-49), so the stances stayed as they
were and the slide does it.

In the night (`clip_arms_tour.tscn -- --measure`, worst per beat, mm, his jacket / her rolled sleeves), against #939's
build of the same clips with the kit's forearm: reload left 120 / 120 (123 / 129), reload right 90 / 90 (90 / 90),
fire right 45 / 53 (60 / 57), aim and hold right none / none (40 and 37 / none), fire armbands none / 40 (48 / 45),
sprint armbands 41 / 45 (56 / 66), sprint arms none / none (32 and 38 / none), reload armbands none / none (74 / 71),
crawl's blend-in right hand 74 / 65 (65 / 67); one vertex at 30-31 in the grenade's cook and her pistol strike (30 is
the tolerance).

What broke on the way:

- The bare tops' wrists opened and their cuff rings came back as bracelets: the parts build picks the cuff and the
  wrist seam by their place along the kit's arm (`|x|` 0.74-0.95 at rest), and the seam had moved 7 cm in. The places
  are now written in the kit's numbers and read through `soldier_arms.along` (`test_soldier_watertight.gd` failed
  first, 24 combinations).
- The sprint carry's left hand spun 77-86 degrees in one tick of the puppet's sprint start: the carries' left wrist was
  turned 175-180 degrees off its turn in the gun hold, and the tree's blend between the two takes either way round
  near half a turn; main's 178 had been on the lucky side. Each carry now rolls its left forearm (one roll for the
  loop, 45-60 degrees) so the wrist stays within 150 degrees (`CARRY_WRIST_MAX` in `tools/blender/soldier_clips.py`);
  `test_sprint_start_blend.gd` failed first.
- The seat's armband on the right upper arm sank 8 mm deeper in her Sprint_Rifle (`test_soldier_clip_fit.gd`: 44 mm,
  recorded 36): the carry's right elbow now bends out twice as far as the IK's (`SPRINT_RIGHT_OUT`).
