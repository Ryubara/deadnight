# Zombies

The dead of the drive-in: which kinds there are, how they look at a distance, and what they play. Built from the kit
zombie (Quaternius "Zombie", CC0) within the [style bible](style.md); how the variants are made and what was measured
is in [zombie variants (research)](../research/zombie-variants.md). The rules that pick them (speeds, the runner type, light)
are in [rounds](rounds.md).

## Variants

A horde reads as many people when it differs in three ways at once: **silhouette** (read at 30 m), **height** (read
in a crowd) and **colour** (read up close). Every variant is the kit zombie's skeleton unchanged, so one animation
library plays on all of them.

| Variant | Role | Silhouette | Height | Colours | Gameplay / far tris |
| --- | --- | --- | --- | --- | --- |
| Walker | the common dead, every round | the kit zombie, bare-chested | 1.00 | kit: green skin, blue-grey shorts, brown belt | 4,000 / 1,500 |
| Greaser | common, every round | short-sleeved tee | 1.02 | pale skin, cream tee, denim, black belt | 4,000 / 1,500 |
| Usher | common, every round | long sleeves, pillbox cap | 0.97 | drive-in uniform: red jacket and cap, gold belt and band, black trousers | 3,999 / 1,500 |
| Farmhand | common, every round | left forearm gone | 1.00 | tan shirt, olive trousers | 3,999 / 1,500 |
| Runner | the runner type (round 4 on) | lean limbs, taller, vest | 1.07 | bright skin, blue vest, grey shorts | 3,999 / 1,500 |
| Brute | rare and tough (proposal: from round 10, one at a time) | broad torso and arms, tallest | 1.18 | dark skin, bare chest, blue-grey work trousers | 3,999 / 1,500 |
| Crawler | a walker whose legs are shot off, or a spawn from round 6 | no lower legs; on the ground | 1.00 | pale grey skin, rag vest, brown trousers | 3,999 / 1,500 |

Height is the scale on top of the zombie's game scale (1.3, in the style bible). At game scale the walker stands
1.77 m at rest, the brute 2.09 m and the usher 1.72 m: a crowd has a skyline, but nothing taller than a door.

Rules for adding one:

- **Change the silhouette first.** A palette swap alone does not read past 15 m; the far LOD keeps silhouettes and
  big colour blocks only.
- **Tops are painted on.** The kit zombie is bare-chested, so a shirt is skin faces moved to a cloth swatch: no
  triangles, no new bones. Vest (torso), short sleeves (upper arms) and long sleeves (forearms) are the three cuts.
- **Missing parts follow a bone.** The kit body is made of closed shells per limb, so removing a forearm or the lower
  legs leaves no hole to patch.
- **Colours come from the kit palette** (style bible) where one fits, plus the zombie skins. New colours are swatches
  on the one zombie atlas; never a second material.
- **Budget**: 4,000 tris gameplay, 1,500 far, one material, one skinned mesh per level of detail.

The runner rule (a type: one on round 4, then 6% of a round growing 4% a round to 30%, at 1.7 times the walk and
never above 4.5 m/s) makes the runner the variant that has to be
seen early: it is the tallest of the commons and the only one in blue, so a player can tell it in a crowd before it
starts to run.

## Crowd budget

The crowds spike (kit `docs/godot/crowds.md`) holds 40 zombies as the ceiling and 20 to 30 as the normal wave, with
one mesh per zombie (the separate eyelid mesh cost 30 % of the browser frame at 80). The rounds cap a solo night at 28
alive.

| Zombies alive | All at gameplay LOD | Half far | Notes |
| --- | ---: | ---: | --- |
| 20 | 80k | 55k | the style bible's planning number |
| 28 (solo cap) | 112k | 77k | |
| 40 (spike ceiling) | 160k | 110k | |

Every variant ships as one file with both levels of detail under one skeleton (`Zombie_Mesh`, `Zombie_Far`); the
game switches them with visibility ranges (proposal: far beyond 18 m). Both meshes are skinned, so a zombie costs one
skeleton and one draw call whichever is shown.

## Boss: the Projectionist

The headliner of boss nights: the drive-in's projectionist, grown huge in the booth, still wearing his pale dust coat,
the projector's arc lamp burning in his gut and a film reel strapped across his back. Built by
`tools/blender/build_boss.py` (pinned Blender, headless; how to run it is at the top of the file) as a variant on the
shared rig, the way the brute is made, into `game/assets/characters/zombie_boss/`.

