# Gun audio

Why the guns sounded "distancy", thin and not alike from shot to shot (the maintainer, playing, issue #407), what was
measured, what changed, and the rules every firearm follows now. The sounds themselves are
`tools/audio/weapon_recipes.py`; how they are played is `WeaponSounds` and `ArmsCatalog`; the design is
[Sound](../design/audio.md).

## What "distancy" was

Measured on a recording of the real shot through `WeaponSounds`, the audio service and the buses, the listener where the
shoulder camera sits (2.7 m behind the muzzle), by `game/tools/bench/audio_gun_bench.tscn` and
`tools/audio/gun_levels.py`. Before the change:

- **Not the 3D attenuation.** Every gun already had `near_cap_db` 0, so the engine's inverse-distance boost (14 m
  `unit_size` over 2.7 m, +14 dB) was held to the trim: no distance loss, no low-pass (the attenuation filter only acts
  when the multiplier falls under 1), no occlusion (the night sets no occluder mask), no reverb or effect on the
  `Effects` bus. The own shot was slightly panned (left minus right +0.6 dB).
- **But a centred 3D voice costs 6 dB.** The shooter's own gun was a 3D voice at the muzzle; flat, the same trim is 6 dB
  louder (the 3D pan law), which is what the 3D shots had been giving away.
- **The shot was mostly room.** The report was 50 to 100 ms of crack with nothing under 120 Hz (band energy 25 to 35 dB
  under the loudest band for the revolver, SMG and rifle), and two layers of room followed it: a generated blast of 0.6
  to 1.6 s with the room baked into the file and a first 20 ms 10 to 20 dB under its peak, and a tail. The share of the
  shot's energy that arrives in its first 50 ms was 0.33 for the tommy gun (0.70 revolver, 0.85 rifle, 0.72 shotgun):
  two thirds of what the player heard was the room answering, which is what a shot a long way off sounds like.
- **Quiet.** The tommy gun's report was trimmed -6 dB and its mix peak was -10.6 dBFS; the guns peaked -5 to -13 dBFS in
  the mix, 20 dB or more under full scale, against a night bed at -35 LUFS.
- **The pitch wandered.** Each of the three layers was shifted by its own random amount up to 0.6 to 1.0 semitones
  (the SMG's report 0.8), on top of five variants whose synthesis moved the thump and the crack by 10 to 15 percent.
  Measured across one burst, the thump's pitch spread was 2.0 to 3.4 semitones and the loudness of consecutive shots
  differed by up to 5.8 dB (tommy gun).

## The rules

One rule for every firearm voice (report and tail of the revolver, SMG, rifle and shotgun, and the flare gun),
pinned by `game/tests/night/test_gun_audio_rules.gd`:

| Rule | Value | Where |
| --- | --- | --- |
| The shooter's own shots play flat (no 3D voice, no pan, no distance term) | always | `WeaponSounds._on_shot` |
| A stranger's shots play from the muzzle, held to their trim up close | `near_cap_db` 0 | `ArmsCatalog` |
| Pitch shift of a voice | within +-0.15 semitones (about 1 percent) | `ArmsCatalog.FIREARM_PITCH_SEMITONES` |
| Level wobble of a voice | within +-0.5 dB | `WeaponSounds.LEVEL_JITTER_DB` |
| Variants of a report differ in their noise, not their note | frequencies within +-2 percent | `weapon_recipes.FREQUENCY_SPREAD` |
| A shot is this far over the night's beds (one shot's loudest 400 ms / a two second burst) | 14 LU / 17 LU | `test_gun_audio_rules.gd` |
| Nothing relies on a bus effect for its power or its headroom | the web build plays samples, which ignore them | the files and the trims |
| No shot or burst gets closer to full scale than | -1 dBFS | the trims |

## What changed

- **The report is the whole close shot.** `report()` in `weapon_recipes.py`: a click, a crack, a roar that darkens, a
  bark in the middle of the spectrum, a falling thump and a low note under it, driven hard together so the file is
  dense up to its peak, with only a ground reflection 7 ms behind (size without a room). The room is the tail, a voice
  of its own, shortened, darker and 14 dB under the report.
- **Two voices, not three.** The generated blasts are gone (their room was the distance); 12 ElevenLabs clips and their
  licence rows are removed, which also shrinks what #252 covers. A shot starts two voices instead of three, which helps
  the browser too (`docs/research/kill-spike.md`).
- **Own shots are flat.** `WeaponSounds` plays the shooter's own report and tail with no position.
- **Trims.** Revolver -1, SMG -2, rifle -1, shotgun -1 (the strongest: its file is the longest and lowest), flare gun
  -2 dB; tails 14 dB under their report.
- **The flare gun** gets the same treatment (crack, bark, thump, then the hiss).

## Measured

RESULTS

## Browser

BROWSER

## Reading the numbers

- Loudness is ffmpeg's `ebur128` on the pinned ffmpeg: the integrated loudness of the 1.6 s around a single shot and of
  the 3.2 s of a two second burst and its tail, and the loudest momentary (400 ms) value of the single shot. The beds are
  the night's crickets and highway, steady, after a four second settle.
- The band table is the spectrum of the first 300 ms of the single shot in dB under its strongest band.
- "Shot-peak spread" is the largest minus the smallest peak of the burst's shots as recorded; "low-pitch spread" is the
  strongest bin between 40 and 400 Hz of each shot's first 60 ms, largest over smallest in semitones. The applied pitch
  and level are what the audio service gave each voice (the bench logs them).
- Nobody can listen here: the sound is judged by these numbers, and the clips on the pull request are for the
  maintainer's ears.
