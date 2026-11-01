# Sound

How Deadnight sounds, and the rules the audio service plays by. The sounds are original: every file in
`game/assets/audio/` is synthesised by the scripts in `tools/audio/` (how: [research](../research/audio.md)), so they
are committed and can be changed by editing a number. The code is `game/core/audio/`; the sounds' table, with every
level and limit, is `sound_catalog.gd`.

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

The layout is the settings screen's (`default_bus_layout.tres`, volumes owned by `Settings`). Nothing here changes it.

| Bus | Carries | Ducked by the sting |
| --- | --- | --- |
| Music | stings (and, later, the score) | no |
| Effects | guns, reloads, steps, the dead, the generator | yes |
| UI | menu and widget sounds | no |

Ducking never touches a bus's volume. The service adds one `AudioEffectAmplify` to Effects and moves that, so the
player's own sliders and the duck do not fight.

## The sounds

Each has several variants where repeating would be noticed (a play never picks the same one twice in a row) and a small
random pitch. Levels are trims on files that are all normalised, so balancing is one number per sound.

| Group | Ids | Notes |
| --- | --- | --- |
| UI | `ui_hover`, `ui_focus`, `ui_tick`, `ui_press`, `ui_back`, `ui_push`, `ui_pop` | relay clacks and a rising or falling film whoosh; hover and focus together make one sound |
| Guns | `shot_pistol`, `shot_smg`, `shot_rifle`, `shot_shotgun`, `dry_fire` | three variants each; crack, blast, thump and the echo off the screen tower |
| Reloads | `reload_pistol`, `reload_smg`, `reload_rifle`, `reload_shotgun` | magazine out, in and the bolt; the shotgun's three shells and pump |
| Steps | `step_asphalt`, `step_gravel` | four variants each; gravel is a spray of tiny grains |
| The dead | `zombie_groan`, `zombie_attack`, `zombie_hurt`, `zombie_death` | one throat model, different pitch curves, vowels, rasp and growl |
| Grenades | `grenade_tick`, `grenade_throw`, `grenade_bounce`, `grenade_blast` | the tick is one fixed pitch whose rate rises with the fuse, so a cook can be timed by ear; the blast is a crack, a roar that darkens and a deep boom (nine tenths of its energy under 150 Hz) |
| The lot | `generator_hum` (loops), `generator_start` | the hum is a whole number of cycles, so it never clicks at the seam |
| Boards | `board_tear`, `board_last`, `board_repair` | at the breach, from `board_torn` and `board_repaired`: a creak then a crack for each board pulled off, a bigger crack, a low thump and the board clattering for the last one, three knocks for one hammered back |
| Doors | `door_open` | a bolt thrown, a rusty creak, the weight settling; from `door_opened`, at the door |
| Melee | `melee_swing`, `melee_hit` | a crowbar through the air from `shot_fired` of a melee weapon; the thud of iron on the dead from a melee `damage_dealt` |
| The till | `till_ring` | the shop's cash register (key thump, ratchet, bell) from `purchase_made`, where the buyer stands |
| The player | `player_hurt`, `player_downed` | a grunt, and a falling groan with the body hitting the ground; the player's own are flat (in their head), a teammate's are where they stand |
| Stings | `round_start`, `round_end`, `special_round` | stereo, on Music; `round_start` ducks Effects 9 dB; `special_round` (3.5 s, on the rules' `special_round_announced`, a higher priority so it takes the one sting voice from the `round_end` that is still sounding) 9 dB for 2.2 s |
| Beds | `bed_crickets`, `bed_highway`, `bed_projector`, `bed_score` | loops under everything, see below |

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

Still not played by the night (their files and catalog entries exist): the dead's voices, the footsteps, the generator's
hum and the grenades, which the capture scenes play by hand (an open issue).

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
- **Occlusion.** A probe (`occlusion_probe`, or a physics ray against `occluder_mask`, off until the map has walls on
  their own layer) returns 0 to 1. A fully blocked sound is 9 dB quieter and low-passed at 1.1 kHz, and counts as half as
  loud when the budget compares it. Measured in a capture: a rifle shot behind a wall was 10 dB down and its centre of
  energy fell from 3.1 kHz to 0.5 kHz.
- **Ducking.** A sting lowers Effects by its `duck_db` (9 dB for `round_start`, 5 for `round_end`) at 80 dB/s, holds it
  for the sting's front (1.6 s, 0.8 s) and lets go at 14 dB/s.
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
