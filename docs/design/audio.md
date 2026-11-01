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
  brass, a theremin wail that rises, a cymbal swell, then a quieter, bell-like resolve when the round is survived. Era
  film and radio were studied for instruments and timing only; nothing is copied.
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
| Stings | `round_start`, `round_end` | stereo, on Music; `round_start` ducks Effects 9 dB |

Not made yet (open issues): the ambient night bed (crickets, distant highway, the projector), melee swings, doors and
boards, the shop's till, the player's hurt and downed voices, a score.

## The service's rules

- **Pooled.** 32 positional and 12 flat players are made once. A play takes a slot; no node is created while playing.
- **A budget, not a queue.** Each sound belongs to a group with a limit (twelve gunshots, six zombie voices, eight
  steps, one hover). Past a limit a play is dropped unless it is stronger than the weakest voice of its group: a higher
  priority, or the same priority and at least 15 percent louder (nearer). So of 28 zombies groaning together the six
  nearest sound, the rest do not, and when one steps closer it takes over from a farther one. Gunfire has its own
  group and always has room.
- **Priority** when the whole pool is full: sting 95, UI 90, guns 80, generator 70, reloads 60, zombie attack 60, death
  55, hurt 50, groan 30, steps 20.
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
- **Rules.** `Audio.connect_rules(rules)` plays the sting on the rules' `round_started` and `round_ended` events; the
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
