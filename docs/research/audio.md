# Audio

How the synthesised sounds are made, how the few ElevenLabs ones are fetched, and what the audio service
taught us. The design (what it should sound like, the service's rules, where every sound comes from) is
[Sound](../design/audio.md).

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
  chirp rate is rounded to a whole number per loop (1.0 to 2.1 a second each since #781, from 2.0 to 4.2); each
  insect's loudness follows a slow wandering curve, so they sing in bursts instead of droning.
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
  The test run checks it too (#211): `tests/net` built nights whose beds only fade out when the night is freed, so
  `after_test` calls `Audio.stop_all()` and `after` waits `Audio.wait_for_mixer()`. CI fails a test run whose log has
  `leaked at exit` or `still in use`. Another source in the same run was a test lambda that captured itself through
  an array (`chain[0] = func ...`): a cycle nothing frees, which kept the test script in use; the test cuts it.
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
- **The exit leak check failed a passing suite at random** (#487; main's ci twice, #402 and #462 once each: 4 objects
  and 2 resources, 8 and 2, 1 object, every test green). Whatever voice was playing or just stopped when the test run
  quit was still held by the audio server: one Ogg voice is exactly 4 instances (the stream, its packet sequence and
  the two playbacks) and 2 resources (the stream and the sequence). A suite cannot wait for the mixer after the last
  test, since GdUnit quits itself, so the wait moved to the end of the process: `AudioService._exit_tree` of the
  autoload calls `drain_mixer_blocking()`, the blocking twin of `wait_for_mixer()` (the mixer runs on its own
  thread, so blocking the main thread for its few steps is safe). `tests/core/test_audio_quit.gd` runs a child Godot
  that starts the beds and two sounds and quits at once: leaked instances and resources every time before (16 and 6
  after `stop_all`), none after.
  (The earlier note that waiting in `_exit_tree` did not help was a fixed real-time wait; counting the mixer's steps
  does.) CI runs the night and the tests with `--verbose` and uploads `leaks.txt`, the engine's list of what leaked.
- **A bed never goes quiet**, so an onset detector on the raw level finds nothing: `analyze.py` compares the short-term
  level with its own median over a second either side.

## Weapons and the lot (#250)

Added in `tools/audio/weapon_recipes.py` (synthesised) and `tools/audio/elevenlabs.py` (generated), listened to by
`WeaponSounds`, `GrenadeSounds` and `WorldSounds` in `game/gameplay/night/`. The design is
[Sound](../design/audio.md); this is what was learned.

- **Hitscan has no tracer, so the report sells the shot.** The old shot was one file: a crack, a roar and a 120 Hz sine
  that rang for 0.3 s like a struck pipe (the spectrogram's bright line at the bottom). Each shot was then three voices
  (report, blast, tail) with their own variants, pitch and level (since #407 two: the report and the tail, see
  [Gun audio](gun-audio.md)) and the report's transient is the loudest thing in the first 10 ms. Before and
  after, rifle: `rifle_before` against `rifle_after` in the pull request's spectrogram.
- **Variation costs voices, so the groups have limits.** Tails 4, impacts 6; the SMG's tail has a 0.22 s cooldown.
  Thirteen SMG shots a second still start the report every time.
- **Reload steps from the reload's motion (#683).** The steps are events of the weapon's `ReloadMotion`
  (`gameplay/player/reload/<id>.tres`) at shares of the reload, so they stretch over the weapon's own `reload_time` as
  the motion does and sound on the moment it draws them; `WeaponSounds.RELOAD` gives each step its sound. They play
  on a `SoundSchedule` the node steps, so a test checks every step 1 ms either side with no wall time. Before #683 they
  read the authored `Reload_<Class>` clips' frames (`ClipEvents`, now gone), which the night never played.
- **World impact versus flesh.** The server sends the pellets' end points in `shot_fired` and the zombie hits in a
  `damage_dealt` right after, so a pellet that ended short of the weapon's range is held until the next step and each
  hit claims the nearest end within 1.5 m; what is left struck the lot. A shotgun's eight pellets ricochet at most
  three times.
- **The generator follows its load.** The load is the draw of the lit circuits over all of them (`GeneratorLoad`,
  built from `fuel_changed`, `circuit_changed`, `fuel_empty`, `fuel_restored`); level and pitch are lerped by it and
  slew at 24 dB/s, so a breaker thrown is a change you hear take a second. A dry tank stops the loops; they restart
  on a refuel.
- **Generated clips (ElevenLabs Sound Effects, free tier).** Used for the shots' blasts (3 variants a gun; removed in
  #407, [Gun audio](gun-audio.md)), the generator's engine loop, power-down and power-up, and the door purchase; 17
  clips, 33 seconds, billed 40 credits a second (about 1,300 credits of the 3,500 allowed). Every file's prompt is in
  `game/assets/audio/eleven/LICENSE.md` with its licence: attribution required, not licensed for commercial use, to be
  replaced or relicensed before any commercial release (#252). Model `eleven_text_to_sound_v2` was used (the v3 model
  was not tried, to spare credits). What the files needed: levels from -22 to +4 dBFS once decoded (several above full
  scale), a lead-in of up to 0.3 s, and no seed, so a bad take is a new request. `elevenlabs.py` trims the silence
  before the sound, levels to -1 dBFS, fades the end and encodes Ogg; a file that exists is never fetched again, and
  `--reprocess` redoes only the levelling.
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
- **A pooled player kept the last sound's cap (#752).** `cap_near_level` set `max_db` only for a capped sound, so the
  dead's voices, boards, door and the till took the cap of whatever used their slot before (a gun's trim): the same
  voice read 2.5 to 15 dB lower after the guns than played alone (`zombie_growl_boss` -6.8 to -20.2 dBFS, `board_tear`
  -4.1 to -19.2) and moved with the gun trims. It now sets `max_db` on every play (`ENGINE_MAX_DB`, the engine's +3 dB,
  for a sound with no cap). Every other property a play can set was already set on every play (3D: stream, bus,
  `volume_db`, `pitch_scale`, `unit_size`, `max_distance`, the filter cutoff, position; flat: stream, bus,
  `volume_db`, `pitch_scale`; beds: stream, bus, `volume_db`, and `stream_paused` on release), and
  `test_near_cap.gd` checks the cap of every sound in the catalog after a rifle shot on the same slot. Measured with
  `tests/captures/audio_headroom.tscn --own=none --all-variants`: each sound's peak is now the same alone and after the
  guns, within 1.6 dB (the pitch draw). The close sounds' loudest files (`board_last`, `grenade_blast` -1.0,
  `door_open` -1.2 dBFS alone) left no room for a shot landing on them: that was #753, solved with a near cap on each
  ([gun-audio](gun-audio.md#close-sounds-under-gunfire)); the sharp ones (boards, door, debris blocker) were then
  limited in their recipes to come back over the beds ([#762](gun-audio.md#the-sharp-sounds-limited-in-their-recipe-762)).
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

## Footsteps (#239)

The dead's voices and feet (#248), the generator's hum and its start (`WorldSounds`) and the grenades (`GrenadeSounds`)
were already in the night when this was written; what was missing was the **players' feet**. The maintainer asked for
players' footsteps that can be heard but stay very subtle, never so loud that a player would want to mute them.

**How shooters mix a player's own steps.** There is no published figure (no developer talk or patch note gives
decibels), only what players and studios said when they got it wrong. Call of Duty: Modern Warfare's beta had your own
steps louder than the enemy's, players complained and the studio said it would lower the first-person footsteps and
raise other players' ([Charlie Intel](https://charlieintel.com/footstep-audio-changes-coming-to-call-of-duty-modern-warfare-in-beta/56122/),
[Kotaku](https://kotaku.com/the-footsteps-in-call-of-duty-modern-warfare-are-too-d-1839530724)); the Modern Warfare 2
alpha had the same complaint. Warzone 2 players showed that a loud one-off (a killstreak) can take the voice a distant
footstep needed, so step priority matters. The rule that falls out, and what this mix follows: **your own steps are
confirmation, not information, so they are the quietest steps in the mix; other players' steps are information, so they
are placed in the world and can be heard over your own.** Everything else here (the 12 dB under the guns, 5 dB over the
bed) is a number this project measured, not a standard.

**What was built** ([design](../design/audio.md#footsteps)): the soft set `step_own_*` (`tools/audio/step_recipes.py`:
heel and toe thump at 130 to 150 Hz plus a dull band, nothing above 3.2 kHz; centroid 420 Hz on asphalt, against 1,800 Hz
for the others' asphalt step; a thump at 90 Hz was tried first and is unheard on a laptop speaker), eight takes of every
step, `FootstepSounds` reading `Player.footstep` for a body here and `FootStride` for a player known only from frames,
and `FootSurface` (a ray to the floor and its material's pattern texture) for the ground.

**Measured** (`game/tests/captures/audio_footsteps.tscn`, Movie Maker mix, `tools/audio/step_levels.py`; shoulder
camera, the body's `local_input` and `capture_mouse` off; the bed is the crickets, the highway and the score at the
start of a night, median 100 ms RMS -35.5 dBFS):

| What | Over the bed, 100 ms RMS | Over the bed, peak | Mix LUFS of its 7 s |
| --- | ---: | ---: | ---: |
| Standing, the bed alone | 0 | 0 | -31.8 |
| Your own walk on asphalt (4.8 m/s) | +4.6 dB | +7.2 dB | -30.7 |
| Your own sprint (7 m/s) | +6.2 dB | +10.7 dB | -29.7 |
| Your own crouched creep (2.4 m/s) | +2.2 dB | +1.6 dB | -32.7 |
| Your own walk on gravel | +4.3 dB | +7.6 dB | -30.4 |
| A teammate passing at 6 m (the loudest of 20 steps) | +4.2 dB | | -31.4 |
| The starting pistol, 17 shots in 6 s | +16.5 dB | +18.8 dB | -20.7 |

So a walk's steps sit 12 dB under the pistol's shots and the walk adds 1.1 LU to the night; a sprint is 1.6 dB louder
and a crouch 2.4 dB quieter than a walk (the level model asks for 4 and 11.5 dB: the bed fills part of every 100 ms
window, and a crouch also steps less often). The mix peaked at -5.8 dBFS with no clipped sample.

**A whole night** (`audio_footsteps.tscn -- --autopilot --seconds=90`: the bot fights through the first rounds, shoulder
camera): 93 s, integrated -27.9 LUFS, peak -4.2 dBFS, no clipped sample; 81 of the player's own steps, all asphalt,
286 sounds started and 20 culled, **12 voices at once at the most** of the 44 the service has (32 positional, 12 flat).
The loudest night (28 zombies, four players) was not played here: the horde capture of #248 held 10 of 32 voices with
the horde at its most, and the steps add at most 8 positional and 2 flat (their group limits).

**What went wrong.**

- A step that is only a low thump is a step nobody hears on a phone or a laptop; the first soft set at 90 Hz had a
  centroid of 265 Hz. Keep the body above about 130 Hz and give it a low band of noise.
- `near_cap_db` matters for feet: the engine's inverse attenuation (`unit_size / distance`) lifts a step next to the
  listener up to the +3 dB ceiling, which would have made a teammate's step right beside you louder than a shot; the
  others' steps are held to their own level (`near_cap_db` 0).
- A test that walked from the middle of the generator yard walked into the generator (0.14 m in 1.5 s): the yard's
  open ground is a corner of its first slab, not its centre.
- The 0.12 s cooldown of the old `step_*` entries would drop one of two players' steps that land together; the
  stride already limits each player, so the cooldown is 0.
- A remote body has no on-the-ground flag in the frame (`NightServer._frame`), so `FootStride` infers flight from the
  height. A `grounded` field in the frame would be exact; it was left because the file is in an open pull request.

## The break's levels (#382)

The score 25% louder (+1.9 dB, -22 to -20.1) and the crickets 25% quieter (-2.5 dB, -16 to -18.5). Measured with the
pinned ffmpeg (`ebur128`, integrated loudness) on the files with the catalog's trims laid over them; Music and Ambience
share the default slider (80), so the buses add the same to both
(`ffmpeg -i f.ogg -af volume=<db>dB,ebur128=peak=true -f null -`; the mix is `amix` of the three with the score
ramped by `volume='pow(10,min(0,-60+20*t)/20)':eval=frame`):

| What | Before | After |
| --- | ---: | ---: |
| Score alone, 32 s | -34.5 LUFS | -32.6 LUFS |
| Crickets alone, 24 s | -38.2 LUFS | -40.7 LUFS |
| Score minus crickets, as heard | +3.7 LU | +8.1 LU |
| Score + crickets, 24 s steady | -31.8 LUFS | -31.4 LUFS |
| Score + crickets + highway, 24 s steady | -30.1 LUFS | -29.8 LUFS |
| The 5 s break as heard (score fades in at 20 dB/s), the three beds | -32.3 LUFS | -32.1 LUFS |

The score was already 3.7 LU above the crickets by the loudness meter (its file is much denser, so its catalog trim, 6 dB
under the crickets', understates it) and is now 8.1 LU above: the two moves add to the 4.4 LU the maintainer asked for,
while the whole bed moves only 0.3 to 0.4 LU. The break is not louder, it is the music over a quieter night.
**A 5 s break is short for a 3 s fade-in**: the score reaches its level after 3 s and starts its 2 s
fade-out at 5 s, so a break plays about 2 s of it at full level (a special round's 15 s plays it whole). A quicker fade
is a one-number change (`AudioService.BED_FADE_IN_DB_PER_S`) if the maintainer wants the music heard in full.

## The crickets, cut again (#781)

The maintainer asked for the crickets to be 50% quieter and to chirp at half the rate. The
crickets were already cut once (#382, -2.5 dB, above) and were still too much. Now `bed_crickets` is **-26 dB** and the
file has half the chirps a second.

**The base is the original -16 dB, and half means half as loud to the ear.** The first reading here took the 50%
from the level after #382 (-18.5) and as half the amplitude (-6 dB, to -24.5); the maintainer corrected both: the 50%
is from the original level (-16, before the cut above), and they chose half as loud to the ear. Perceived loudness
halves for every 10 dB (the usual rule of thumb: about 2^(dB/10), the sone scale), so half as loud is -10 dB, -16 to -26.
Half the amplitude is only -6.02 dB, which the ear hears as about 0.65 of the loudness, not 0.5. The chirp rate stays
half the original (12.71 of 25.38 a second).

**Why the first cut was not enough.** It was a number checked against numbers. #382's proof was a loudness table of the
crickets under the score; the one comparison with the highway read the crickets 2.6 LU *under* it, so by the meter they
were already quiet. But the crickets sing at 3.4 to 5.7 kHz and the highway bed has almost nothing there (-93.7 dBFS
against the crickets' -44.3: 49.5 dB), so the highway never masks them: what decides whether they are noticed is the
quiet night, not the other beds, and the meter's broadband gap says nothing about it. 2.5 dB is also about the smallest
step an ear notices, and the cut touched one of two things: the level, never the density (25 chirps a second scheduled
over the eight, 14 of them sung, in the highest band the ear is most sensitive to). Nobody put a quiet stretch of the
night in front of the cut and asked whether the chirping still stood out. Check next time: a bed that is a narrow tone
is judged in its own band against what is in that band, and by what it does (rate, bursts) as well as by how loud.

Numbers in the paragraph above that are read at -18.5 (the highway gap of 2.6 LU, the crickets' -44.3 dBFS band) are the
state the maintainer reacted to; the tables below put the original -16 beside the result.

**The rate.** The recipe keeps the draw it always made (`CRICKET_DRAW_HZ`, 2.0 to 4.2 chirps a second each, and the draws
of every later value) and keeps `CRICKET_RATE_SCALE` = 0.5 of the chirps: the same eight insects (pitch, bursts, place),
every other chirp gone, so each now sings 1.0 to 2.1 a second and a whole number of chirps in the 24 s loop (it still
loops cleanly). With the scale at 1.0 the recipe renders the old file bit for bit. Narrowing the draw to
`uniform(1.0, 2.1)` was tried first and drew another set of eight (10.8 chirps a second, not half of 25.4: a different
random stream, not the same crickets). **The file is normalised to its peak**: with half the chirps overlapping less, the
same -3 dBFS peak made each chirp 2 dB louder, so the entry's peak is now -5 dBFS (`CRICKET_PEAK_DB`) and the loudest
chirp in the file is as loud as before; `volume_db` is then the whole cut of a chirp (-10.0 dB from the original).

Measured with `tools/audio/cricket_levels.py` (the catalog's `volume_db` laid over the decoded file; ebur128 from the
pinned ffmpeg; the highway at its -18 dB; `check` pins the rate range and the whole chirps a loop):

| What | Original (-16 dB) | After (-26 dB) |
| --- | ---: | ---: |
| Chirps a second, all eight, scheduled by the recipe | 25.38 | 12.71 |
| Chirps a second sung (a chirp is dropped when its cricket is not singing) | 14.42 | 7.21 |
| Each cricket, chirps a second | 2.00 to 4.08 | 1.00 to 2.04 |
| Chirps a second told apart in the file (a lower bound, chirps overlap) | 8.08 | 5.00 |
| Loudest chirp (band envelope), dB | -27.8 | -37.8 (-10.0) |
| Crickets in 3.4 to 5.7 kHz, dBFS rms | -41.8 | -53.8 (-12.0) |
| Crickets alone, 24 s | -38.2 LUFS | -49.9 LUFS (-11.7) |
| Crickets against the highway bed, integrated | -0.1 LU | -11.8 LU |
| Crickets against the highway bed, in the crickets' band | +52.0 dB | +40.0 dB |
| Crickets + highway | -35.1 LUFS (+3.0 over the highway alone) | -37.9 LUFS (+0.2) |
| Score minus crickets, trims | -4.1 dB (the score at -22) | +5.9 dB (the score at -20.1) |

The crickets are still heard over the highway in the sense that matters: in their own band they stand 40.0 dB over it
(nothing there masks them), and at the unit distance they sit 18.7 dB under one's own footstep on wood (-53.4 against
-34.7). On the quiet night (below) they are 12 dB down in their band and the chirps come half as often. The second map has
no crickets.

**A quiet stretch of the night** (`game/tests/captures/audio_quiet_night.tscn`: the lot at dusk, the rules paused in the
intro, so only the beds play, 30 s through Movie Maker; `cricket_levels.py capture` reads its `night.wav`), 4 to 30 s,
through the real service and buses, at the original level and now:

| The whole mix | Original (-16 dB) | After (-26 dB) |
| --- | ---: | ---: |
| Mix, integrated | -35.0 LUFS | -36.4 LUFS |
| Crickets' band 3.4 to 5.7 kHz, dBFS rms | -43.6 | -55.6 |
| Loudest chirp in the band, dB | -29.7 | -39.7 |
| Chirps a second told apart | 8.12 | 5.12 |

The mix moves only 1.4 LU (the highway is most of its energy) and the crickets' band 12 dB: the cut is in the crickets,
not in the night. The spectrogram of the two nights is attached to the pull request.

## The soldier's voice (#384)

The player's character talks like a person in the moment: 115 takes of 21 moments ("Reloading, cover me!", "Jeez, that one
nearly had me, back off, back off!"), played by `SoldierVoice` (design: [the soldiers' voices](../design/audio.md#the-soldiers-voices)).
The maintainer listened to samples and approved the configuration below, which is not changed here.

| What | Value |
| --- | --- |
| Service | ElevenLabs text to speech, free tier (`POST /v1/text-to-speech/{voice_id}`, `mp3_44100_128`) |
| Model, voice | `eleven_v4`; Brian, the premade `nPczCjzI2devNBz1zQrb` |
| Settings | `stability` 0.0, `similarity_boost` 0.8, `style` 0.6 (the low stability is what lets the tags act) |
| Recipe | `tools/audio/elevenlabs_voice.py` reads the lines and settings from `tools/audio/soldier_voice.json`: `plan` (the table and the characters to request, refusing over `--budget`), `generate` (one request per take, never twice: the raw mp3 and its request are kept in a cache folder), `encode` (trim, level to -20 LUFS, peak limit -1 dBFS, Ogg Vorbis q3, mono), `check`, `credits` |
| Output | `game/assets/audio/voice/soldier/<moment>_<n>.ogg`, `manifest.json` (file to moment, text, characters, model, voice, settings, seed, seconds, loudness before levelling), `LICENSE.md` |
| Takes | 115: 113 requested once each, and the two samples the maintainer approved (`round_clear_1`, `streak_1`) encoded like the rest |

### How the lines were written

The first sample failed ("Reload... catch your breath" read like a narrator: [lesson](https://ryubara.github.io/gdstudio/gamedev/audio/voice-lines/#2-writing-the-lines)).
Each line is first person, with contractions, a filler or a breath, an exclamation where it fits, and uneven
length (10 to 139 characters); the feeling is in the words and the v4 tag (`[breathing hard]`, `[laughs]`,
`[shouting]`) only adds to it. A test fails a line that is a bare caption (`test_soldier_voice_catalog.gd`). Barks run
0.8 to 3.8 s (a reload 2.4 s on average, a kill 1.9 s, a hurt 2.2 s), the calm moments longer (a cleared round 6.6 to
8.5 s, the idle musings 5 to 7 s). The lines are original; no other game's line is quoted or paraphrased.

### Characters, and what the check cost

| Step | Free-tier characters used (of 10,000) |
| --- | ---: |
| Before | 2,248 |
| After the 113 requests | 7,302 (5,054 billed for 5,738 written) |
| After transcribing every take | 8,278 (976 for the 115 transcripts) |
| Left | 1,722 |

- **Audio tags are not billed.** The 113 lines are 5,738 characters with their tags and 4,674 without; the account was
  charged 5,054. The plan counts tags (the safe number); the bill is lower.
- **Transcribing costs credits.** `POST /v1/speech-to-text` (`scribe_v1`) takes about 8.5 characters of the same quota
  for a take of about 4 s (976 for 115). A recipe that checks every take must budget for it; the transcripts are kept in
  the cache and never fetched twice.
- **Tags performed, not spoken.** Scribe writes the sounds it hears in brackets (`[laughs]`, `[sighs]`, `[grunts]`); a tag
  the voice read out comes back as plain words. Across the 115 takes no tag word appeared outside brackets and no line lost
  more than a word or two (`check` flags both): 0 of 115 failed, so no retake was spent. Some tags are heard as a
  different sound than written (`[sharp inhale]` as `[inhales]`, `[through gritted teeth]` as nothing, `[grunts]` alone
  for `[pained grunt] Ugh!`), which is acceptable for a bark.
- **Licence.** Free-tier output is for non-commercial use and needs attribution: the same as the other ElevenLabs sounds,
  so it joins [#252](https://github.com/Ryubara/deadnight/issues/252) (replace or relicense before any commercial
  release). The Credits screen names ElevenLabs for the voice too.

### Measured in a night capture

Run with `game/tests/captures/audio_soldier_night.tscn` under Movie Maker (15 frames a second): the autopilot plays through
the shoulder camera (`local_input` and `capture_mouse` off) for 45 s, then the moments it does not reach are told to the
soldier one after another (7 s apart). The Voice, Effects and Ambience buses are recorded as stems with an
`AudioEffectRecord` each, and `tools/audio/voice_report.py` measures them (BS.1770 loudness, `pyloudnorm`).

| What | Result |
| --- | --- |
| The run | 111 s, 15 voice lines of 15 moments, 20 shots, mix peak -3.1 dBFS, 0 clipped samples, integrated -24.4 LUFS |
| Stems over the run | Voice -23.3, Effects -24.7, Ambience -33.3 LUFS |
| A voice line while it speaks (first 1.2 s) | mean -24.0 LUFS (-27.8 to -21.7) |
| A shot (Effects stem, 0.4 s from it) | mean -19.2 LUFS (max -17.4) |
| The beds away from gunfire | mean -34.6 LUFS |
| The voice against the guns / the beds | -4.8 LU / +10.6 LU |
| The voice against everything else playing in the same 1.2 s | +8.7 LU |

The voice is heard clearly over the beds and the fight but never over the guns: a line is 5 LU under the burst of a
shot. The takes are levelled to -20 LUFS (their loudness before levelling ran from -33.5 to -16.7 LUFS, the whispered lines
lowest), `SoldierVoiceCatalog.VOICE_DB` is -4 dB and the player's own voice another -2 dB (`LOCAL_DB`); those two numbers
are the whole trim. Nobody has listened to it in the game: the maintainer's ears decide whether it wants another dB.

- **Stems from a capture.** `AudioEffectRecord` on a bus works under Movie Maker: add it to each bus, set
  `set_recording_active(true)`, and `get_recording().save_to_wav(...)` at the end gives each bus's own mix, so a level can
  be compared across kinds of sound without guessing from the master. Remove the effects before quitting, or the engine
  reports a resource still in use at exit.
- **The frame size is the project's.** `--write-movie` ignores `--resolution` and a window resized in the script: the frames
  are 1920 x 1080 whatever is asked (a night at that size ran at about 2 frames a second on a busy machine).
- **`obj == false` is an error.** The service returns a node or null; a test double returns `true`. Comparing a node with
  `false` raises `Invalid operands 'Object' and 'bool'` at run time, not at parse time: test with `is bool`.

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

- **Answered (#88):** the web build plays 44 voices without crackle, and plays them as samples, which ignore bus effects
  and the distance filter: [Audio in the browser](web-export.md#audio-in-the-browser). The pool stays at 32 and 12.
- **Answered (#88):** the lot's walls are on physics layer 2 and the night sets `Audio.occluder_mask` to it
  (`test_night_occlusion.gd`).
- The sting's duck (and the rear cue and occlusion low-pass) do not work in the browser. The bus volume does, so the duck
  could be a bus volume on the web; not done.

## The female soldier's voice (#679)

The same 20 moments and 115 takes as the male soldier, in a female voice, for the character choice
([#678](https://github.com/Ryubara/deadnight/issues/678)). `SoldierVoiceCatalog` builds both sets from the one moments
table and the one mix (male `vox_<event>_<n>` from `voice/soldier/`, female `voxf_<event>_<n>` from
`voice/soldier_female/`); a player speaks with the `voice` of their frame entry (`female`, else male).

| What | Value |
| --- | --- |
| Service | ElevenLabs text to speech, **Free tier** (a new account, 10,000 characters a month), `mp3_44100_128` |
| Model, voice | `eleven_v4`; **Sarah**, the premade `EXAVITQu4vr4xnSDxMaL` ("Mature, Reassuring, Confident", young, American) |
| Settings | the male soldier's: `stability` 0.0, `similarity_boost` 0.8, `style` 0.6 |
| Recipe | `tools/audio/elevenlabs_voice.py --voice female` reads `tools/audio/soldier_voice_female.json`; same `plan`, `generate`, `encode`, `check`, `credits` |
| Output | `game/assets/audio/voice/soldier_female/<moment>_<n>.ogg`, `manifest.json`, `LICENSE.md` (Free tier: attribution, no commercial licence) |

- **Why Sarah.** On the Free tier the API serves the premade voices only (the account lists 21: Brian, Adam, Roger,
  Harry and others male; Sarah, Laura, Jessica, Alice, Matilda, Bella, Lily female). A soldier who talks under stress
  needs a steady, confident voice that the low stability can then move: Sarah ("mature, reassuring, confident"), not
  Laura ("sassy, quirky"), Jessica ("playful, bright") or Lily ("velvety actress"). A different premade voice is one
  line in the json and a re-run.
- **The lines.** The male set, kept where it fits a woman as it is (most lines: "Reloading, cover me!", "I'm dry, I'm
  dry!") and changed where it named a man ("Come to papa" is "Come to mama", "cheer a guy up" is "cheer a girl up",
  "big boy coming through" is "big girl", "Thanks, man" is "Thanks"). The two takes the maintainer approved for the male
  voice (`round_clear_5`, `streak_7` here) were not samples for her, so every one of her 115 lines was requested.
- **Levelled like the male takes**, by the same recipe (-20 LUFS, peak limit -1 dBFS). Measured on the decoded files
  with `tools/audio/analyze.py report` and BS.1770 loudness (`pyloudnorm`):

| 115 takes each | Male | Female |
| --- | ---: | ---: |
| Integrated loudness, mean (min to max) | -20.19 LUFS (-20.89 to -19.93) | -20.16 LUFS (-20.68 to -19.89) |
| Spread (standard deviation) | 0.12 LU | 0.11 LU |
| Per moment, female minus male | | -0.10 to +0.11 LU |
| Peak, mean (highest) | -3.5 dBFS (-1.0) | -4.5 dBFS (-0.8) |
| Clipped samples | 0 | 0 |
| Length, mean (longest) | 3.75 s (8.5) | 3.85 s (8.3) |
| Spectral centroid, mean | 3,341 Hz | 3,103 Hz |

  Her takes sit within 0.1 LU of his in every moment and peak a little lower on average; the same
  `VOICE_DB` (-4 dB) and `LOCAL_DB` (-2 dB) trim therefore holds, and the night-capture numbers above apply to both.

- **Check.** Every take was transcribed (Scribe): 0 of 115 flagged (no tag spoken, no line missing words), so no retake.
- **Characters.** 6,457 of the 10,000 for the month were used for all of it, 3,543 left (read from
  `/v1/user/subscription` after the last request). That is the only reliable number: **the account's counter lags the
  requests by minutes**. It read 3,419 right after generation, 6,333 after the transcripts and 6,457 a little later.
  The 115 lines are 5,953 characters written and 4,919 without tags; the male set billed 5,054 for 4,674 spoken, so
  hers was about 5,300 and the Scribe check about 1,150 (the male one cost 976). The split is an estimate, the total
  is measured. The next retake budget is 3,543, enough for about 60 average lines.
- **Cost of two sets in the game.** The catalog now holds 230 voice takes; the warm-up and the background preload load
  every sound, so both sets are loaded (4.5 MB of Ogg each). Loading only the voice a night uses is a follow-up for the
  character choice (#678), which knows who speaks.
- **Not heard.** No agent listens; the numbers above are the proof, and the maintainer's ears decide whether Sarah
  wants another dB or another voice.

## The progression voice lines (#1063)

Eight moments of three takes each in both voices, for the progression events of
[the design](../design/progression.md#voice-lines): `level_up`, `tier_up`, `unlock`, `challenge_done`, `poster_set`,
`card`, `emblem` (an emblem or a frame) and `first_game`. 48 files (24 a voice), the male takes of `voice/soldier/` and
the female takes of `voice/soldier_female/` (139 files each now), the same recipe, voice, model and settings as the two
soldiers above; the lines are in `tools/audio/soldier_voice.json` and `soldier_voice_female.json`, appended after
`idle` so that every earlier take keeps its file name and its seed.

- **Made on the free tier.** The maintainer decided on 2026-11-04 to generate them before the plan with commercial
  rights was bought, and to buy that plan afterwards. The subscription endpoint read `tier: free` before and
  after; every new manifest entry carries `"plan": "free"` and `"generated": "2026-11-04"`
  (`elevenlabs_voice.py encode --plan free --generated 2026-11-04`), and both `LICENSE.md` files list the 24 prompts.
  **They are not licensed for commercial use: regenerate them under the commercial plan before any release (#252).**
- **Lines.** Short in-world cheers of 32 to 52 characters (1,018 a voice, 42 on average; the older lines average 50),
  checked by reading aloud: "[excited] Level up! Now we're cooking!", "[shouting, triumphant] New rank! Hear that
  brass?!", "[smug] Challenge done. Easy as pie.", "[delighted] The whole set! Every poster on the wall!", "[laughs]
  Day's first game. Bonus time!". The same words in both voices (no line names a sex); the delivery differs.
- **Check.** Scribe on all 48: 0 flagged, no tag spoken, no word missing.
- **Characters.** 6,457 used before, 8,661 after (read once after a pause) for 48 requests, their check and nothing
  else: 2,204 of the 3,000 the maintainer allowed for this work, 1,339 left in the month (resets 2026-12-03). The lines
  are 2,036 characters written (1,018 a voice); audio tags are not billed. A budget test holds the new events to
  1,300 a voice.
- **Rank.** 61 to 64, in the band between the chatter and the urgent lines: [design](../design/audio.md#the-soldiers-voices).
  One new tuning value, `urgent_priority` 65 in `NightSoundTuning`: a line of that rank or more cuts a cheer that is
  speaking (the director's 25-rank margin alone would have left a boss waiting for a celebration).
- **In a fight.** `game/tests/captures/audio_progression_voice.tscn` (modes `listen`, `beside`, `fight`) plays the cheers
  through the real service; `tools/audio/voice_clip.py` makes the `.mp4`s with the sound in them. In a 60 s autopilot
  night with all eight told to the soldier (5 s apart, 12 shots): a cheer measures -20.7 to -25.1 LUFS in its first
  1.2 s (mean -23.7 in both voices; the other lines of that night -23.1 to -24.0, a round start -27.8 and -31.9), the
  shots -17.8 (male run) and -17.7 (female run), the beds -36.2: a cheer sits 5.9 to 6.0 LU under the gunfire and 12.5 LU
  over the beds, the soldier's usual place (5 and 10.6 LU for the first capture). The female run plays the night's lines
  with her take set through a wrapper on `SoldierVoice.play` (the night's player is the male character).
- **Wired to the server's events (#1063).** `SoldierVoice` hears `level_up`, `tier_up` and `unlock_earned` of `XpAward`
  on every client (`ClientState.event_received`) and cheers the player the event names: flat for the player at the
  screen, from where the soldier stands for a teammate. The events of one player come together (a level, its tier, what
  it unlocks), so `NightSoundTuning.cheer_window` (0.25 s) holds them and one cheer is said: the tier over an item
  (`SoldierVoiceCatalog.CHEER_OF_SLOT`: a card, an emblem or frame, else an unlock) over the level, so a level that
  gives an item is cheered for the item. Players who level up in the same window are cheered one after the other from a
  queue (the first version asked the director for each at once and the second was dropped:
  [kit lesson](https://github.com/Ryubara/gdstudio/pull/599)). A bot has no level and no event.
- **`challenge_done` wired (#1135).** `ChallengeAward`'s event (keys `player_id`, `id`, `family`, `text`, `target`,
  `rung`, `rungs`, `reward`) is one row of `SoldierVoiceCatalog.CHEER_OF_EVENT` and `SoldierVoice` hears it with the
  others. Its weight is 2, level with an item and under a tier: the challenge's own reward is XP, which can pay a level
  in the same window (the challenge is told first, then the level), and a challenge that levels you up is cheered as
  the challenge, whichever event came first. Takes: 3 in each voice (`challenge_done_1..3.ogg`, the line after the
  record scratch), already made. Recorded through the real service in a solo night (`audio_progression_voice.gd
  --challenges=5+,12,13.2,20`): a challenge and its level together are one line at 5.33 s; two challenges 1.2 s apart
  are two lines, the second held for the first and its 2 s cooldown (said at 15.27 s). Heard over the night the
  segments measure -22 to -24 LUFS with the beds and the gunfire, peaks -6.5 to -8.9 dBFS. The weight is a design
  call the maintainer has open.
- **Tests.** `tests/net/test_progression_voice_online.gd`: four clients over a real WebSocket, a level up of player 1
  is played by all four (hers flat, the others where she stands) once each, a level that opens a tier and gives an
  item is one tier cheer on every client, and four kills that finish a challenge are one `challenge_done` line on
  every client (it fails with the row removed). `tests/night/test_soldier_voice.gd`: the slot table, a burst of
  events as one cheer, a challenge over the level it paid and under a tier, two players one after the other, a cheer
  held behind a reload, a downed player's dropped.
- **In a night.** `audio_progression_voice.tscn --mode=fight --account=420 --told=0` plays a night where the account
  holds 420 XP and the night pays the rest: the rules told level 6, its tier and its unlock together at 4.07 s and the
  soldier said `tier_up` take 1 at 4.27 s (0.2 s later); level 7 and its unlock at 38.40 s gave `unlock` take 1 at
  38.60 s (the director's history is in the pull request). One cheer each. No agent
  listens; the maintainer's ear decides the takes.
