# Audio

How the original sounds are made and what the audio service taught us. The design (what it should sound like, the
service's rules) is [Sound](../design/audio.md).

## Making sounds with code

`tools/audio/` is three small files: `dsp.py` (noise, envelopes, oscillators, filters, a cheap open-air reverb, one echo),
`recipes.py` (one function per sound, plus the registry of variants and peak levels) and `generate.py` (renders every
recipe to a 16-bit WAV, then encodes Ogg Vorbis, quality 4, with the pinned ffmpeg). Run it from the repository root:

```text
uv run --with numpy --with scipy python tools/audio/generate.py --ffmpeg <pinned ffmpeg> [--wav-dir <keep the WAVs>] [--only name]
```

- **Repeatable.** A sound's seed is a CRC of its name and variant number, and ffmpeg runs with bit-exact flags, so two
  runs produce identical files (checked: all 52 hashes equal). Change a recipe, rerun, commit the new files.
- **Size.** 52 files, 450 KiB in all (3 to 38 KiB each; a gunshot is 7 to 9 KiB). Mono at 44.1 kHz except the two stings
  (stereo). Small enough that nothing needs streaming for the web build.
- **What each is made of.**
    - Gunshot: three layers, summed then soft-clipped: a **crack** (high-passed noise, 8 to 20 ms), a **blast** (low-passed
      noise whose cutoff falls from 6 kHz while it decays) and a **body** (a sine sweeping down, 120 Hz to 42 Hz for the
      shotgun). Then one filtered slap-back echo and an exponentially decaying, darkening noise convolution for the open
      air. Per class it is a table of numbers (`GUNS`).
    - Reloads and clicks: a few inharmonic damped sines (ratios 1, 1.58, 2.31, 3.37, 4.9, which reads as struck steel)
      plus a 3 ms noise transient; sliding metal is band-passed noise with a bumpy envelope.
    - Gravel: 34 to 52 grains of 12 ms band-passed noise scattered by a half-normal draw, under a faint thump.
    - Zombie voice: a sawtooth with slow random pitch jitter, a low-passed copy plus breath noise, through two vowel
      formant sets (three resonant band-passes each, "oh/aa/uh") crossfaded over the length, amplitude broken by
      low-passed noise (rasp) and optionally a 38 Hz growl; all of it soft-clipped, then a short room.
    - Generator hum: 60 Hz mains harmonics, 24 power strokes a second, a low-passed noise rumble made periodic by
      filtering in the frequency domain. Every part is a whole number of cycles in 2.000 s, so the loop has no seam
      (the last and first samples differ by 0.006 of full scale; the largest step between neighbours is 0.036);
      the stroke envelope has a 2 ms attack, because a hard step at each stroke is a click.
    - Stings: a timpani sine sweep, three detuned sawtooths per note of a minor cluster through a sweeping low-pass,
      a vibrato sine gliding up an octave, a high-passed noise swell, then two different room tails (left and
      right) to make the mono mix wide.
- **Hearing without ears.** An agent cannot listen. What was checked instead: log-frequency spectrogram sheets
  (`ffmpeg showspectrumpic`) to see clicks, formant bands, the generator's stroke rate rising and the theremin glide;
  peak levels (no clipping anywhere); the loop seam; file sizes. Whether it *sounds good* is a human's call: expect
  tuning passes on the numbers in `recipes.py`, which is why they are all in one place.

## The night's sounds (#88)

Added in `tools/audio/night_recipes.py`, rendered by the same `generate.py` (which now takes the loops from
`Entry.loop` and renders both files' registries). Nothing is sampled: all of it is noise, oscillators and filters.

- **Loops are built circularly.** `_wrap_add` puts an event in at any time and wraps what runs past the end back to the
  start; noise comes from `_ring_noise` (random phases between two frequencies, so it repeats exactly) and the filters
  that touch the whole file are applied in the frequency domain. Crickets chirp a whole number of times in the loop, the
  projector's motor is a whole number of cycles in 12 s (48, 96, 144 Hz) and its clatter is 288 frames at 24 a second.
  Measured seam (last sample to first, against the largest step inside the file): crickets 0.0027 (0.578), highway
  0.0000 (0.034), projector 0.011 (0.074), score 0.003 (0.020): all under the in-file steps, so no click.
- **Crickets:** a pulse is a 16 ms Hann-windowed sine with a quiet second harmonic, three to a chirp 24 ms apart; the
  chirp rate is rounded to a whole number per loop; each insect's loudness follows a slow wandering curve, so they
  sing in bursts instead of droning.
- **Highway:** a ring-filtered rumble under a slow swell, plus six passes (3.5 to 6.5 s, a sine-squared swell) of
  band-passed noise whose centre falls from about 850 Hz to about 450 Hz (the doppler of a car going by) over a faint
  low saw for the engine.
- **A board pulled off:** a *creak* (a pulse train gated by a 14 to 22 Hz stick-slip and wobbled in pitch, through two
  wooden resonances near 800 and 1650 Hz), then at 0.92 of it a *crack* (1.5 kHz high-passed noise 12 ms, a 420 Hz
  woody ring that falls, three to six splinter ticks) and the board dropping as a short thud. The last board is the same
  with a lower creak, a 95 to 45 Hz boom and three decaying clatters. A repair is three knocks about a fifth of a
  second apart, each a falling sine with a nail's metal ring on top, rising in pitch as the nail goes in.
- **The player's voice** reuses the zombie throat (`_voice`) with much less rasp and growl and more breath, pitched at
  120 to 190 Hz, so the living and the dead are one family; the downed groan falls to 70 Hz and ends in a body thud.
- **Measured** (`tools/audio/analyze.py report`): no file clips (peaks -1 to -5 dBFS by design, the catalog trims the
  rest); the 13 new sounds are 125 KiB of effects and about 730 KiB of loops and score.
- **Without ears, again:** `analyze.py sheet` draws a waveform and a log-frequency spectrogram per file; `analyze.py
  capture` reads a Movie Maker mix and checks that every sound the scene logged starts where it was played. In the
  real-night capture (`game/tests/captures/audio_night_tour.tscn`) every sound was found within 0.3 s of its event, the
  mix peaked at -2.6 dBFS with no clipped sample, and the bed alone sat at about -36 dBFS RMS, 16 to 33 dB under the
  sounds on top of it.

### What went wrong

- **`Dictionary.merged(other)` keeps the old value** unless its second argument is `true`: the catalog's overrides on a
  base that already had the key (a UI sound's pitch, `dry_fire`'s range) were silently dropped (#135). The catalog now
  lays overrides through one helper, `_with`, and a test reads the catalog's own source and fails on any other call.
- **Streams still held at exit** are reported as `resources still in use at exit`: a bed (or any sound) playing when the
  engine shuts down keeps its decoded stream, and so does the service's own cache. The night's suites ended with 4 to 9
  such lines once the beds played. The service now stops every voice, drops every player's stream and clears its cache
  in `_exit_tree`; waiting in `_exit_tree` did not help, letting go of the streams did. A loop that lives outside the
  service (the projector's player, under the night) is stopped by its node.
- **A stopped voice is still held until the mixer thread has run a few steps** (#317). `stop()` only marks the playback
  for removal; the audio server keeps it, and its stream, until the mixer takes a step or two. Quitting first leaks
  every such stream, and a fixed real-time wait (the capture waited 0.3 s) is too short whenever the mixer thread is
  starved, which failed CI's headless night at random on busy runners (1 in 20 with a CPU burner on every core; 1 in 3
  when quitting at once). `Audio.wait_for_mixer()` counts the mixer's own steps (`AudioServer.get_time_since_last_mix`
  falls when one lands) instead of waiting a set time; call it after `stop_all()` before any quit. A test reads a
  stream's reference count to see the server let go.
  The wait alone was not enough once the guns had tails: `WeaponSounds` (and the other night sounds) hold scheduled
  sounds (a shot's tail 40 to 70 ms later, a reload's steps) that start from `_process` after `stop_all()`, so voices
  began again during the wait and were still playing at quit (CI: 10 objects, 4 resources, every run; 8 of 8 locally).
  The capture now frees the night, which frees those players, before it stops the audio and waits for the mixer.
- **A bed never goes quiet**, so an onset detector on the raw level finds nothing: `analyze.py` compares the short-term
  level with its own median over a second either side.

## Weapons and the lot (#250)

Added in `tools/audio/weapon_recipes.py` (synthesised) and `tools/audio/elevenlabs.py` (generated), listened to by
`WeaponSounds`, `GrenadeSounds` and `WorldSounds` in `game/gameplay/night/`. The design is
[Sound](../design/audio.md); this is what was learned.

- **Hitscan has no tracer, so the report sells the shot.** The old shot was one file: a crack, a roar and a 120 Hz sine
  that rang for 0.3 s like a struck pipe (the spectrogram's bright line at the bottom). Each shot is now three voices
  (report, blast, tail) with their own variants, pitch and level, so the same shot is a different sound each time
  (5 x 3 x 3 combinations per gun) and the report's transient is the loudest thing in the first 10 ms. Before and
  after, rifle: `rifle_before` against `rifle_after` in the pull request's spectrogram.
- **Variation costs voices, so the groups have limits.** Blasts 5, tails 4, impacts 6; the SMG's blast and tail have a
  0.14 s and a 0.22 s cooldown. Twelve SMG shots a second still start the report every time.
- **Reload steps from the clip's frames.** `clips.json` lists the events in frames at 24 a second (the revolver and
  SMG's `mag_out` 6 and `mag_in` 22; the rifle's `round_in` 20, 32, 44 and `lever` 56; the shotgun's `break_open` 6,
  `shells_in` 26, `snap_shut` 34). The sounds read those frames (`ClipEvents`) on a `SoundSchedule` the node steps, so a
  test checks every step 1 ms either side of its frame with no wall time. Not scaled to the weapon's `reload_time`: the
  animation plays at its own speed, and the rifle's lever (2.33 s) lands after the simulation's 2.2 s reload ends, as the
  picture does.
- **World impact versus flesh.** The server sends the pellets' end points in `shot_fired` and the zombie hits in a
  `damage_dealt` right after, so a pellet that ended short of the weapon's range is held until the next step and each
  hit claims the nearest end within 1.5 m; what is left struck the lot. A shotgun's eight pellets ricochet at most
  three times.
- **The generator follows its load.** The load is the draw of the lit circuits over all of them (`GeneratorLoad`,
  built from `fuel_changed`, `circuit_changed`, `fuel_empty`, `fuel_restored`); level and pitch are lerped by it and
  slew at 24 dB/s, so a breaker thrown is a change you hear take a second. A dry tank stops the loops; they restart
  on a refuel.
- **Generated clips (ElevenLabs Sound Effects, free tier).** Used for the shots' blasts (3 variants a gun), the
  generator's engine loop, power-down and power-up, and the door purchase; 17 clips, 33 seconds, billed 40 credits a
  second (about 1,300 credits of the 3,500 allowed). Every file's prompt is in `game/assets/audio/eleven/LICENSE.md`
  with its licence: attribution required, not licensed for commercial use, to be replaced or relicensed before any
  commercial release (#252). Model `eleven_text_to_sound_v2` was used (the v3 model was not tried, to spare credits).
  What the files needed: levels from -22 to +4 dBFS once decoded (several above full scale), a lead-in of up to 0.3 s,
  and no seed, so a bad take is a new request. `elevenlabs.py` trims the silence before the sound, levels to -1 dBFS,
  fades the end and encodes Ogg; a file that exists is never fetched again, and `--reprocess` redoes only the levelling.
- **Layering over them.** The generated blast sits 9 dB under the synthesised report and the synthesised tail 10 dB,
  so the report's transient stays the front and the generated clip is the body and the roll. Nobody could listen to it:
  this is balanced by the numbers below and wants a pair of ears.

### Measured in the capture

Run with `game/tests/captures/audio_arms_tour.tscn` under Movie Maker (480 x 270, 30 frames a second); the mix is
analysed with `tools/audio/analyze.py capture`.

| What | Result |
| --- | --- |
| The tour (buys, a fight with five weapons, a grenade, the generator running low, dry and refuelled) | 70.3 s; 53 kinds of sound, 200 voices started, 21 culled by distance |
| Mix peak, clipped samples | -2.7 dBFS, 0; RMS -26.1 dBFS |
| The same tour with the first trims | 0.0 dBFS, 1,754 and then 3,401 clipped samples: see the next point |
| Reload steps against the clip's frames (15 steps, five weapons) | worst error 0.017 s (a movie frame is 0.033 s); the rifle's four steps exact |
| Sounds found within 0.3 s of the event that caused them | 13 of 19 spot-checked; the others are present but have slow attacks (the sputter, the power-up, the tonic's gulp) or sit under another sound, so the onset detector places them 0.3 to 0.5 s off |
| A lone shot (report, blast, tail) at 1.7 m, peak in the mix | pistol -6.1, SMG -11.7, shotgun -2.4, rifle -3.4 dBFS |

- **Why the first trims clipped.** Cutting every gun's `volume_db` by 8 dB changed little. `AudioStreamPlayer3D`
  boosts a sound by `unit_size / distance` and the only ceiling is `max_db`, +3 dB over the file: at 1.7 m with a
  `unit_size` of 14 that is 18 dB, so everything close sat at the ceiling and three layers per shot stacked past full
  scale. A shotgun trimmed to -23 dB still peaked at -5 dBFS. The fix is `SoundDef.near_cap_db` (0 for the arms and
  the lot), which sets the player's `max_db` to its own level, so the trim is what you hear up close; far away nothing
  changes. The generator's loops move their `max_db` with their level. Measured by playing each gun alone at 1.7 m at
  three offsets (`game/tests/captures/audio_gun_levels.tscn`): the peaks follow the offsets once the cap is on.
- **No flesh hits at the fence.** Most of the tour's shots (38 ricochets against 3 impacts on a zombie) hit the boards
  or the lot: the dead stand behind the fence. The flesh and headshot impacts are covered by the tests; a capture in the
  open field would show more.
- **The generator's power-down** arrived 3 s after the tank was emptied in the tour, because a tick of the rules was
  needed to raise the event (events a test raises outside `GameRules.apply` are dropped: `apply` starts with a fresh
  list).

## The dead (#248)

- **The voices.** `tools/audio/zombie_recipes.py` makes the per-type sounds with the same throat model as the first
  four (`recipes._voice`): a runner's shriek (380 to 940 Hz), a brute's groan an octave under the walkers' and its
  breath (noise in two bands over a 58 Hz rumble), a crawler's moan and drag (low-passed band noise with a grain),
  the headliner's roar (a sub sine at half the pitch under a growling voice, the echo off the screen) and growl, and
  three feet (shuffle, run, stomp). The grunt and the growl peak at known times into the file (0.07 s, 0.92 s), a
  constant in the recipe and in `ZombieVoiceTable`, which is how the game times them to the blow.
- **ElevenLabs takes.** `tools/audio/elevenlabs_zombies.py` asks the Sound Effects API for extra takes of the
  groans, snarls, hurts, deaths, shrieks and the roar (24 calls, 35.5 s requested, which is 1,420 credits at 40 a
  second; the account counted 444 used). It reads `ELEVENLABS_API_KEY` from the environment, trims the silence, fades
  and normalises each take, encodes it, and skips a take whose file exists, so a rerun costs nothing. There is no
  seed: variety comes from asking again. The files are licensed per
  `game/assets/audio/zombie/LICENSE.md` (free tier, attribution, relicense before a commercial release, #252). Their
  spectrograms show more hiss above 5 kHz than the synthesised ones (centroids of 3 to 5 kHz against about 1 kHz),
  which the rear cue and the distance low-pass soften; whether they sound right is a human's call.
- **Unit size is not a size.** `AudioStreamPlayer3D`'s inverse attenuation is `unit_size / distance`, which is above 1
  inside `unit_size`: a boss with `unit_size` 14 at 3 m was 13 dB over its file, held by `max_db` (3 dB) only, and its
  roar and growl clipped the mix. `unit_size` 7 and -6 to -7 dB trims fixed it. Keep `unit_size` near the distance
  at which a sound should start to fall away, not larger.
- **Lambdas copy plain variables.** A capture or test that updates an `int` from inside a `Callable` passed to a
  helper changes its own copy; use a dictionary or array both sides share.
- **Measured** (`audio_dead_horde`, a horde of twelve closing from 24 m at 1.2 to 4.2 m/s, four directions, then the
  headliner; the mix of `--write-movie`, analysed in numpy):

| What | Result |
| --- | --- |
| Left against right, seconds 1 to 10 of the horde from the left / from the right | +5.9 dB / -5.8 dB (the pan law's ear) |
| Left against right, horde from the front / from behind | +0.9 dB / -0.6 dB: centred |
| Centre of energy of the approach, from the front / from behind | about 1.2 kHz / 0.7 kHz: the rear cue |
| Voices held at once: zombie voices / feet / all | 6 of 6 / 5 of 5 / 10 of 32 |
| Sounds started / culled over 54 s | 934 / 31 |
| Mix peak, clipped samples | -0.4 dBFS, 0 (before the boss levels were trimmed: 0 dBFS, 268 clipped) |

## Godot facts

- **Movie Maker records audio.** `--write-movie out.png` also writes `out.wav` next to the frames: the master mix at the
  mix rate (48 kHz), but as **32-bit integer PCM**, not 16-bit. Read as 16-bit it comes out as noise at twice the length.
  Mux with `ffmpeg -framerate 10 -i out%08d.png -i out.wav -shortest`. Give `--write-movie` an absolute path: a relative
  one resolved against the project folder lands somewhere unexpected and the writer then fails every frame with
  `f_wav.is_null()`.
- **`AudioStreamOggVorbis.loop`** is on the resource; the import setting also exists, but a file shared by a one-shot and
  a loop is easier to keep as a duplicate with `loop = true`.
- **Ducking in an effect.** An `AudioEffectAmplify` added to the bus at runtime (`AudioServer.add_bus_effect`) and moved
  with its `volume_db` leaves the bus's own volume to the settings. Remove it again when the service leaves the tree,
  or every test (or scene reload) stacks another one.
- **`AudioStreamPlayer3D`** keeps `global_position` when its parent is a plain `Node`, so pooled players can sit under
  the service and be moved per play. `max_distance` silences beyond it; `unit_size` is the loudness at range;
  `attenuation_filter_cutoff_hz` is the built-in low-pass the service lowers for occlusion.
- **The listener** is the active `Camera3D` unless an `AudioListener3D` is made current. A top-down capture camera 11 m
  up would make every distance wrong; the capture gives the player its own listener.
- **GdUnit4 and sound.** The headless run uses the dummy audio driver: players "play", buses and effects exist, nothing
  is heard. A test cannot rely on `finished`, so the service times a voice by its stream length and its own clock.

## Measured in the captures

Run with the capture scenes in `game/tests/captures/` (`audio_menu_tour`, `audio_yard_tour`), mix analysed in numpy:

| What | Result |
| --- | --- |
| Rifle shot, open ground at 9 m, three times | RMS -20.0 dB, peak -2.7 dB, centre of energy 3.1 kHz |
| The same shot behind the wall at 11 m, three times | RMS -29.6 dB, peak -13.9 dB, centre of energy 0.47 kHz |
| Mix peak, the yard tour / the menu tour | -1.1 dB / -5.8 dB, no clipped samples |
| 28 zombies groaning in one frame | 6 voices started, the six nearest (lit in the capture) |
| Ducking read on screen 1.8 s after `round_start` | -4.8 dB, releasing (9 dB held for 1.6 s, then 14 dB/s) |

The wall figure combines the 9 dB occlusion trim, the lowered cutoff and the extra 2 m of distance.

## Open questions

- Does the web build play many `AudioStreamPlayer3D` voices without crackle on a modest laptop? Not measured: the capture
  is native. The pool is 32 positional voices; if the web build needs fewer, the limit is one constant
  (`AudioService.POOL_3D`) and the group limits already keep most nights well under it.
- `AudioStreamPlayer3D` sample playback on the web (the engine can play short sounds as browser "samples") changes
  how filters and effects apply. Check when the first web export exists.
- A real occlusion probe needs the map's walls on their own physics layer; set `Audio.occluder_mask` then.
