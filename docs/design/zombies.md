# Zombies

The dead of the drive-in: which kinds there are, how they look at a distance, and what they play. Built from the kit
zombie (Quaternius "Zombie", CC0) within the [style bible](style.md); how the variants are made and what was measured
is in [zombie variants (research)](../research/zombie-variants.md). The rules that pick them (speeds, sprinters, light)
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
| Runner | the sprinter (round 4 on) | lean limbs, taller, vest | 1.07 | bright skin, blue vest, grey shorts | 3,999 / 1,500 |
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

The sprinter rule (round 4 on, at most one in two, never above 4.5 m/s) makes the runner the variant that has to be
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
| Run | `Run`, `Run_Arms` | 0.67 s | kit | sprinters; `Run_Arms` (arms reaching) for half of them |
| Crawl | `Crawl` | 1.67 s | kit | crawlers; legless bodies play it as is. The rules emit `zombie_crippled` (`speed_scale` 0.35) when a [grenade blast](weapons.md#grenades) takes the legs: the zombie drops to the ground, plays `Crawl` at the scaled speed, and swaps to the Crawler variant's legless mesh |
| Attack | `Punch`, `Idle_Attack`, `Run_Attack` | 0.75, 1.67, 0.67 s | kit | swipe in reach; a grab-and-bite at a downed player; a lunge at run speed |
| Crawler attack | `Crawl_Attack` | | **new** | a grab at the ankles |
| Hit reaction | `HitReact` | 0.58 s | kit | upper body; played additively over the walk |
| Stagger | `Stagger` | | **new** | a heavy hit (melee, shotgun): a step back |
| Death | `Death` | 0.75 s | kit | |
| Death variants | `Death_Forward`, `Death_Crawl` | | **new** | three deaths keep a cleared wave from looking the same |
| Barrier break-in | `Tear_Boards` | | **new** | pull boards off a window; interim: `Idle_Attack` looped at the barrier |
| Vault a counter or fence | `Jump`, `Jump_Idle`, `Jump_Land` | 0.33, 0.50, 0.33 s | kit | three parts for a vault over the snack-bar counter |
| (not used) | `Wave`, `Yes`, `No` | 1.67 s | kit | left in the file, never played |

Seven new clips, in the order the game needs them: `Emerge`, `Tear_Boards`, `Stagger`, `Walk_Limp`, `Crawl_Attack`,
`Death_Forward`, `Death_Crawl`. They are authored on the kit zombie's rig in Blender and exported with the same
recipe, so they play on every variant.

## Playback variety

A crowd must never march in step. Per zombie, chosen by the seeded random of the rules engine:

| What | Range | Why |
| --- | --- | --- |
| Start phase | 0 to the clip length | no two zombies plant the same foot together |
| Play speed | ground speed / clip speed, then times 0.9 to 1.1 | feet keep up with the ground; the jitter breaks sync between zombies at the same speed |
| Walk to run | `Walk` below 1.6 m/s, blended into `Run` to 2.6 m/s, `Run` above | round 1 walks at 0.9 m/s, round 30 at 3.8: late walkers jog |
| Sprinter run | `Run` or `Run_Arms`, half each | two run silhouettes in one wave |
| Light | lit ground slows a zombie to 60 %; the blend follows the slowed speed | a sprinter drops into a walk in the light: the player sees the light work |
| Hit | `HitReact` added over the walk, not replacing it | the walk never stops mid-stride |
| Death | one of three deaths | a cleared wave does not fall the same way |

The animation throttle of the crowds spike (update far and unseen zombies less often) also breaks sync for free: a
zombie updated every third frame drifts against its neighbours.
