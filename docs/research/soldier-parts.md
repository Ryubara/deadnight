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
crawl and his SMG carry (31-38 mm), and #987 brought the IK's reload and long-gun hold there too
([the numbers](weapon-hold-ik.md#the-reload-and-the-shouldered-hold-out-of-the-body-987)), the menu's holds with them.
The rest of what #987 left over (the crawl's blend-in, the melee swing's and sprint's armband, the pistol
sprint and strike, the grenade's cook) was done in #1282
([the numbers](weapon-hold-ik.md#the-poses-987-left-over-the-tolerance-1282)):
the whole tour is under 3 cm on both looks, and `test_pose_arm_fit.gd` holds those poses. Only the armbands
(33-36 mm) are recorded.

A sampled pose stays where it was sampled (#1143): `ClipFit.pose` pauses the player after the seek. A playing
clip went on with the real time of the physics frames `prepare_sets` awaits, so `BodyFit.bone_point` (the live
skeleton) was a later pose than the surface read before the wait: the swing skirt's `10 Run leg` read 0.142-0.144 m
on the pull requests and 0.1348 m every time once held (the recorded 0.137 stands).

## The ladder's pieces (#1078)

The fifteen wearables of [the ladder](../design/progression.md#wardrobe-costumes-and-the-locks), in two waves, in
`tools/blender/soldier_ladder.py`, appended to their slots (a part is an index on the wire). All are original ideas
from a drive-in's staff and a B-movie crowd. Wave one: a bellhop's jacket, card 3-D glasses, a booth operator's eyeshade,
a press pass, a string tie, bib overalls, a mechanic's one-piece and two-tone oxfords. Wave two is
[below](#wave-two).

| Piece | How it is made | Where it fits |
| --- | --- | --- |
| Usher's jacket | the jacket's rule, a plastron cut down the front (x +-0.095) in `secondary`, six buttons, a braid on each sleeve, a half belt at the back for the shoulder camera | buttons at z 1.13-1.31: lower, her chest's underside turned them away |
| Coveralls | the open collar on long sleeves, the kit's cuffs kept; the trunk and **the legs in one part** (`hides_legs`); a zip cut in, two pockets, a name patch and a crew oval lying along the back's slope | ankles swept against every shoe |
| Overalls | the trousers' rule plus a waist over the top's hem, a bib, straps and brass clips, in `legs` | every top: on a tall collar the straps pass under its foot; the vest's pouches and pads are worn over the bib |
| Saddle shoes | the kit's feet; the sock's line (z 0.135) and the saddle (y -0.112 to -0.016) cut in, white laces | every pair of trousers |
| Cinema glasses | a card frame with a nose notch and red and cyan lenses (two new fixed swatches) | where the glasses sit: y `FRONT` - 0.035 |
| Projectionist's visor | a band (r 0.40, z 2.05) above the brows, a peak angled down, a reel pin; it does not hide the hair | clears every cut; goggles rest on its peak (their lenses cross it, as they sink into the ball cap on main; no test measures head pieces against each other) |
| Press lanyard, Bolo tie | a ring round the collar's foot; a card or a slide with two ends hanging at y -0.255; her own variant | the ring inside the vest's pads, what hangs in front of its pouches |

Numbers they rest on (kit metres at rest, front -Y):

| Measured | Value |
| --- | --- |
| Trunk under every top | front y -0.19 (waist) to -0.16 (chest), back y 0.18-0.22, x +-0.30 at z 1.0; her chest y -0.28 at x 0.1, z 1.16 |
| The collars' foot | at z 1.46 the tall and the open collars both reach r 0.22-0.235 at the front and 0.15-0.16 at the back: one ring fits both |
| The tall collar's flare | r 0.33 at z 1.6, over the shoulder: a ray down at x 0.33 lands on it, not on the sleeve (top z 1.51) |
| Vest | pouches stand to y -0.233 (z 1.11-1.38, x +-0.24), pads from x 0.205 up to z 1.59 |
| The top's hem | down to z 0.873 at the centre, 0.94 at the sides, y -0.198: below it a ray meets only the trousers |
| The foot | y -0.246 to 0.094, up to z 0.195 at the ankle |

What broke on the way:

- **The straps and the bib stayed put and the top came through them.** Weights taken from the "trunk" by the bone that
  leads each face skipped the chest's edges and the shoulders, which are weighted to the arms and move when the arms
  hang. `borrow_skin` now picks faces by place and interpolates over the face it lands on (`poly_3d_calc`).
- **A strap at its centre line sank under the humps beside it**: each point of a sheet rests on the highest of the
  surface under its whole footprint (`Surface.front_over`, the straps' three rays across).
- **The hem hung out under the waist**: each row of the waist takes the widest within its reach.
- **Two prisms were inside out** and looked right: the far wall of a thin closed shape shows through its culled front
  (the glasses' frame; the coveralls' oval, a half-moon). `test_every_part_is_closed_on_both_bodies` caught both;
  `plate` takes an outline that is always counter-clockwise from the front.
- **A braid on one bone floated off the sleeve** as the arm hung: the shoulder's faces close up. It borrows the sleeve's
  weights, from the sleeve only (`on_sleeve`), and the ray that seats it starts under the collar's flare.
- **The ladder's looks would have recut every far mesh** (ratio 0.284 to 0.235): the ratio stays solved over the
  presets, and each new piece is asserted against the far budget instead.
- **The mouths (#1088) took three pieces over the budget**: held with every mouth, the teeth add 74 triangles on her and
  76 on him over the smile, which took Pit crew in the Overalls, Usher's jacket and the Saddle shoes to 6,066, 6,057 and
  6,006, and her Projectionist in the lanyard to 2,006 far. They lost the half belt's two buttons (and the belt its
  outer third, which stood off the curving back), a bib column and row, two strap stops, a lace bar, a line on the
  card and two facets on the bolo's tips; nothing that sets how they sit.

The arms (`test_the_ladders_clothes_keep_the_arms_out_of_the_body`, every clip at eight frames): the bib takes no arm
past the tolerance on either body. One vertex of the left forearm goes 40 mm in at one frame of `Strafe_Left` in the
Coveralls and in Usher's jacket on her; her plain jacket does the same (40.49 mm): the kit's long sleeve, recorded
under `ladder`. No test measures a top's folds against the bib worn over it: that was looked at (Idle, Run_Gun and
Reload_Rifle on both bodies).

The pieces are free like every other until the wardrobe grid (#1065) reads their gates; each has its row in
`gameplay/progression/unlocks.json`, `available` since its art landed, named in the table's own words
(`test_every_piece_is_earned_at_its_level` holds which row is which part).

### Wave two

Roller skates (38), Swing skirt (40), Creature tee (44), Rubber boots (46), Creature mask (48), Film-strip scarf (50) and
Varsity gold (52). The tee and the mask share one creature, invented here: a wide toad's skull, bulging eyes, a jagged
grin and a crest of fins; it borrows from no film.

| Piece | How it is made | Where it fits |
| --- | --- | --- |
| Roller skates | the kit's foot with its sole sheared up 8 cm, dying out at the ankle (z 0.19); a metal plate, four 8-sided wheels half outside the sole, a toe stop | the ankle is every shoe's, so every trouser leg meets it as it meets the boots |
| Rubber boots | the kit's ankle cut off (z 0.125) and the foot widened 28 % and lengthened 12 %, a closed shaft over the trouser leg, a turned band, a pull tab, the top painted dark as the inside | the shaft is a tube the leg comes out of, so the bare shin needs nothing of its own |
| Swing skirt | the Overalls' waist over the top's hem, a pleated wall (flat facets), a band at the hem, a lining up to a roof in the hips; the legs cut at z 0.62 and capped, bobby socks | one closed shell; the legs under it are knees and shins |
| Creature tee | the shirt's rule, a printed head on a sheet above her chest's fullest line, three fins down the spine for the shoulder camera | prints rest on `front_over`, so they ride the shirt's folds |
| Varsity gold | the letter jacket's collar, a gold body (two new fixed swatches, so it is gold on everyone), sleeves in the look's colour with one white stripe cut in, a star on the chest and a big one on the back | the stars are seated point by point (`seated_star`) |
| Creature mask | a closed 14-sided shell (half width 0.43, z 1.605-2.215), eyes, brows, a mouth with mismatched teeth, seven crest fins, ear fans, gill slits; `hides_hair` and `hides_eyewear` | wider than the jaw and a tall collar's top; the floor is closed, the neck comes out of it |
| Film-strip scarf | a thick band tilted onto the shoulders, two ends down the chest; each frame is one quad showing `film`, the atlas's one patterned swatch; her own variant | a tall collar's funnel comes out of the band |

Numbers they rest on (kit metres at rest, front -Y):

| Measured | Value |
| --- | --- |
| Room per slot, in every preset, both bodies, every mouth | near / far: feet 1,056 / 396, legs 854 / 367, torso 2,968 / 867, neck 354 / 234, headwear 354 / 234 (608 / 328 hiding the hair, 959 / 444 hiding the eyewear too) |
| The leg | straight tubes: x 0.04-0.336 either side, y -0.147 to 0.167, trousers end at z 0.187; the knee at z 0.56 |
| The foot | x 0.121-0.293 either side at the sole, z -0.023 to 0.195 |
| The head | x +-0.34, y -0.388 to 0.309, up to z 2.193; glasses reach x +-0.31 at y -0.405, outside any shell that fits the head |
| `film` swatch | cell (2, 2): a fixed 16 px tile (sprocket holes, a moon over a dark lot); the sprocket holes in faces would have passed the neck's far room of 234 |

What broke on the way:

- **The boot's shaft had a slit at the ankle**, with the trouser leg showing. Three changes to the rays that fit it did
  nothing: the shaft was blended to the foot up to z 0.26, so a bent ankle left it behind while the hem went with the
  shin. It stays on the shin down past the hem (z 0.16), and only the ring in the foot bends.
- **A knee through the skirt could not be measured as a vertex inside it**: its wall is thin. A ray from the hips to
  the vertex over-counted too (0.6 m on a 0.4 m thigh): the wall folds near the hips. A place on the wall now counts when
  nothing lies between it and the leg's own line.
- **The thigh's share is a trade**: at 85 % a raised thigh showed through the wall; with all of it past z 0.74 the skirt
  opened in a V to the waist. What works is to take the thighs away: the legs stop just under the skirt, and the hem
  takes 95 % of the thigh's turn, growing from nothing at the hips.
- **The wall's top ring on the bare Hips bone parted from the waist** in every pose: it borrows the same skin as the waist.
- **`tube` closed both ends**, which put a dark floor across the hem; the roof then faced up, a back face from under the
  skirt, once the hips were gone from behind it.
- **The rim of a curved `panel` was inside out** on top (the mask's mouth): each face was turned away from the rim's
  middle, which is the wrong way on a curve. The rim is wound by its own order now. The ear fans' outlines were
  clockwise (`test_every_part_is_closed_on_both_bodies` caught both).
- **Rings laid over a sleeve stood clear of it**: the arm is thinner than the shoulder. Stripes are cut in
  (`cut_sleeve`); each cut crosses the long sleeve faces, so one wide stripe fits and two did not (6,009 near).
- **A flat star lost its points under the curve of the back.** It is seated point by point, and the chest star sits
  above her chest's fullest line, where it fell between the jacket's vertices.

The clips (`test_soldier_ladder_clips.gd`, a suite of its own so the shards stay even): the mask and the film stay out of
the shoulders in every clip. Recorded in `clip_fit_recorded.json`, with caps in the test: `ladder two`, a forearm 92 mm
under the mask's rim at the top of `Grenade_Throw` and a hand 47 mm into the skirt's flare in `Run`; `skirt`, the wall in
a knee up to 139 mm at full stride (16 sides cannot hold it; it reads as the skirt riding over the knee) and a hand up to
93 mm under the flare in `Sprint_Pistol`. Hair and hats are held to the shoulder camera (`test_hair_and_the_camera.gd`):
the mask passes.

Not covered by a test: a top's folds against the skirt's waist, as with the bib. In `Duck` the top's hem shows through in
small patches. Looked at in Idle, Run and Duck, the far level at 24 m (the crest thins out, the silhouette holds).

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

## The wardrobe's cost in the night

Every catalogue mesh used to stand in every dressed soldier, hidden, and eight soldiers are alive in a night: four bodies
and four HUD portraits, each in a SubViewport that draws one picture. The late-round budget's `mesh_instances` walks the
tree, SubViewports too, so each mesh in the file cost eight. Peaks in the same CI step (limit 2,600):

| Build | Meshes a soldier | Peak |
| --- | --- | --- |
| Main before the mouths (#1088) | 94 | 2,402 |
| Main with the mouths | 110 | 2,534 |
| Wave one without the mouths | 120 | 2,610 |
| Wave one with the mouths | 136 | 2,728 |
| With `SoldierLook.trim` | 11 to 15 | 1,734 (local; the unfixed build reads 2,718 here) |

The peak moves by about 10 between runs: the crowd's own meshes differ. Freed, not set aside: a node out of the tree is
an orphan, and the budget holds those to 2.