| What | Choice | Why |
| --- | --- | --- |
| Height | 1.45 (armature scale): 1.97 m at kit scale, 2.56 m at game scale | a head over the brute (2.09 m): the one thing on the lot taller than a door |
| Build | vertices pushed 60-75 mm along the normals on torso, arms and belly, 25 mm on the legs | a barrel body under the kit head |
| Colours | pale dust coat `#bdb39a` (long sleeves), grey-green skin `#6f7f5c`, near-black trousers | the palest mass on the lot catches any light; nothing else wears it |
| Silhouette | a film reel (0.38 m radius, kit scale) upright on the back, wider than the shoulders | from the front it is a dark disc behind the head; from the side a slab; no common has it |
| Weak spot | the arc lamp in the belly: a dark housing, a grey rim and an amber lens `#ffd27a` that glows (emission map, strength 6) | the brightest point on the lot at night; the attack's wind-up lifts the arms and shows it fully |
| `WeakSpot` node | an empty on the `Torso` bone at the lens; Godot makes it a `BoneAttachment3D` | the hitbox and an `OmniLight3D` hang from it and follow every clip |
| Budget | 8,000 gameplay, 3,000 far (8,314 built: kit 7,822 plus 492 for the lamp and reel) | two walkers' worth; one boss on a 20-zombie night is 88k at gameplay LOD, inside the 80-112k crowd numbers above |
| Material | one, its own: the zombie atlas plus the boss swatches, and a black emission map lit only at the lens | the commons' shared atlas has no emission; one boss is one extra draw call |

It keeps the 50-bone skeleton and carries the kit's 16 clips, so `ZombieRig` attaches to it unchanged; its own five
clips are added beside them (`clips.json` next to the model has lengths, loops and event frames):

| Clip | Length | Loop | Events (frame at 24 fps) | What it shows |
| --- | ---: | --- | --- | --- |
| `Boss_Walk` | 1.67 s | yes | | the kit Walk slowed from 32 to 40 frames, hunched, arms hanging lower, the chest rolling over the planted foot |
| `Boss_Attack` | 2.50 s | no | windup 0, telegraph 22, hit 32, recover 44 | a two-handed overhead smash: arms climb overhead and hold (0.9 s to the peak, 1.33 s to the hit), a fast slam, a slow recovery; the raised arms bare the lamp, the opening players learn |
| `Boss_Roar` | 2.75 s | no | roar 22 | the entrance: gather, rear up with the arms flung up and out, a shaking roar, settle |
| `Boss_Stagger` | 1.42 s | no | hit 0 | a lamp hit: thrown back, then folded over the lamp with the hands at it, back up at 1.4 s |
| `Boss_Death` | 2.17 s | no | fall 20 | the stagger's recoil and fold, then the kit Death slowed 2.5x: a heavy fall onto the back |

