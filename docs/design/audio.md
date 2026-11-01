# Sound

How Deadnight sounds, and the rules the audio service plays by. The code is `game/core/audio/`; the sounds' table, with
every level and limit, is `sound_catalog.gd`.

## Where the sounds come from

Almost every sound is original: it is synthesised by the scripts in `tools/audio/` (how:
[research](../research/audio.md)), so it is committed and can be changed by editing a number. The folders under
`game/assets/audio/` with no licence file hold only such files; nothing in them is third-party.

The exception is 24 files in `game/assets/audio/zombie/` (extra groans, snarls, hurts, deaths, shrieks and roars),
generated with ElevenLabs Sound Effects on the free tier. They are third-party output: attribution required, not
licensed for commercial use, to be relicensed or replaced before a commercial release
([#252](https://github.com/Ryubara/deadnight/issues/252)). Their licence entry, with every prompt, is
[`zombie/LICENSE.md`](https://github.com/Ryubara/deadnight/blob/main/game/assets/audio/zombie/LICENSE.md), and the
Credits screen names ElevenLabs. Pull request #277 (open) adds ElevenLabs takes for the weapons and the lot, with a
licence file of their own.

The licence file records the choice to use the takes as relayed by the coordinator. The maintainer's own first-hand
confirmation is still pending ([#292](https://github.com/Ryubara/deadnight/issues/292)).

## Direction

A 1958 drive-in, after dark, with something wrong at the screen. The sound should feel like that night: **close and
dry where you are, big and open everywhere else, and a little theatrical**.

- **Open air, not a corridor.** Shots crack, thump and then roll away across an empty lot, with one slap of echo off the
  screen tower. No long caves of reverb: the lot is flat and hard.
- **Machines are the kit.** The booth's relay clack is every button; the generator's hum and cough are the lot's heartbeat
  (its stroke rate climbs as it catches); the projector gate is the film-leader whoosh of a screen change.
- **The dead are voices, not roars.** A groan is a throat (pitch, vowel, rasp, breath), not a monster growl: slow, low,
  always a little human, so a crowd reads as people and not as noise.
- **B-movie stings.** Round start and end are title-card music from the era's instruments: low timpani, a minor stab of
  brass, a theremin wail that rises, a cymbal swell, then a quieter, bell-like resolve when the round is survived. The
  special-round sting is the marquee switching on: eleven bulbs ticking on faster and faster, a reel whirring up, two
  low organ stabs and a gong. Era film and radio were studied for instruments and timing only; nothing is copied.
- **Everything is a cue for survival.** The generator carries far and is heard through walls; a groan tells you which
  way, a reload tells the team you are exposed.

## Buses

Six buses, each with its own slider in the settings screen (`default_bus_layout.tres`, volumes owned by `Settings`).
Everything goes to Master, which is the master slider.

| Bus (slider) | Carries | Ducked by the sting | Default |
| --- | --- | --- | --- |
| Music | stings and the score | no | 80 |
| Effects | guns, reloads, steps, the dead, the generator, boards, doors, blows, the till | yes | 100 |
| Voice ("Voices") | the player's own hurt and downed voices | no: what you hear of yourself is never ducked | 100 |
| Ambience | the crickets, the highway and the projector | yes | 80 |
| UI ("Interface sounds") | menu and widget sounds | no | 80 |

The ambience sits lowest on purpose (its sounds are 14 to 22 dB under a footstep), so a player who finds the night too
busy turns one slider and keeps the guns. A sting ducks Effects and Ambience together, so the title card is heard over the
night; Music, Voice and UI are left alone.

Ducking never touches a bus's volume. The service adds one `AudioEffectAmplify` to each ducked bus and moves those, so the
player's own sliders and the duck do not fight.

## The sounds

Each has several variants where repeating would be noticed (a play never picks the same one twice in a row) and a small
random pitch. Levels are trims on files that are all normalised, so balancing is one number per sound.

| Group | Ids | Notes |
| --- | --- | --- |
| UI | `ui_hover`, `ui_focus`, `ui_tick`, `ui_press`, `ui_back`, `ui_push`, `ui_pop` | relay clacks and a rising or falling film whoosh; hover and focus together make one sound |
| Guns | `shot_<gun>`, `blast_<gun>`, `tail_<gun>` for the pistol (the revolver), SMG, rifle and shotgun; `shot_flare`, `burst_flare`; `dry_fire`, `weapon_swap` | see [The guns](#the-guns) |
| Impacts | `impact_flesh`, `impact_head`, `impact_world` | a wet thump, the same with a crack and a knock, and a round on asphalt or sheet metal with a ricochet's whine |
| Reloads | `reload_pistol_mag_out/_in`, `reload_smg_mag_out/_in`, `reload_rifle_round/_lever`, `reload_shotgun_open/_shells/_shut` | one sound for each event frame of the reload clip |
| Steps | `step_asphalt`, `step_gravel` | four variants each; gravel is a spray of tiny grains |
| The dead | `zombie_groan`, `zombie_attack`, `zombie_hurt`, `zombie_death` and the per-type sounds below | one throat model, different pitch curves, vowels, rasp and growl; the first four also have ElevenLabs takes as extra variants |
| Grenades | `grenade_tick`, `grenade_throw`, `grenade_bounce`, `grenade_blast` | the tick is one fixed pitch whose rate rises with the fuse, so a cook can be timed by ear; the blast is a crack, a roar that darkens and a deep boom (nine tenths of its energy under 150 Hz) |
| The lot | `generator_hum` (loops), `generator_engine` (loops), `generator_start`, `generator_up`, `generator_sputter`, `generator_down`, `generator_down_air`, `breaker_on`, `breaker_off` | see [The lot's machines](#the-lots-machines) |
| The shop | `door_unlock`, `door_buy`, `buy_weapon`, `buy_ammo`, `buy_fuel`, `buy_tonic`, `deny`, `points_tick`, `points_kill` | what each purchase sounds like (besides `till_ring`), the refusal's buzzer and the points |
| The crane | `crane_spin`, `crane_claw_drop`, `crane_claw_lift`, `crane_prize`, `crane_break`, `crane_move` | the prize crane's play, from the rules' `crane_*` events, at the crane: `crane_spin_started` is the claw going down and a carnival jingle that slows down (5.4 s, a bell at 4.6 s as the 4.5 s spin ends), `crane_prize_ready` the claw hauling up and, 0.35 s later, the prize ding, `crane_prize_taken` the rack's clack, `crane_breakdown` sputter, sparks and power-down, `crane_moved` a whoosh and a clunk, and a refused take the buzzer |
| Boards | `board_tear`, `board_last`, `board_repair` | at the breach, from `board_torn` and `board_repaired`: a creak then a crack for each board pulled off, a bigger crack, a low thump and the board clattering for the last one, three knocks for one hammered back |
| Doors | `door_open` | a bolt thrown, a rusty creak, the weight settling; from `door_opened`, at the door |
| Melee | `melee_swing`, `melee_hit` | a crowbar through the air from `shot_fired` of a melee weapon; the thud of iron on the dead from a melee `damage_dealt` |
| The till | `till_ring` | the shop's cash register (key thump, ratchet, bell) from `purchase_made`, where the buyer stands |
| The player | `player_hurt`, `player_downed` | a grunt, and a falling groan with the body hitting the ground; the player's own are flat (in their head), a teammate's are where they stand |
| Stings | `round_start`, `round_end`, `special_round` | stereo, on Music; `round_start` ducks Effects 9 dB; `special_round` (3.5 s, on the rules' `special_round_announced`, a higher priority so it takes the one sting voice from the `round_end` that is still sounding) 9 dB for 2.2 s |
| Beds | `bed_crickets`, `bed_highway`, `bed_projector`, `bed_score`, `bed_tension` | loops under everything, see below |

### The beds

The night is never silent. Three looping beds start with the night and fade in over three seconds; all sit well under a
footstep (14 to 22 dB), so they are felt when they stop rather than heard.

- **Crickets** (24 s): eight insects, each its own pitch (3.7 to 5.3 kHz) and chirp rate, singing in bursts.
- **A distant highway** (32 s): a low rumble that swells and thins, and six passes of a car or truck whose pitch falls.
- **The projector** (12 s, a loop in the world, not flat): the gate's 24 clatters a second over a motor and a fan, from
  the middle of the projection booth, so it is only heard near it (35 m, `unit_size` 4).
- **The score** (32 s, stereo, on Music): a low organ pad through four chords with a sub bass and a sparse theremin
  wail. It plays in the **breaks**: it fades in when a round ends and out when the next begins, so it never fights the
  stings. At the game's end every bed fades out over two seconds.

All four are built to loop: every event that runs past the end wraps to the start and every filter is applied to the
whole loop at once, so the seam is smaller than the largest step inside the file (measured in
[research](../research/audio.md)).

### The guns

Every shot of a firearm is **three voices**, each with its own random variant, pitch (within 0.6 to 1 semitone) and
level (plus or minus 1.2 dB), so repeats do not machine-gun: the **report** (`shot_*`: a high-passed crack and a falling
chest thump, five variants, 0.05 to 0.35 s, synthesised), the **blast** (`blast_*`: the body and the roll of the shot,
three variants, generated with ElevenLabs, see [research](../research/audio.md)) and the **tail** (`tail_*`: the lot
rolling the shot away and one slap off the screen tower, three variants, started 40 to 70 ms late). An automatic gun's
blast and tail have a cooldown (the SMG's 0.14 s and 0.22 s), so twelve shots a second are twelve reports over one roll.
The hitscan weapons have no tracer, so the report has to sell the shot. The flare gun is a hollow pop and a rising hiss;
its burst sizzles where it lands (`projectile_burst`).

- **Impacts.** A `damage_dealt` (not melee) thumps where the round hit; a headshot cracks. A hitscan pellet that ended
  short of the weapon's range and was not claimed by a hit in the same batch ricochets where it struck the lot, at most
  three times for a shotgun's eight pellets.
- **Reloads** sound on the reload clip's event frames from `clips.json` (`ClipEvents`), the same frames the player's
  animation emits: the revolver and SMG on `mag_out` (6) and `mag_in` (22), the rifle on `round_in` (20, 32, 44) and
  `lever` (56), the shotgun and flare gun on `break_open` (6), `shells_in` (26) and `snap_shut` (34), at 24 frames a
  second. Putting the weapon away abandons them.
- **Empty and swap.** A `fire_rejected` for an empty magazine clicks where the shooter stands; a `weapon_equipped`
  rustles.
- The crowbar's swing and blow are the melee sounds above.

### The lot's machines

- **Generator.** Two loops play from the generator: the synthesised hum and a generated engine. Their level follows the
  **load** (the draw of the lit circuits over the draw of all of them: hum -15 to -7 dB, engine -22 to -9 dB) and their
  pitch rises 0.94 to 1.05. Below the tank's low line the engine **sputters** (a cough every 4 s, every 1 s when nearly
  dry) and its pitch wobbles; when it runs dry (`fuel_empty`) it winds down (`generator_down`, with a generated
  layer) and the loops fade out; on a refuel (`fuel_restored`) the pull-cord start and a generated roar play and the
  loops come back.
- **Breakers.** A circuit thrown plays a heavy clunk with a zap for on and a dry drop for off, at its post.
- **The shop.** Every `purchase_made` plays its item's sound at the buyer (a door: the padlock and then, 0.2 s later, a
  generated chain-and-hinge, under `door_open`; the till is `till_ring`). A refused buy (`purchase_denied`) buzzes for
  the player who was refused. Own points ticking up (`points_changed`) ticks for a hit and rings for a kill.
- **Tension.** `bed_tension` (8 s, Music) fades in 2.4 s after a round starts, once the sting's front is over, and out
  when it ends. It is a low drone of two close notes beating, a tritone that breathes and a slow double heartbeat, 20 dB
  under the file's level; the breaks belong to the score.

- **Grenades.** `GrenadeSounds` plays the throw at the hand, a tick while a player cooks one (every 0.5 s at the start of
  the fuse, every 0.1 s at the end, so a cook can be timed by ear), each bounce (louder when it hits harder, -9 to 0 dB)
  and the blast where it goes off. The night does not run the grenade server yet (#239), so these hear nothing in a
  real night until it does; the capture tells them the events the server will send.

The code is `gameplay/night/weapon_sounds.gd`, `grenade_sounds.gd` and `world_sounds.gd`, each listening to the client
state's events like `NightSounds`, on a `SoundSchedule` clock they step themselves.

### The dead, per type

`ZombieVoices` (`game/gameplay/zombies/`) plays them from what a client hears: each frame's decoded zombies and the
rules' `zombie_damaged` events. Who sounds like what is one table, `ZombieVoiceTable`.

| Look | Idles with | Noticed | Swing | Feet |
| --- | --- | --- | --- | --- |
| walker, greaser, usher, farmhand | `zombie_groan` | `zombie_alert`, a rising snarl | `zombie_grunt`, a short chesty effort | `zombie_step_shuffle` (a dragging scuff), `zombie_step_run` from 2.2 m/s |
| runner | `zombie_groan` | `zombie_shriek`, thin and high | `zombie_grunt` | `zombie_step_run`: a hard slap and scuff |
| brute | `zombie_breath_brute` (a big chest working), `zombie_groan_brute` | `zombie_groan_brute` | `zombie_attack` | `zombie_step_stomp`: a deep thump |
| crawler | `zombie_groan_crawler`, a reedy moan | `zombie_alert` | `zombie_grunt` | `zombie_drag`, a body hauled over asphalt |
| headliner | `zombie_groan_brute` | none (the roar is its announcement) | `zombie_growl_boss`, climbing to its peak on the blow | `zombie_step_stomp`; `zombie_roar` when it rises and, quieter, when it falls |

- **Rationed idles.** Every zombie has a random timer (5 to 11 s) and the whole horde one gate: at most one idle voice
  every 0.6 to 1.6 s, picked at random from the nearest three that are due. Twenty-eight zombies due in one frame start
  one groan, not twenty-eight. Idles are heard to 36 m.
- **Noticed.** A snapshot carries no target, so a chasing zombie snarls once, the first time it comes within 22 m,
  and no two snarls start within 0.35 s of each other.
- **Timed to the blow.** The swing sound is started `windup - lead` after the swing begins, `lead` being how far into
  its file the effort peaks (0.07 s for the grunt, 0.92 s for the headliner's growl), so the peak lands on the blow:
  at 0.45 s for a walker, 1.2 s for the headliner. A swing that repeats (at the boards) repeats the cue every 1.2 s.
- **Feet in the clips' cadence.** A foot plants twice per cycle of the clip that plays at the zombie's speed (walk
  1.33 s, run 0.67 s, crawl and boss walk 1.67 s; the blend runs from 1 m/s to 3 m/s as in `ZombieRig`), starting from
  the per-id phase the view starts the clip at. Standing zombies and those past 28 m are silent. The plant being at
  0 and half the cycle is an assumption; the clips carry no foot events.
- **Voice cap and priority.** Voices share the service's groups: `zombie_voice` (6; groan 30, breath 25, hurt 50,
  death 55, grunt 62, alert 65, shriek 66), `zombie_boss` (2; growl 86, roar 88, so the headliner is always heard) and
  `zombie_step` (5, priority 15, below the player's own steps and in a group of their own so a horde's feet never
  take the player's). Nearer sounds beat farther ones at the same priority.
- **Bus.** The dead play on Effects, not Voice: Voice is the player's own pain, which is never ducked, while the
  dead duck under a sting like every other sound in the lot.
- **Behind you.** Every dead sound has `rear_cue`: a sound behind the listener is low-passed (from 5 kHz at the side
  to 1.8 kHz straight behind), because panning alone cannot tell front from back on two speakers.

Not heard in a real night yet: the grenades, because the night does not run the grenade server (#239); `GrenadeSounds`
is ready for its events.

## The service's rules

- **Pooled.** 32 positional and 12 flat players are made once. A play takes a slot; no node is created while playing.
- **A budget, not a queue.** Each sound belongs to a group with a limit (twelve gunshots, six zombie voices, eight
  steps, one hover). Past a limit a play is dropped unless it is stronger than the weakest voice of its group: a higher
  priority, or the same priority and at least 15 percent louder (nearer). So of 28 zombies groaning together the six
  nearest sound, the rest do not, and when one steps closer it takes over from a farther one. Gunfire has its own
  group and always has room.
- **Priority** when the whole pool is full: sting 95, UI 90, the player's downed 88 and hurt 85, guns 80, last board
  75, doors 70, melee 70 to 72, generator 70, boards 65, till 65, reloads 60, zombie attack 60, death 55, hurt 50,
  groan 30, steps 20. A board torn outranks a groan, so it is heard over the horde at its breach.
- **Beds** are outside the budget: four players of their own, started by `Audio.start_bed(id)`, faded in at 20 dB/s
  and out at 30 dB/s on the service's own clock, so they are as testable as everything else. `stop_all` silences them.
- **Distance.** Each sound has a `max_distance` beyond which it is not started at all (a groan carries 40 m, a step
  30 m, a shot 90 m) and a `unit_size`; the engine does the attenuation, and its built-in distance low-pass dulls far
  sounds.
- **Near level.** The engine boosts a 3D sound by `unit_size / distance` as it comes close and stops only at the player's
  `max_db` (+3 dB over the file), so up close every sound sits at the same ceiling whatever its trim and a gun's three
  layers sum past full scale. A sound with a `near_cap_db` (the arms and the lot's sounds have 0) sets the player's
  `max_db` to its own level plus that, so close up the trim is the level and far away nothing changes.
- **Rear cue.** A sound with `rear_cue` is low-passed by how far behind the listener it is (`rear_amount`, from the
  listener node or the camera): 0 in front and at the side, 1 straight behind, where the cutoff is 1.8 kHz.
- **Occlusion.** A probe (`occlusion_probe`, or a physics ray against `occluder_mask`, off until the map has walls on
  their own layer) returns 0 to 1. A fully blocked sound is 9 dB quieter and low-passed at 1.1 kHz, and counts as half as
  loud when the budget compares it. Measured in a capture: a rifle shot behind a wall was 10 dB down and its centre of
  energy fell from 3.1 kHz to 0.5 kHz.
- **Ducking.** A sting lowers Effects and Ambience by its `duck_db` (9 dB for `round_start`, 5 for `round_end`) at
  80 dB/s, holds it for the sting's front (1.6 s, 0.8 s) and lets go at 14 dB/s.
- **Seeded.** Variants and pitch come from one generator (`seed_random`); the clock is the service's own
  (`advance(delta)`), so tests and replays do not depend on real time.
- **UI.** The service sets `UIAudio.handler` when it starts; every `gds_ui` control and every router transition then
  makes its sound with no screen doing anything. The cue-to-sound table is `SoundCatalog.UI_CUES`.
- **Rules.** `Audio.connect_rules(rules)` plays the sting on the rules' `round_started`, `round_ended` and
  `special_round_announced` events; the
  server sends the same events to every client, so the same sting plays for everyone.

## Using it

```gdscript
Audio.play(&"shot_rifle", muzzle.global_position)   # in the world
Audio.play(&"round_start")                            # flat, no place
Audio.start_loop(&"generator_hum", generator_node)    # a loop that lives on the node
Audio.listener = player_head                          # else the current camera
```

The listener should be the player's head. The engine hears from the active camera (or an `AudioListener3D`), so give
the player one. Set `Audio.occlusion_probe` once the lot has walls to hide behind.
