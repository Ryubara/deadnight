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
| A gun that fires without a break peaks no closer to full scale than (the flare gun, one shot in a long while: -1 dBFS) | -4.5 dBFS | the trims (#718, [below](#headroom-under-other-sounds)) |
| Another sound landing on that gun's shots (a reload, a teammate's gun, a zombie's voice, a door) | no sample over -1 dBFS | the same trims; `tests/captures/audio_headroom.tscn` |

## What changed

- **The report is the whole close shot.** `report()` in `weapon_recipes.py`: a click, a crack, a roar that darkens, a
  bark in the middle of the spectrum, a falling thump and a low note under it, driven hard together so the file is
  dense up to its peak, with only a ground reflection 7 ms behind (size without a room). The room is the tail, a voice
  of its own, shortened, darker and 14 dB under the report.
- **Two voices, not three.** The generated blasts are gone (their room was the distance); 12 ElevenLabs clips and their
  licence rows are removed, which also shrinks what #252 covers. A shot starts two voices instead of three, which helps
  the browser too (`docs/research/kill-spike.md`).
- **Own shots are flat.** `WeaponSounds` plays the shooter's own report and tail with no position.
- **Trims.** First revolver -1, SMG -2, rifle -1, shotgun -1 (the strongest: its file is the longest and lowest), flare
  gun -2 dB, tails 14 dB under their report. Now (#718, [headroom](#headroom-under-other-sounds)) the reports sit at
  revolver -6.5, SMG -6.5, rifle -6.5, shotgun -7.0 and flare gun -1.5 dB, the tails 14 dB under.
- **The flare gun** gets the same treatment (crack, bark, thump, then the hiss).

## Measured

Native, the shooter's own shots, the bench at 60 frames a second (`tools/audio/gun_levels.py`, the pinned ffmpeg).
The night's beds alone measure -35.3 LUFS before and -35.2 after (the same beds). Before, the shot was three voices at
the muzzle (3D, 2.7 m from the camera); after, two voices, flat.

| Gun | Loudest 400 ms of a shot (LUFS) | Burst, 2 s (LUFS) | Peak of a shot / of a burst (dBFS) |
| --- | --- | --- | --- |
| Revolver | -21.9 to -14.0 | -20.5 to -12.5 | -6.5 / -5.6 to -2.2 / -1.5 |
| Tommy gun | -28.2 to -16.4 | -24.2 to -9.4 | -10.6 / -10.1 to -2.8 / -1.5 |
| Rifle | -17.9 to -13.3 | -18.7 to -14.6 | -5.2 / -3.3 to -1.9 / -1.9 |
| Shotgun | -16.3 to -11.8 | -15.7 to -12.5 | -6.2 / -3.2 to -2.9 / -1.5 |
| Flare gun | -30.4 to -16.4 | -31.7 to -17.6 | -13.3 / -13.0 to -2.5 / -2.7 |

Read "a to b" as before to after. Over the beds now: one shot 19 to 23 LU, a burst 18 to 26 LU (the test asks 14 and
17).

| Gun | Energy in the first 50 ms | Centroid (Hz) | Pitch given to the report (semitones) | Level given (dB) | Burst peak spread (dB) | Burst thump-pitch spread (semitones) |
| --- | --- | --- | --- | --- | --- | --- |
| Revolver | 0.70 to 0.96 | 1474 to 2985 | -0.51..+0.30 to -0.13..+0.09 | -4.0..-2.4 to -2.9..-2.1 | 2.0 to 1.4 | 2.07 to 0.58 |
| Tommy gun | 0.33 to 0.99 | 1452 to 3019 | -0.66..+0.75 to -0.15..+0.13 | -7.2..-4.9 to -3.0..-2.0 | 5.8 to 1.9 | 3.41 to 1.14 |
| Rifle | 0.85 to 0.85 | 1751 to 2781 | -0.32..+0.56 to -0.13..+0.08 | -3.9..-1.9 to -3.9..-3.1 | 2.1 to 1.1 | 2.15 to 0.71 |
| Shotgun | 0.72 to 0.58 | 1814 to 2514 | -0.58..+0.60 to +0.01..+0.10 | -2.5..-1.4 to -3.5..-2.5 | 1.9 to 0.7 | 2.54 to 0.49 |
| Flare gun | 0.95 to 0.99 | 2144 to 3103 | none to -0.08..+0.14 | none to -1.4..-1.3 | none to 2.0 | none to 0.28 |

- The shotgun's first-50-ms share falls because its report is now long and low (0.4 s of boom): the share of a long
  sound is not the measure for it, its loudness and peak are.
- The burst's pitch figure is the strongest bin between 40 and 400 Hz of a 60 ms piece, so it includes the bin
  resolution (about 0.3 semitones at 100 Hz); the applied figures are exact.
- Where the energy sits, in dB under the strongest band (20-60, 60-120, 120-250, 250-500, 500-1000, 1000-2000,
  2000-4000, 4000-8000 and over 8000 Hz), before and after: the revolver, SMG and rifle had almost nothing under
  120 Hz (-25 to -22 dB in the 20-60 Hz band, -13 to -4 dB in 60-120 Hz) and now carry 60-250 Hz at the top of the
  spectrum; the shotgun keeps its sub at the top. See `spectrograms_before_after.png` on the pull request (a
  log-frequency spectrogram of each gun's single shot, before on the left).
- The own shot is flat now: left minus right 0.0 dB (+0.6 dB before), no distance term.
- The whole night, `audio_arms_tour.tscn` (a fight with every weapon, buys, a grenade, the generator; 69 s): mix
  peak -0.5 dBFS, 0 clipped samples, with the guns this loud (before the change the same tour peaked at -0.4).
- Without a limiter, nothing clips: every shot and burst peaked at -1.5 dBFS or lower (the trims were -2.5 to -3.5 dB),
  and the Ogg of a driven file decodes up to 1.5 dB over its PCM peak. That left too little for a second sound: see
  [headroom](#headroom-under-other-sounds), where the trims are 3 to 4 dB lower.

## Headroom under other sounds

Issue #718: the player's own tommy gun, fired without a break, peaked at -1.5 dBFS alone, so a reload, a teammate's gun
or a zombie's voice landing on a shot took the mix to 0 dBFS.

**Decision: lower the guns' trims, no limiter.** A hard limiter on Master holds its ceiling natively and does nothing in
the web build, which plays samples (`tools/bench/audio_limiter_probe.tscn`, the tommy gun fired without a break, a
limiter at -9 dB on Master; web through `tools/web_smoke/limiter_web.py`, headless Chromium with a tap on the page's
output):

| Phase | Native (Movie Maker), peak dBFS | Web (browser tap), peak dBFS |
| --- | --- | --- |
| Nothing on the buses | -6.0 | -6.0 |
| Hard limiter on Master, ceiling -9 dB | **-9.0** | **-6.0** (ignored) |
| Limiter taken off again | -6.0 | -6.0 |
| Master turned down 9 dB | -15.0 | -15.0 |

(The web run's first phase read +1.8 dBFS while the page started: shots queued before the browser resumed its audio
played together; the phases after are the figures.) Only bus volume acts in both builds, so the gun's headroom is its
trim, and the mix stays a plain sum (the reload audibility measurement of #683 relies on that).

**What was set.** Report trims (tails 14 dB under): revolver -2.5 to -6.5, SMG -2.5 to -6.5, shotgun (the
double-barrel) -3.0 to -7.0, each a 4 dB cut, and the rifle -3.5 to -6.5, a 3 dB cut (4 dB left its two second burst
16.7 LU over the beds, the test asks 17). The flare gun stays at -1.5: its report is a sharp crack (a crest factor of 20
dB: a 1.2 dB cut of its peak takes 2.5 dB off its burst's loudness, under the 17 LU), and it fires once in a long while.
A teammate's reload steps are lifted by 5 dB (`teammate_reload_db`, was 6): a rifle round step landed on a tommy gun
shot at -0.8 dBFS (4 samples over -1 dBFS) with 6, and with 5 every step of five weapons is still heard under a tommy
gun 6 m off ([design](../design/audio.md#reloads)). A cut in trim is a cut in gain: peak, RMS and loudness fall
together, the crest factor of a burst does not move.

**Measured**, `tests/captures/audio_headroom.tscn` through `WeaponSounds`, the audio service and the buses (60 frames a
second, a recording of the plain sum), `tools/audio/headroom.py`, the same capture on `main` (before) and with the
change (after). Each own gun fires without a break (at its rate of fire) for five cells: alone; a teammate 4 m ahead
reloads each of four weapons; a teammate 4 m ahead fires each of four weapons for a second; every zombie voice, one at
a time, a zombie 2 m ahead (and the boss); a door, boards, a blow, an impact, a grenade blast 4 m off, the till and a
debris blocker. Peak of the mix in dBFS, with the samples over -1 dBFS in brackets, before then after:

| Own gun | alone | + reload | + teammate's gun | + zombie voices | + lot's sounds |
| --- | --- | --- | --- | --- | --- |
| Revolver | -1.9 to **-5.9** | -0.4 (8) to **-4.0** (0) | 0.0 (68) to **-2.2** (0) | -0.1 (39) to **-4.0** (0) | -1.3 (0) to **-4.0** (0) |
| Tommy gun | -1.7 to **-5.7** | 0.0 (25) to **-1.2** (0) | 0.0 (286) to **-2.7** (0) | 0.0 (106) to **-3.6** (0) | 0.0 (56) to **-2.0** (0) |
| Rifle | -2.4 to **-5.4** | -1.3 (0) to **-3.5** (0) | 0.0 (50) to **-2.3** (0) | -1.2 (0) to **-4.4** (0) | -1.9 (0) to **-4.8** (0) |
| Shotgun | -1.6 to **-5.6** | -0.4 (17) to **-3.0** (0) | 0.0 (170) to **-3.0** (0) | 0.0 (113) to **-3.1** (0) | 0.0 (35) to **-2.3** (0) |
| Flare gun (trim unchanged) | -3.1 | -1.9 (0) | 0.0 (35) to **-0.2 (8)** | -0.1 (10) to **-1.3** (0) | -2.1 (0) to **-2.4** (0) |

Before, 14 of the 25 cells had samples over -1 dBFS, most of them at 0.0 dBFS; after, one: the flare gun's crack landing
on a teammate's revolver shot at -0.2 dBFS (8 samples, none at full scale), the one gun whose trim was not cut. The
worst of the others is -1.2 (the tommy gun under a teammate's reload) and -2.0 to -2.2 under a teammate's gun or the
lot's sounds. The sounds that landed peak, alone, before then after: a teammate's gun -4.6 to -5.1 then -8.0 to -9.5, a
reload step -5.8 to -12 then -6.8 to -13 (the SMG's magazine going in the loudest), a grenade blast -7.2.

The issue's own measure, `tests/captures/reload_under_fire.tscn` in its `mate` scene (a teammate reloads while the
player fires the tommy gun), for the five weapons reloaded: before -0.0 dBFS for the rifle (53 samples over -1 dBFS, 7
at full scale), -0.6 and -0.7 for the revolver and shotgun (5 and 2 samples over), -1.5 and -1.3 for the SMG and flare
gun; after -2.2 to -5.4, none over -1 dBFS.

**Punch is kept.** The cut is the same number of dB on every number, so the crest factor of the gun alone (peak minus
RMS) is unchanged: 11.1 dB for the tommy gun, 11.3 for the double-barrel, 14.6 for the revolver and 15.6 for the rifle.
Against the night's beds (-35.3 LUFS, `tools/audio/gun_levels.py`, now `tests/night/gun_levels.json`): one shot's
loudest 400 ms is 14.9 LU over the beds (tommy gun) to 19.5 (double-barrel), a two second burst 17.7 LU (rifle) to 21.9
(tommy gun), against the 14 and 17 the test asks. `test_gun_audio_rules.gd` now also asks every gun but the flare gun
to peak at -4.5 dBFS or lower.

**What this does not cover.** The matrix plays each zombie voice and lot sound once, in a pool that has already played
guns (the game's usual state). Two things make the close sounds louder than that, and both are follow-ups
(#752 and #753):

- *A pooled player keeps the last sound's `max_db`.* `AudioService.cap_near_level` sets it only for a sound that has a
  near cap, so after a gun (trim -2.5, now -6.5) used a slot, an uncapped sound (the dead, boards, the door) played in
  it is capped at that trim. The same zombie voices played alone peak 4 to 10 dB higher, and the dead, boards, doors
  and blows in the matrix fell 3.7 to 4.3 dB with the guns, whatever the change did to them (their balance against the
  guns stayed, against the beds it did not). Fixing it makes the dead's loud level the normal one.
- *The files of a sound differ by 3 to 9 dB in peak.* `--all-variants` plays every file of every zombie voice and lot
  sound, in a clean pool, under each own gun: the revolver, tommy gun, rifle and flare gun reach 0.0 dBFS (31 to 135
  samples over -1 dBFS in the zombie cell, 40 to 127 in the lot's), the shotgun 56 and 190. Solo, close, the loudest
  files peak at `grenade_blast` -1.0, `board_last` -1.1, `door_open` -1.9, `board_tear` -2.1, `zombie_attack` -2.2,
  `zombie_death` -3.5 and `zombie_groan_brute` -4.0 dBFS: as loud as the player's gun was, so one of them, or two,
  landing on a shot can still clip whatever the gun's trim.

## Browser

`tools/web_smoke/gun_levels_web.py` plays the same bench in headless Chromium (the web export plays sounds as samples)
and taps the page's audio output. The numbers are RMS and peak, not LUFS, taken over one second after each shot and
over the burst (software GL on a loaded machine, so the shots' timing is the browser's):

| Gun | Single peak / RMS (dBFS) | Burst peak / RMS (dBFS) |
| --- | --- | --- |
| Revolver | -2.2 / -25.3 | -1.6 / -22.0 |
| Tommy gun | -2.9 / -26.7 | -1.6 / -18.5 |
| Rifle | -2.0 / -24.4 | -2.0 / -23.4 |
| Shotgun | -3.0 / -22.4 | -1.5 / -21.5 |
| Flare gun | -2.5 / -26.2 | -2.7 / -26.8 |
| The night's beds alone | -22.8 / -43.8 | |

The browser plays the same shots at the same peaks as the native run (-1.5 to -3.0 dBFS), 17 to 26 dB of RMS over the
beds, nothing clipped, with no limiter: this is why the power and the headroom live in the files and the trims. (The
first run of this check failed with "Failed loading scene": the export leaves out `tests/`, so the bench lives in
`game/tools/bench/`.)

## Reading the numbers

- Loudness is ffmpeg's `ebur128` on the pinned ffmpeg: the integrated loudness of the 1.6 s around a single shot and
  of the 3.2 s of a two second burst and its tail, and the loudest momentary (400 ms) value of the single shot. The
  beds are the night's crickets and highway, steady, after a four second settle.
- The band table is the spectrum of the first 300 ms of the single shot in dB under its strongest band.
- "Shot-peak spread" is the largest minus the smallest peak of the burst's shots as recorded; "low-pitch spread" is the
  strongest bin between 40 and 400 Hz of each shot's first 60 ms, largest over smallest in semitones. The applied pitch
  and level are what the audio service gave each voice (the bench logs them).
- Nobody can listen here: the sound is judged by these numbers, and the clips on the pull request are for the
  maintainer's ears.