In the night all of this is wired ([research](../research/zombies.md#the-headliner-in-the-night)). Rules for the behaviour
code: loop `Boss_Walk`; time the attack's damage on `hit` and let the dodge window run from
`telegraph`; the lamp goes dark on `Boss_Death` (set the material's emission off); the reel clips the ground in the
last frames of the death, which the dark hides.

## Animation set

The kit zombie has 16 clips (24 fps, no root motion). A round-based zombie needs these; "kit" clips are shared through
the rig-sharing recipe as they are, "new" ones have to be made.

| Need | Clip | Length | Source | Notes |
| --- | --- | ---: | --- | --- |
| Spawn: climb out of the ground | `Emerge` | | **new** | interim: `Death` played backwards from its last frame reads as getting up |
| Stand | `Idle` | 1.00 s | kit, fixed | the kit's Idle has no arm channels; the build holds the Walk's arms (research) |
| Walk | `Walk` | 1.33 s | kit | the arms-forward shamble |
| Walk variant: limp | `Walk_Limp` | | **new** | for the farmhand and anyone hit in the leg |
| Walk variant: upright | Enemy's `Walk` | | kit character | shared through the recipe with rebased position keys; a fresher dead |
| Run | `Run`, `Run_Arms` | 0.67 s | kit | runners; `Run_Arms` (arms reaching) for half of them |
| Crawl | `Crawl` | 1.67 s | kit | crawlers; legless bodies play it as is. The rules emit `zombie_crippled` (`speed_scale` 0.35) when a [grenade blast](weapons.md#grenades) takes the legs: the zombie drops to the ground, plays `Crawl` at the scaled speed, and swaps to the Crawler variant's legless mesh |
| Attack | `Punch`, `Idle_Attack`, `Run_Attack` | 0.75, 1.67, 0.67 s | kit | swipe in reach; a grab-and-bite at a downed player; a lunge at run speed |
| Crawler attack | `Crawl_Attack` | | **new** | a grab at the ankles |
| Hit reaction | `HitReact` | 0.58 s | kit | upper body; played additively over the walk |
| Stagger | `Stagger` | | **new** | a heavy hit (melee, shotgun): a step back |
| Death | `Death` | 0.75 s | kit | |
| Death variants | `Death_Forward`, `Death_Crawl` | | **new** | three deaths keep a cleared wave from looking the same |
| Barrier break-in | `Tear_Boards` | 1.21 s | **made** (#221) | reach, grab, strain, yank, at the fence's boards: [Tearing boards](#tearing-boards) |
| Vault a counter or fence | `Jump`, `Jump_Idle`, `Jump_Land` | 0.33, 0.50, 0.33 s | kit | three parts for a vault over the snack-bar counter |
| (not used) | `Wave`, `Yes`, `No` | 1.67 s | kit | left in the file, never played |

Six new clips still to make, in the order the game needs them: `Emerge`, `Stagger`, `Walk_Limp`, `Crawl_Attack`,
`Death_Forward`, `Death_Crawl`. They are authored on the kit zombie's rig in Blender and exported with the same
recipe, so they play on every variant. New clips go into `tools/blender/build_zombie_clips.py`: one file of their own
(`game/assets/characters/zombies/clips/zombie_clips.glb`, kit skeleton and mesh, only the new clips, `clips.json`
beside it) whose clips `ZombieRig` adds to the shared library and the boss's, so the variant files are not rebuilt.

### Tearing boards

`Tear_Boards` (29 frames, 1.21 s at 24 fps, loops, full body; the rig is the kit zombie's 50 bones, not the
Soldier's 43): reach in with a forward lean (0-6), hands close on the board (`grab` 9), lean back and strain (14-20),
**`yank` 22** (the chest throws back and turns, the hands come past the shoulders: the board leaves the hands here),
fling and settle (25-29), back to the stance the next reach starts from.

| What | How |
| --- | --- |
| When it plays | the snapshot's mode byte has a tearing bit (`ZombieCodec.TEARING_BIT`): the simulation sets `tearing` on a zombie at its boards that is working one loose this step. While it is set, the view stays in the `tear` state through the simulation's repeated swings (new episodes) |
| Pace | a type takes `seconds_per_board / barrier_speed` a board (walker 1.2 s, brute 0.48 s); `Night` hands it per look to the views |
| First board | the clip starts at the reach, played so the yank lands one board's time later, when the rules tear it (the work starts from nothing) |
| Every tear | the rules' `board_torn` names the zombie: its clip is set to the yank and from there plays one full loop per board, so the next yank lands on the next tear |
| Interrupted | a stagger leaves the tear state (the flag drops); back at the boards the clip restarts at the reach, and the next tear puts it on the yank again |

Checked in `game/tests/zombies/test_zombie_tear.gd`: the simulation, the wire format and the view run together step by
step, and at every tear the clip is at its yank (the walker to the frame, the brute within one 30 Hz simulation step).
The board's own flight is the fence's ([map](map.md)).

## Playback variety

A crowd must never march in step. Per zombie, chosen by the seeded random of the rules engine:

| What | Range | Why |
| --- | --- | --- |
| Start phase | 0 to the clip length | no two zombies plant the same foot together |
| Play speed | ground speed / clip speed, then times 0.9 to 1.1 | feet keep up with the ground; the jitter breaks sync between zombies at the same speed |
| Walk to run | `Walk` below 1.6 m/s, blended into `Run` to 2.6 m/s, `Run` above | round 1 walks at 1.2 m/s, round 10 at 2.6, round 20 at 4.2: late walkers run |
| Runner run | `Run` or `Run_Arms`, half each | two run silhouettes in one wave |
| Light | a zombie off lit ground is 25 % faster; the blend follows the speed it really moves at | the dark makes the dead run: the player sees the light hold them back |
| Hit | `HitReact` added over the walk, not replacing it | the walk never stops mid-stride |
| Death | one of three deaths | a cleared wave does not fall the same way |

The animation throttle of the crowds spike (update far and unseen zombies less often) also breaks sync for free: a
zombie updated every third frame drifts against its neighbours.
