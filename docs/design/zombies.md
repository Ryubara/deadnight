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

The runner rule (a type: one on round 4, then 6% of a round growing 4% a round to 30%, at 1.4 times the walk and
never above 5.0 m/s under the lights, 6.25 in the dark; [rounds](rounds.md#zombie-types)) makes the runner the variant
that has to be seen early: it is the tallest of the commons and the only one in blue, so a player can tell it in a
crowd before it starts to run.

## Crowd budget

The crowds spike (kit `docs/godot/crowds.md`) holds 40 zombies as the ceiling and 20 to 30 as the normal wave, with
one mesh per zombie (the separate eyelid mesh cost 30 % of the browser frame at 80). The rounds cap a solo night at 28
alive, and any night with a browser in it at 40; a night of desktops and a server alone stands up to 120
([the platforms](#decision-a-ceiling-for-each-platform-453), the decisions below).

| Zombies alive | All at gameplay LOD | Half far | Notes |
| --- | ---: | ---: | --- |
| 20 | 80k | 55k | the style bible's planning number |
| 28 (solo cap) | 112k | 77k | |
| 40 (spike ceiling) | 160k | 110k | |

Every variant ships as one file with both levels of detail under one skeleton (`Zombie_Mesh`, `Zombie_Far`); the
game switches them with visibility ranges (proposal: far beyond 18 m). Both meshes are skinned, so a zombie costs one
skeleton and one draw call whichever is shown.

### Decision: the rules' cap stops at 40 (#315)

`RoundTuning.alive_cap` added 6 for each player after the first on the solo cap (28 at most), so four players asked
for 41 to 46 alive from round 22. The lot never stood them: the director's `ZombieTuning.hard_cap` is 40, and the
rules' extra zombies waited in its queue, counted alive by the rules and the balance model but not on the lot. In
the web build the 46 cap peaked at 40 standing in every run. Three ways out, and what the numbers said
([the measurement](../research/crowd-budget.md)):

| Option | Verdict |
| --- | --- |
| Keep 46 and let far detail carry the six | No: the far level of detail is already in the 40 (a zombie past 18 m is the cheap mesh), and the six never reach the lot, so nothing would be shown to carry. |
| Raise the ceiling to 46 | No: 40 at full detail costs 8 to 10 ms on a fast desktop in Chrome (2 to 3 ms as played), 6 more add about 1 ms there (0.15 ms a zombie) and three or four times that on the slower machine the budget is written for, which the crowds spike already named as the reason 40 is a ceiling and not a target. |
| **Lower the cap to the ceiling** | **Yes.** `RoundTuning.alive_cap_ceiling` is 40, the same number as `hard_cap` (a test pins that they match), so the rules, the balance model and the lot agree on what is alive. |

What changes: only four players are cut, from round 22 (round 21 is 40 already); three players reach 40 at round 29
and stay there, one and two never do. The table in [rounds](rounds.md) and [the lot](map.md) show the
cap per player count: 4 players are 24, 31, 39 and 40 in rounds 1, 10, 20 and 30 (46 at round 30 before).
The director's queue stays as a safety net for a tuning that asks for more.

### Decision: a ceiling for each platform (#453)

The 40 above was measured in the browser and held everywhere, so a desktop never had a budget of its own. Measured
on its own ([the numbers](../research/crowd-budget.md#desktop-and-game-server-100-and-more-alive-453-156)): a desktop
draws 120 zombies in 2.4 ms of frame (1080p, RTX 5080) and a server's 60 Hz tick takes 7.0 ms at the median and
14.8 ms at p95 for 120 on Railway's processor, 17.3 ms at p95 for 160, over the 16.7 ms tick. So:

| Where the night is played | Most alive at once |
| --- | ---: |
| A browser, alone or in a room with a browser in it | 40 (`RoundTuning.web_alive_cap_ceiling`) |
| A desktop alone, or a server with no browser in the room | 120 (`RoundTuning.alive_cap_ceiling`) |

The ceiling is the weakest client's in the match: a client says what it is after its welcome, one that says nothing
counts as a browser, and the rules' cap and the director's hard cap move together. The default curve is unchanged; 100
and more come from the "Most alive at once" match setting (its slider ends at the host's platform's ceiling) or from the
intensity multiplier. A game server also cuts each room to its share of an alive budget (`ALIVE_BUDGET`, 120 for the
whole process: a lone desktop room stands 120, three rooms 40 each), and an operator can cap a small container with
`MAX_ALIVE`; see the [crowd budget](../research/crowd-budget.md#rooms-in-one-process-561).

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
| Sprint | `Sprint` | 0.67 s | **made** (#278) | the fastest dead (6.5 m/s): the Run's cycle with a shorter ground contact, a deeper lean, lower hips and pumping arms; in step with `Run` ([gait](../research/zombie-gait.md#the-sprint)) |
| Crawl | `Crawl` | 1.67 s | kit | crawlers; legless bodies play it as is. The rules emit `zombie_crippled` (`speed_scale` 0.35) when a [grenade blast](weapons.md#grenades) takes the legs: the zombie drops to the ground, plays `Crawl` at the scaled speed, and swaps to the Crawler variant's legless mesh |
| Attack | `Punch`, `Idle_Attack`, `Run_Attack` | 0.75, 1.67, 0.67 s | kit | swipe in reach; a grab-and-bite at a downed player; a lunge at run speed |
| Crawler attack | `Crawl_Attack` | 1.25 s | **made** (#971) | a lunge along the floor and a grab at the ankles: [The crawler's attack](#the-crawlers-attack) |
| Hit reaction | `HitReact` | 0.58 s | kit | upper body; played additively over the walk (the crawler's is `Crawl_Stagger`) |
| Crawler stagger | `Crawl_Stagger` | 0.42 s | **made** (#1000) | a flinch on the floor: [A crawler's every action](#a-crawlers-every-action) |
| Stagger | `Stagger` | | **new** | a heavy hit (melee, shotgun): a step back |
| Death | `Death` | 0.75 s | kit | the walker's (the crawler's is `Crawl_Death`) |
| Crawler death | `Crawl_Death` | 0.83 s | **made** (#1000) | the arms give, the chest and head drop to the floor and it lies: [A crawler's every action](#a-crawlers-every-action) |
| Death variants | `Death_Forward`, `Death_Crawl` | | **new** | three deaths keep a cleared wave from looking the same |
| Barrier break-in | `Tear_Boards` | 1.21 s | **made** (#221) | reach, grab, strain, yank, at the fence's boards: [Tearing boards](#tearing-boards) |
| Vault a counter or fence | `Jump`, `Jump_Idle`, `Jump_Land` | 0.33, 0.50, 0.33 s | kit | three parts for a vault over the snack-bar counter |
| (not used) | `Wave`, `Yes`, `No` | 1.67 s | kit | left in the file, never played |

Five new clips still to make, in the order the game needs them: `Emerge`, `Stagger`, `Walk_Limp`,
`Death_Forward`, `Death_Crawl`. They are authored on the kit zombie's rig in Blender and exported with the same
recipe, so they play on every variant. New clips go into `tools/blender/build_zombie_clips.py`: one file of their own
(`game/assets/characters/zombies/clips/zombie_clips.glb`, kit skeleton and mesh, only the new clips, `clips.json`
beside it) whose clips `ZombieRig` adds to the shared library and the boss's, so the variant files are not rebuilt.

### The crawler's attack

A crawler is a walker whose legs went (or a spawn from round 6). It used to play the walker's `Punch` when it reached
a player, a clip authored for a body standing on two legs: the head went from 0.2 to 0.99 m (kit scale, 0.85 to 1.84 m
in the game) and the body stood up to strike and dropped again (#971: `ZombieView._enter` sent every look but the
headliner to the `attack` state, which was the `Punch`; only the move state had a crawl branch). It has an attack of its
own now.

**How crawling enemies attack in the genre, and why** (a reading of what game wikis and designers say, not a copy of
any one game). What the legless dead of the genre have in common is that they are *low*: the threat is not damage but
being easy to miss, since a player who watches the crowd at head height does not see the one on the floor, and what it
can reach is the legs. So their attack is a grab or a claw at the legs from the floor, never a standing blow: the Dead
Island crawler grabs onto the hero's leg and slashes at the legs ([wiki](https://deadisland.fandom.com/wiki/Crawler)),
the 7 Days to Die crawler drags itself along the ground and is much slower than the standing dead
([wiki](https://7daystodie.wiki.gg/wiki/Crawler_Zombie)), and the crawlers of other games are described as slow with a
weak melee blow, which is what makes a pack of them a nuisance and not a wall. Telegraphing guidance says the same
from the other side: the enemy needs a short pause that tells the player "here I come", and the visual change has to
come before the action, in a shape that reads at the camera's distance
([Game Developer](https://gamedeveloper.com/design/enemy-attacks-and-telegraphing)). Taken together, the design rules
for a crawler's attack are:

| Rule | Why | What it is here |
| --- | --- | --- |
| It never stands | a body that rises for the blow breaks the one thing the player knows about it, that it is low | the highest point of the body in the attack stays within the crawl's own height (+0.02 m measured, tests: 0.05 m on the mesh, 0.1 m on the bones) |
| It is shown before it lands, from the camera above and behind the player | a low target is the hardest to read; the player's camera looks down on it | a wind-up that changes the silhouette: the body draws back and the right arm cocks out wide beside the head, claw open (the widest shape the crawler makes), held a beat; then the body is thrown forward on the planted left arm and the right arm sweeps low across the floor |
| A longer telegraph than a walker's | it is easier to miss, so it is easier to see coming | 0.65 s from the start of the swing to the blow (the walker's is 0.45 s) |
| Its own, shorter reach | it grabs from the floor with what its arm and its lunge cover, and the lunge is slow to turn | the swing starts at 1.2 m (the walker's 1.4 m) and lands up to 1.6 m: the clip's fingertips reach 1.6 m from the crawler's feet at the grab, so what is drawn is what hits |
| A grab, not a knock-back | it holds the ankle, it does not throw the player | damage 12 (unchanged), knockback 0, fingers closing on the grab frame |
| It is committed | on its hands it cannot turn or retreat in a blow | the recovery is the walker's (0.75 s): drag back, settle into the crawl's first frame |

`Crawl_Attack` (30 frames, 1.25 s at 24 fps, full body, not looping; `tools/blender/build_zombie_clips.py`, built from
the kit Crawl's first frame so the clip starts and ends on the crawl): gather and coil (0 to 11: weight back, chest
lifting on the left arm, the right arm cocked), **`strike` 13** (the body thrown forward 0.46 m kit scale, the right
hand low across the floor, the left hand pulled forward), `grab` 16 (the fingers close), drag back and settle (16 to
30). The game plays it at the pace that puts `strike` on the type's `telegraph_seconds` (`ZombieView._enter`, the same
time scale as the headliner's attack); the type's `reach` and `telegraph_seconds` are data (`ZombieType`,
`default_tuning.tres`), carried by `zombie_spawn_requested` and read by the simulation from the profile
(`ZombieProfile.reach_in`).

| Part | What follows the clip |
| --- | --- |
| Hit zones | `crawler.strike` is fitted to `Crawl_Attack` (`tools/hit_fit/fit_hit_shapes.gd`: it was fitted to the `Punch`, so a shot at the grabbing crawler was aimed at a standing body) |
| The player's reaction | the hurt arc (`HudDamage`) swings in from the crawler's bearing as for any blow; with no knock-back a grab leaves the player where they were |
| Bots | `BotDodge.CRAWLER_WINDUP` (0.65 s); their reach numbers are the walker's, so a bot that keeps out of a walker's blow is out of a crawler's |
| Test | `game/tests/zombies/test_crawler_attack.gd`: a crawler in the real night (spawn, director, codec, horde, the sim's own swing) never rises above its crawl while it attacks, and the clip, reach, telegraph and view state each have a test |

### A crawler's every action

A body that cannot stand has its own clip for every action (#1000; #971 was the attack). Its stagger played the walker's
`HitReact` (the mesh's top went to 1.66 m against the crawl's 0.85 m) and its death the walker's `Death` (1.81 m), so
a crawler stood up when a shot hit it and again when it died, for the same reason as the attack: `ZombieView._enter`
chose the state by mode and the body only for the move and the swing. The list of actions of a body, and what each plays:

| Action (`ZombieBody.Mode`) | Walker (standing) | Crawler (lying) | Highest point (crawler, game scale) |
| --- | --- | --- | --- |
| Emerging | `move` (the model rises out of the ground) | `crawl` (the same rise) | the crawl's |
| Chase | `move` | `crawl` | 0.85 m |
| Attack | `attack` (`Punch`) | `crawl_attack` (`Crawl_Attack`) | 0.87 m |
| Stagger | `stagger` (`HitReact`) | `crawl_stagger` (`Crawl_Stagger`) | 0.87 m |
| Dying | `die` (`Death`) | `crawl_die` (`Crawl_Death`) | 0.85 m |
| Tearing boards | `tear` (`Tear_Boards`) | never: a crawler goes under the boards (`ZombieSim._work_the_boards`) | |
| Climbing a sill (#986, not merged when this was written) | `crawl` with a lean, for any look | the same | not measured here: check it when #986 lands |

`Crawl_Stagger` (10 frames, 0.42 s at 24 fps, the length of the type's `stagger_seconds` 0.4 s; full body, not looping):
from the Crawl's first frame, both hands planted, the body is thrown back 0.24 m (kit scale) along the floor, the chest
twists and lifts, the head snaps up and to the side (`recoil` 3), and it settles (`recover` 7, `end` 10) back on the
frame the crawl restarts from. `Crawl_Death` (20 frames, 0.83 s, not looping, the last frame held while it lies): the
arms buckle (`buckle` 4), the chest and then the face drop to the floor and the arms slide out to the sides (`drop` 9,
`settle` 15). Both are built by `tools/blender/build_zombie_clips.py` beside `Crawl_Attack`, and the hit set
`crawler.stagger` is fitted to `Crawl_Stagger` (`tools/hit_fit/fit_hit_shapes.gd`; a dying zombie is not shot at).
`game/tests/zombies/test_crawler_attack.gd` walks every mode of `ZombieBody.Mode` through the view and the real night
and fails when a crawler's highest bone in any of them stands over the crawl's.

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
| Play speed | ground speed / the gait's own speed (`ZombieRig.gait_rate`, 0.5 to 1.6) | feet keep up with the ground; the throttle's drift breaks sync between zombies at the same speed ([gait](../research/zombie-gait.md)) |
| Walk to run to sprint | `Walk` below 1.4 m/s, blended into `Run` to 3.0 m/s, `Run` to 4.4, blended into `Sprint` to 6.5 at its own rate, played faster past it (speeds of a walker's size) | round 1 shambles at 1.2 m/s, round 10 jogs at 2.6, round 20 runs at 4.2 and a runner sprints in the dark at 6.25 |
| Runner run | `Run` or `Run_Arms`, half each | two run silhouettes in one wave |
| Light | a zombie off lit ground is 25 % faster; the blend follows the speed it really moves at | the dark makes the dead run: under the lights they keep their round's pace, and the player sees the dark speed them up |
| Hit | `HitReact` added over the walk, not replacing it | the walk never stops mid-stride |
| Death | one of three deaths | a cleared wave does not fall the same way |

The animation throttle of the crowds spike (update far and unseen zombies less often) also breaks sync for free: a
zombie updated every third frame drifts against its neighbours.

## The flare lure

A flare does no damage (#439); a **re-cut** flare gun leaves a patch of fire for the same
seconds ([the burning ground](upgrades.md#the-four-elements)). Where it bursts it burns for
`WeaponDef.lure_seconds` (8 s), and for that time every zombie within `lure_radius` (25 m, along the
ground) walks to it instead of to a player; the maintainer's model is a monkey bomb or a pipe bomb.
The server owns it: the combat server sends `lure_started` (id, point, radius, seconds) with the burst,
`ZombieSim` holds the `ZombieLure`s and counts them down, and the client's `LureView` only draws the burning flare.

| Rule | What happens |
| --- | --- |
| Who hears it | a zombie within the radius that is up (not emerging, not dying); the nearest lure wins when several burn |
| Walking | the lure replaces the zombie's target: it paths to the flare (a new way is found when the lure changes) and ignores the players while it burns |
| Arriving | within `lure_gather_distance` (2.5 m, inside the swing's reach) it stops and stands about the flare, facing it; it swings at nothing |
| The end | the lure runs out and the zombie picks the nearest player again as it always does; no zombie is left holding a dead lure |
| Left alone by default | a zombie tearing boards (`lure_pulls_gate_zombies`), a boss (`lure_pulls_bosses`) and a zombie in the middle of a swing (`lure_breaks_swings`); each is a flag in `ZombieTuning`, off |

Checked in `game/tests/zombies/test_zombie_lure.gd` (the simulation alone), `game/tests/night/test_night_flare_lure.gd`
(a flare shot in a night: no damage, a zombie walks to it, the view draws it, the server ends it) and
`game/tests/weapons/test_combat_special.gd` (the event and the 0 damage). The numbers are in the flare's definition, not
in the code, so a new lure weapon is a new `.tres`. Findings: [the flare lure](../research/flare-lure.md).

## Finding the last ones: the outline through walls

When a round is down to its last `ZombieTuning.mark_last` zombies (3), counting those still to spawn, every
player sees them outlined in orange through walls, so a round is never stuck on one zombie in a corner. The
outline is the silhouette's edge, a few pixels wide at any distance, with no glow; the body is not filled. It
is drawn only where the zombie is hidden (a zombie half behind a car is outlined below the car's edge only; one
in the open has none). It clears when the round ends or a zombie dies. How it is built, what it costs and the
choices to retune (colour, width, N) are on the [research page](../research/outline.md).

### A round never waits on them (#950)

Two rules keep the last dead from holding a round open, whatever stops the people reaching them
([why, and the numbers](../research/zombies.md#a-round-that-waits-on-its-last-dead-950)):

- **The siege.** A dead that has pulled at one window's boards for 30 s (`ZombieSim.SIEGE_SECONDS`) without getting
  through, because a hand puts them back as fast as it tears them, bursts them: every board that stands comes off and it
  walks in. A hit on it starts the count over.
- **The rescue.** With only the marked few left (`mark_last`) and nothing happening to them for 30 s
  (`ZombieDirector.RESCUE_AFTER`: no blow struck, no damage done, no kill), a dead that has no way to anyone (the
  walking mesh leaves its path 3 m or more short: a pocket) rises again at the spawn point nearest the people that is
  25 m or more from them (the farthest on a map with none that far) and not at the breach it stood at, and walks in
  as a new one does. A dead that has a way is coming, however slowly, and is never moved.
