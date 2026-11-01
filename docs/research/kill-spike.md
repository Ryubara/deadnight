# The lag on every shot and kill (web)

The maintainer felt a small stutter at each kill in the browser, and then at each shot. This page is what the
frames showed, where the time went, and what was changed. The general Godot findings are in the kit page
[Audio](https://github.com/Ryubara/gdstudio/blob/main/docs/godot/audio.md). First-use stutters (a program built the
first time something is drawn) are a different thing: [First-use hitches](first-use-hitches.md).

## How it was measured

`KillBench` (`game/tools/bench/`) plays a night with the bot through its shoulder camera, quick and with a player who
cannot die, and `PerfLog` writes every frame: the time since the frame before, objects, resources and nodes alive, and
what `PerfProbe` timed and counted in it (a probe costs one static read when off). It starts instead of the menu when
the page's address has `?bench` (or `--bench` on a desktop). `tools/web_smoke/kill_spike.py` serves the web export,
runs it in a fresh headless Chrome profile on the real GPU (RTX 5080, unpaced, so a frame's time is its work), and
reports the frames by what happened in them (a shot, a kill, a zombie arriving or leaving) with a chart lined up on the
frame of the shot or the kill. The bot buys no door or weapon (a door starts a navigation bake; that is another cost).
Three runs of 70 s each, 37 kills a run (28 for the older build, which also shopped).

## Where the time went (before)

An ordinary frame takes 4.1 ms. The frame of a shot took 11 to 12 ms and the frame of a kill 12 to 13 ms (worst 18):
**about 8 ms over**, half a 60 Hz frame, so a slower machine drops the frame. Of the extra, by what
the probes timed in a kill frame (means, ms):

| Cause | ms | What it is |
| --- | --- | --- |
| Starting sounds | 5.0 | six sounds start in the frame (shot, blast, impact, hurt cry, points, death), each 0.8 ms in the browser: starting a player on an Ogg Vorbis file makes the engine read its headers and codebooks again |
| Points on the HUD | 1.0 | a gain label and the points box rebuilt (portrait key, colours) at every kill |
| Effects of the shot | 1.2 | the flash, the impacts, the damage number (a Label3D, a tween and a node for each) |
| Server tick | 0.6 | the shot's ray and the rules |
| Rest | 1.5 | the death voice's search, the view, the engine's own drawing of what was made |

Nothing leaked: the resource count was the same before and after a kill. The cost was **made and freed in the
frame**: a shot built about 35 objects and freed them 0.2 to 1 s later (49 lights, 175 meshes and 40 labels over 14
kills), and a zombie that left was freed (a model, a skeleton, an animation tree and its state machine) while a new one
was built for the one that came. The same went for a zombie arriving (2 ms) or leaving (2 ms).

## What was changed

- **Sounds are samples.** A short sound (up to 2.5 s) is decoded once into 16-bit samples when the night loads
  (`PcmStream`, called by `AudioService.preload_sound`, behind the loading screen: 1 s for all 240 files in the
  browser, 14 MB) and plays from them: 0.3 ms to start, not 0.8. Loops and beds stay Ogg.
- **A start budget.** In the night at most two sounds start in a frame; the rest start in the next frames, the highest
  priority first, and one that waited 0.12 s is dropped (`AudioService.starts_per_frame`). The kill's six sounds
  start over three frames; no one hears 16 ms.
- **Beds that come and go are kept.** The score between rounds took 43 ms to start a minute of music, at the end of
  the round, in the frame of its last kill. `AudioService.keep_bed` starts it silent and paused during loading; after,
  starting it is a fade. Loops are copied at preload, not when they start.
- **Streaks and damage numbers are pooled** (`ShotEffects`: lent, hidden when done, animated by age, one material);
  the muzzle flash and the impacts are pooled by #325 (`MuzzleFlash`, `ImpactFx`), which this builds on.
- **Zombie bodies are kept** (`ZombieHorde`: parked by look when a zombie leaves, up to 12 a look, and made ahead of
  the night by the warm-up, `NightWarmup.PARKED_BODIES`), and a parked body starts over as the next zombie.
- **The HUD** lends the labels of its point gains (`HudGains`) and skips what did not change in a points box.

## Results

Web, three runs each, the median of the frames in a fight, ms (an ordinary frame 4.1 to 4.2 both times):

| Frame of | Before | After |
| --- | --- | --- |
| A shot | 11.1, 11.7, 11.7 (worst 14 to 18) | **6.9, 7.0, 7.0** (worst 9 to 10) |
| A kill | 12.4, 12.6, 13.2 (worst 16 to 18) | **7.3, 7.4, 7.7** (worst 12) |
| A zombie arriving | 6.4 to 6.6 | 5.9 to 6.1 |
| A zombie leaving | 5.8 to 6.2 | 5.1 to 5.5 |

On a desktop (window, same GPU) the frame of a kill went from 11.1 ms to 6.7 (worst 15.4 to 9.6).

**Not met:** the target was a shot or kill within 2 ms of an ordinary frame; it is within 3 (the shot 2.9, the kill
3.2 to 3.6). What is left in the frame, in ms: sounds starting 0.6, HUD 0.5, effects 0.5, the shot's ray and the
rules 0.5, the engine's own drawing of the flash and the impacts the rest. The next steps are the HUD (a points change
still rebuilds a box) and the flash's light.

## What is still over 33 ms in a 70 s run

Three frames of 36 to 78 ms, at the same moments in every run. Each is **a program the browser links the first time**
(no script ran in them, the page's WebGL hook shows a link of 25 to 56 ms): at the bot's first wound, at the end of
the first round and at the start of the second. They are unshaded and lit by no lamp, without fog, with a texture:
the warm-up does not draw them. Also found while measuring, and not changed here: the first frames of a night, when
the bot walks to its post, link 15 programs in 2 s (a 1.9 s frame; a person who walks the same way meets them too),
the first door bought bakes the navigation again (a 400 ms frame, #335), and after merging the warm-up with `main`
`test_a_night_draws_nothing_the_warm_up_did_not` fails: the prize crane's effects (its beam, sparks and plush) came
after the warm-up's list.

## The tests

- `tests/night/test_kill_allocations.gd` plays 14 kills with the bot and asserts no node enters the tree and no
  resource is held that was not before. **It fails on the build before:** 362 nodes made over 14 kills (49 lights, 175
  meshes, 40 labels, 14 zombie bodies), 20 resources, 222 objects.
- `tests/weapons/test_shot_effects_pool.gd`, `tests/zombies/test_zombie_pool.gd` and
  `tests/core/test_audio_start_cost.gd` test the pools, the samples, the start budget and the kept beds one by one.
