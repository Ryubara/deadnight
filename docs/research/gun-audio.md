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
| Every firearm's shot or burst peaks no closer to full scale than | -4.5 dBFS | the trims (#718, [below](#headroom-under-other-sounds)); the flare gun's file too (#761, [below](#the-flare-guns-crack)) |
| Another sound landing on that gun's shots (a reload, a teammate's gun, a zombie's voice, a door) | no sample over -1 dBFS | the same trims; `tests/captures/audio_headroom.tscn` |
| A close sound (a voice of the dead, a board, the door, the blast) | its loudest file at most -9.8 dBFS 1.2 m ahead, what the loudest own gun leaves under -1 dBFS | a negative `near_cap_db` (#753, [below](#close-sounds-under-gunfire)) |

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
  revolver -6.5, SMG -6.5, rifle -6.5 and shotgun -7.0 dB, the tails 14 dB under, and (#761, a reshaped file) the
  flare gun -6.0.
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
16.7 LU over the beds, the test asks 17). The flare gun stayed at -1.5 then: its report was a sharp crack (a crest factor
of 20 dB: a 1.2 dB cut of its peak takes 2.5 dB off its burst's loudness, under the 17 LU); it is reshaped in
issue 761 ([below](#the-flare-guns-crack)).
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
| Flare gun (trim unchanged then; reshaped in #761) | -3.1 | -1.9 (0) | 0.0 (35) to **-0.2 (8)** | -0.1 (10) to **-1.3** (0) | -2.1 (0) to **-2.4** (0) |

Before, 14 of the 25 cells had samples over -1 dBFS, most of them at 0.0 dBFS; after, one: the flare gun's crack landing
on a teammate's revolver shot at -0.2 dBFS (8 samples, none at full scale), the one gun whose trim was not cut (solved in
issue 761). The
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
(tommy gun), against the 14 and 17 the test asks. `test_gun_audio_rules.gd` now also asks every gun
to peak at -4.5 dBFS or lower (every gun but the flare gun until #761).

**What this did not cover (both are done now).** The matrix plays each zombie voice and lot sound once, in a pool that
had already played guns. Two things made the close sounds louder than that: *a pooled player kept the last sound's
`max_db`* (a gun's trim capped the dead; fixed in #752, where every play sets it) and *the loudest files of the close
sounds peak at -1 to -5 dBFS by themselves* (#753, [next section](#close-sounds-under-gunfire)).

## Close sounds under gunfire

**The cause.** A close 3D sound sits at its player's `max_db`, +3 dB over its file when it has no `near_cap_db`,
whatever its trim, and the files are normalised to peak at -2 to -4 dBFS. Dead ahead that is 0 to 3 dB under the
file's peak: every zombie voice, the boards, the door and the blast peaked at -0.6 to -3 dBFS by themselves, as loud as
the player's own gun was before #718, and one landing on a shot (-5.5 dBFS alone) clips. #718's matrix played each once
in a pool that capped them (#752), so it did not show.

**The rule.** The highest sample of any file of a close sound, right beside the listener (1.2 m, where the cap and not
the distance sets the level), is at most what the loudest own gun leaves under -1 dBFS when the two peaks land
together (amplitudes add): `10^(-1/20) - 10^(-4.9/20)` is 0.32, **-9.8 dBFS** (the rifle's -4.9 in
`tests/night/gun_levels.json`; the capture's own gun alone is -5.4 to -5.9). It is pinned by
`tests/core/test_close_sound_levels.gd` from `tests/core/close_sound_levels.json`, which `tools/audio/close_levels.py`
measures from the capture's `--close` run. A table and not arithmetic on the files: how much of a file's peak reaches
the mix is 0 to 3 dB for a voice and 10 to 14 for a 70 ms click such as an impact, whose peak the distance low-pass
takes off. The test fails when a cap or a trim moves without a new measurement, when a row leaves no room, and when a
row is louder than its loudest file could be. No limiter: the web build ignores bus effects (above).

**What was set.** A negative `near_cap_db`: `volume_db + near_cap_db` is the most the sound gets however close, and from
where the cap stops holding it falls as it always did (a sound's far reach is the same). One cap for each sound, not
for each file: the files of a sound differ by about 1 dB in peak (the 3 to 9 dB the first sweep showed were mostly a
window that missed a late peak or caught the next sound). Twenty sounds changed (the impacts were already under
the rule). Peak of any file 1.2 m ahead, alone, and the loudest 400 ms of any (LUFS), before then after; the night's
beds are -35.3 LUFS:

| Sound | Trim | Cap before | Cap now | Peak before | Peak now | Loudest 400 ms before | now |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `grenade_blast` | +0.0 | none | -7.0 | -0.6 | -10.4 | -10.2 | -20.4 |
| `board_last` | +4.0 | none | -9.0 | -0.7 | -10.0 | -21.6 | -29.7 |
| `debris_clear` | +0.0 | none | -6.0 | -1.5 | -10.8 | -16.0 | -25.1 |
| `zombie_roar` | -7.0 | none | +1.0 | -1.5 | -10.5 | -7.0 | -15.8 |
| `zombie_growl_boss` | -6.0 | none | +0.0 | -1.6 | -10.0 | -10.2 | -18.9 |
| `zombie_shriek` | -5.0 | none | -1.5 | -1.7 | -10.2 | -6.8 | -15.8 |
| `board_tear` | +2.0 | none | -4.5 | -1.8 | -10.0 | -21.6 | -27.3 |
| `zombie_hurt` | -2.0 | none | -4.0 | -1.9 | -10.2 | -7.9 | -16.6 |
| `zombie_alert` | -2.0 | none | -4.5 | -2.0 | -10.2 | -9.4 | -19.0 |
| `till_ring` | -4.0 | none | +0.5 | -2.3 | -10.4 | -12.2 | -18.5 |
| `zombie_groan_brute` | -3.0 | none | -2.0 | -2.4 | -10.5 | -9.3 | -17.5 |
| `door_open` | -2.0 | none | -3.0 | -2.5 | -10.5 | -19.8 | -27.6 |
| `board_repair` | +3.0 | none | -6.5 | -2.6 | -9.9 | -23.4 | -30.0 |
| `zombie_death` | -2.0 | none | -3.5 | -2.6 | -10.2 | -7.3 | -15.5 |
| `zombie_groan` | -4.0 | none | -1.0 | -2.6 | -10.4 | -9.6 | -17.4 |
| `zombie_attack` | +0.0 | none | -4.5 | -2.8 | -10.0 | -12.5 | -19.7 |
| `zombie_groan_crawler` | -4.0 | none | -0.5 | -2.9 | -10.2 | -9.4 | -16.7 |
| `zombie_grunt` | -3.0 | none | -1.5 | -3.1 | -10.2 | -15.2 | -22.6 |
| `zombie_breath_brute` | -3.0 | none | +0.0 | -4.7 | -10.1 | -12.8 | -18.4 |
| `melee_hit` | +0.0 | none | -2.0 | -5.3 | -10.2 | -22.1 | -27.4 |
| `impact_flesh` | -3.0 | +0.0 | +0.0 | -16.7 | -16.7 | -36.1 | -36.1 |
| `impact_head` | -1.0 | +0.0 | +0.0 | -17.4 | -17.4 | -37.3 | -37.3 |

The dead's voices stay the cue they were: at 1.2 m they are -15.5 to -22.6 LUFS, 13 to 20 LU over the beds and where
one shot of a gun is (-15.8 to -20.4 LUFS, 15 to 19 LU over), 6 to 10 dB under their level before; the order among them
is the one the trims set. The boards, the door and the debris blocker are sharp (a crest factor of 16 to 23 dB), so
under a peak ceiling they came to -25 to -30 LUFS, 5 to 10 LU over the beds at 1.2 m (12 to 19 before): a loud crack
on a quiet night, not a loud noise (the next section brings them back). The cap holds only close up, so a board torn
across the lot is as it was.

### The sharp sounds, limited in their recipe (#762)

**What was done.** `tools/audio/limiter.py` (`limit_crest(x, crest_db)`, called at the end of the five recipes, not a bus
effect: the web build ignores those) holds the highest sample of a file `crest_db` over its loudest 400 ms with a smooth
gain curve (the gain each sample needs, cut to its minimum over 2 ms either side and then averaged over the same window,
so it never steps and never rises into a peak, which keeps the Vorbis encode from overshooting a flat top). The crack
comes down 6 to 10 dB and the body stays; the files are normalised lower by what was taken off (`peak_db`, so the far
level is the one it was) and `near_cap_db` is raised by the same, then moved to put the measured close peak back under
-9.8 dBFS. The nominal limits (dB over the loudest 400 ms) are 13 for a torn board, 10 for the last one, 8 for a
hammered one, 12 for the door and 11 for the debris blocker; the other sounds' files are untouched (the recipes' seeds
are the same, bit for bit). Crest factor of every file (highest sample over its loudest 400 ms, RMS): 15 to 23 dB before,
12.6 to 16.6 now (`test_the_sharp_sounds_have_a_limited_crack_in_their_files`).

**What was not obvious.** The give-back at 1.2 m is not the crest taken off the file. Before, the distance low-pass
took off much of a crack's peak (a click loses 10 to 14 dB close up), so the close peak of a sharp sound was already
under its file's; a limited file's highest sample is the body's, which the low-pass keeps. With the file's peak lowered
and the cap raised by the crest taken off (a first try, limits of 16, 11, 9, 13 and 13 dB) the close peaks read 2.8 dB
(torn board), 1.9, 1.2, 0.2 and 0.7 dB higher than before, three of them over the room, and the loudness had come
back by only 2.1 to 7.7 dB. So the limits were cut again (13, 10, 8, 12, 11), the file levels and caps set from the
measured peaks, and a second capture put every row at most -9.9 dBFS. The close crest (peak minus loudest 400 ms) is
11.4 to 14.7 dB now, 14 to 20 before. Read the close peak again after limiting: the old cap does not carry over.

Loudest 400 ms of any file, 1.2 m ahead, alone (LUFS, LU over the night's beds at -35.3 in brackets), and the highest
sample of any file (dBFS), before then after, from `tools/audio/close_levels.py`:

| Sound | Cap before | Cap now | Peak before | Peak now | Loudest 400 ms before | now |
| --- | --- | --- | --- | --- | --- | --- |
| `board_tear` | -4.5 | +3.2 | -10.0 | -10.3 | -27.3 (8.0) | -21.9 (13.4) |
| `board_last` | -9.0 | -3.7 | -10.0 | -9.9 | -29.7 (5.6) | -23.3 (12.0) |
| `board_repair` | -6.5 | -1.3 | -9.9 | -10.2 | -30.0 (5.3) | -24.9 (10.4) |
| `door_open` | -3.0 | +3.2 | -10.5 | -10.0 | -27.6 (7.7) | -21.8 (13.5) |
| `debris_clear` | -6.0 | -1.9 | -10.8 | -10.2 | -25.1 (10.2) | -21.6 (13.7) |

(The caps are `near_cap_db`; the `volume_db` trims are as they were, so a board's ceiling over its file is the trim plus
the cap.) A torn board is still the loudest board close up (a test pins it, with at least 10 LU over the beds for all
five), and still outranks a groan (priority). Not done: `melee_hit` is also sharp (-27.4 LUFS, 8 LU over the beds) and
is left as it was.

**Measured**, `tests/captures/audio_headroom.tscn --all-variants` (`--close` for 1.2 m), every file of the 12 voices
and the 10 lot's sounds, one at a time, under each own gun firing without a break; samples over -1 dBFS in the zombie
cell then the lot's cell, before then after (peak of the mix in dBFS after):

| Own gun | ordinary geometry (2 to 6 m) | close (1.2 m) |
| --- | --- | --- |
| Revolver | 59, 78 then 0, 0 (-2.5, -3.9) | 833, 62 then 0, 0 (-2.8, -4.2) |
| Tommy gun | 45, 205 then 0, 0 (-2.2, -3.1) | 1837, 348 then 0, 0 (-2.3, -3.2) |
| Rifle | 31, 49 then 0, 0 (-2.6, -3.4) | 1085, 214 then 0, 0 (-1.8, -2.6) |
| Shotgun | 56, 323 then 0, 0 (-2.1, -3.6) | 1881, 166 then 0, 0 (-2.7, -4.0) |
| Flare gun | 135, 59 then **4, 2** (-0.6, -0.8) | 928, 48 then **2, 1** (-0.9, -0.8) |

The ordinary run of the matrix (each sound once, a random file) has no sample over -1 dBFS for four guns in any cell;
the flare gun's crack on a teammate's revolver shot is still -0.2 dBFS (8 samples), as before.

The flare gun's row of that table was the exception then; it is reshaped in
[the next section](#the-flare-guns-crack).

## The flare gun's crack

Issue #761. After #753 every other own gun had no sample over -1 dBFS in any cell of the headroom capture; the flare gun
still had some (4 and 2 in the zombie and lot cells, 2 and 1 close, 8 on a teammate's revolver shot). Its crack peaked
at -3.1 dBFS alone (a crest factor of 20 dB, the loudest 400 ms 20 dB under its highest sample), so a trim for -5.5
took its burst under the 17 LU rule: a fresh bench on `main` read its burst **16.7 LU** over the beds (-18.6 LUFS,
peak -2.3) where the table said 17.7. The row had parted from the bench; most likely the thin crack's burst reads
1.3 dB apart depending on which three variants the seed draws and where the 400 ms blocks fall on them (offline, over
the orders and block alignments), and the test only checked the table's trims against the catalog.

**Decision: reshape the file, no exception.** The flare gun follows the same two rules as the others (no sample over
-1 dBFS under other sounds, burst 17 LU over the beds). A look-ahead limiter alone is not enough (the best trade found
before: 1.3 dB off the decoded peaks for 0.5 LU), so the body is fuller too. `flare_shot` in `weapon_recipes.py`:
puff 2.4 to 3.5 and bark 2.2 to 3.0 (the thump unchanged), a harder drive (2.5 to 6), then `limiter.limit_crest`
(`FLARE_CREST_DB` 5: the highest sample at most 5 dB over the loudest 400 ms, a smooth gain, 2 ms look-ahead), then the
pipeline's normalisation as before. The limiter is in the file, so the web build plays it too (it ignores bus
effects; not re-run in Chromium, the [Browser](#browser) table below is the old file). Trim -1.5 to **-6.0**. A first
try with a heavy thump (1.4) met the numbers and turned the pop into a boom (91 percent of its energy under 250 Hz
against 44 to 69 for the other guns), so the bench's low-end share and centroid are read beside the LU.

**Measured**, `game/tools/bench/audio_gun_bench.tscn` through `tools/audio/gun_levels.py` on `main` (82eac9bd) and with
the change; the other four guns reproduce the table to 0.1:

| Flare gun, own shots | Before (`main`) | After | Rule |
| --- | --- | --- | --- |
| Loudest 400 ms of one shot | -17.2 LUFS (18.1 LU over the beds) | -16.2 (19.1) | 14 LU |
| Two second burst | -18.6 LUFS (16.7 LU) | -17.4 (17.9) | 17 LU |
| Peak of a shot / of a burst | -2.2 / -2.3 dBFS | -5.2 / -5.2 | -4.5 |
| Crest factor alone (peak minus RMS, headroom capture) | 20.4 dB | 17.5 | |
| Centroid, energy under 250 Hz | 3066 Hz, 0.50 | 3043 Hz, 0.63 | (others 0.44 to 0.69) |

Peak of the mix (dBFS, samples over -1 dBFS in brackets), the flare gun fired without a break, before then after:

| Cell | Before | After |
| --- | --- | --- |
| alone | -3.1 | -5.4 |
| a teammate reloads | -1.9 (0) | -3.8 (0) |
| a teammate fires (`mate`) | **-0.2 (8)** | -2.5 (0) |
| the dead's voices | -1.1 (0) | -2.4 (0) |
| the lot's sounds | -2.4 (0) | -5.0 (0) |
| every file, ordinary geometry: voices, lot | -0.6 (4), -0.8 (2) | -2.4 (0), -2.5 (0) |
| every file, 1.2 m: voices, lot | -0.9 (2), -0.8 (1) | -2.3 (0), -3.6 (0) |

The plots on the pull request show the sweep (before in grey, after in blue, -1 dBFS dashed) and the shot's envelope.
Run: `generate.py --only shot_flare`, the bench, `gun_levels.py --table game/tests/night/gun_levels.json`, and
`audio_headroom.tscn --own=flare_gun` (ordinary, `--all-variants`, `--all-variants --close`) through `headroom.py`.

**The test now fails when the table and the game part.** `test_gun_audio_rules.gd` no longer has the flare gun's
exception (-1 dBFS): every firearm peaks at -4.5 or lower in the table. The table also holds a SHA-256 of every variant
file the bench played (`gun_levels.py --table` writes them) and `test_the_measured_loudness_is_of_the_files_the_game_has`
fails when a file changed, or one was added or dropped, without a new measurement (checked: the old flare file under the
new table fails it). A trim moved without measuring already failed. What the hash does not cover is the playing code
(jitter, the audio service): the bench is re-run when that changes.

## The energy weapons and the re-cut layer (#791)

The ray gun, the freeze gun and what an upgraded weapon sounds like. Recipes: `tools/audio/energy_recipes.py`; played by
`EnergySounds` and `RecutLayer`; measured by `game/tools/bench/audio_energy_bench.tscn` through
`tools/audio/energy_levels.py` (the gun bench's method, with each weapon plain and re-cut), pinned in
`game/tests/night/energy_levels.json` by `test_energy_audio_rules.gd`. The design is
[Sound](../design/audio.md#the-energy-weapons-and-the-re-cut-layer).

### How the genre's upgraded weapons sound (design only)

Read from fan wikis; no developer account or sound-design breakdown was found, and the pages disagree, so this is what
can be said and no more:

- The upgraded weapon's shot is audibly *processed*, a "strange" firing sound, and that is the one thing the sources
  share. A fan wiki of the first game's mode lists, among the upgrade's changes, that the shots of bullet weapons are
  **higher in pitch** ([Nazi Zombies wiki, Pack-a-Punch](https://nazizombies.fandom.com/wiki/Pack-a-Punch)); the
  same family's wiki says a later game's upgraded weapons are **noticeably lower in pitch with a pulsating sound**, and
  its shotguns have a unique **laser-like** sound
  ([Call of Duty wiki, Pack-a-Punch Machine](https://callofduty.fandom.com/wiki/Pack-a-Punch_Machine)); a console
  port's note there says some weapons lacked the strange firing sounds. A guide describes the sound as a "laser-like
  pew-pew" added to the gun's
  ([GameRant](https://gamerant.com/call-of-duty-cod-mw3-modern-warfare-3-zombies-how-pack-a-punch-start-upgrade-weapon/)).
- So the direction of the pitch is not the signal (up in one game, down in another); what is: an electronic,
  laser-like, pulsing character laid on the gun, and a machine whose own sound ends on a jingle.
- **What we took:** the idea of a layer (not a re-pitched gun: our pitch rule stays within 0.15 semitones), the laser's
  sweep and the pulse, and a bench whose last sound is the layer's own ring so the player learns the pair. Nothing of
  any game's sound is copied; the layer and the elements are our own recipes.

### What was made

| Family | Sounds | Notes |
| --- | --- | --- |
| Ray gun | `shot_ray` (4), `bolt_ray` (loop), `burst_ray` (3), `reload_ray_cell_out`/`_in` (2 each), `equip_ray` | a charge (a sweep 350 Hz to 2.2 kHz in 90 ms) let go with a crack, a falling FM zap, a bark and a thump; a hum of two close notes beating at 7 Hz for the bolt; a boom and a shower of crackle for the burst |
| Freeze gun | `shot_freeze` (4), `freeze_hit` (2), `freeze_creak` (4), `freeze_thaw` (2), `freeze_shatter` (4), `reload_freeze_out`/`_in`, `equip_freeze` | a valve's hiss, a bark and an icy crackle; glass notes rising over a thickening crackle; stick-slip creaks; drips; a crack and twenty-odd tinkling shards |
| Re-cut layer | `recut_layer` (5), `recut_deep` (3, the wonder weapons'), accents `recut_blast`, `recut_shock`, `recut_fire` (3 each) | played over the shot of any re-cut weapon, 30 ms behind the report; the element accents over it |
| The bench | `buy_recut` | follows [#787's bench](https://github.com/Ryubara/deadnight/pull/802): the strike at 0.8 s, the ring of light and the skin's sweep from butt to muzzle to 1.35 s, the layer's own ring at 1.55 s |

Every shot keeps the firearms' rules: flat for the shooter, from the muzzle for a stranger, within 0.15 semitones and
0.5 dB, the variants within 2 percent of one note, no bus effect (the shot is limited in its recipe, `limit_crest`, run
three times to hold a crest of 7 dB: one pass leaves it 5 dB over because the limit also lowers the loudest 400 ms it is
read against).

### The shots, measured

The gun bench's method (`tools/audio/energy_levels.py`: the listener 2.7 m behind the muzzle, 60 frames a second, the
night's beds at -35.3 LUFS). The ray gun fires every 0.45 s and the freeze gun every 0.8 s in the bench (#785's numbers).

| Weapon | Loudest 400 ms of a shot (LUFS) | Burst, 2 s (LUFS) | Peak of a shot / of a burst (dBFS) | Over the beds, shot / burst (LU) | Centroid (Hz) | Low end under 250 Hz |
| --- | --- | --- | --- | --- | --- | --- |
| Ray gun | -13.8 | -14.2 | -7.5 / -6.5 | 21.5 / 21.1 | 2884 | 0.20 |
| Freeze gun | -14.0 | -17.4 | -6.0 / -5.5 | 21.3 / 17.9 | 5969 | 0.01 |

Both clear the rules (14 LU for a shot, 17 for a burst, a peak under -4.5 dBFS). The ray gun is trimmed -7.5 dB (the
loudest firearm, the shotgun, reads -15.3 for its loudest 400 ms) and the freeze gun -6.5 dB: a cold hiss has no low
end to give it weight, so its burst is the one closest to the rule (17.9 LU against 17).

### The re-cut layer, measured

A first version, started with the shot and trimmed 18 dB under it, lifted a rifle's burst peak by 0.7 dB and was not
heard (+0.3 dB in the tail of the revolver's shot): its loudest moment landed on the report's peak, and its body was
25 dB under its own peak. It now starts 30 ms behind the shot, is made dense (a crest of 7 dB) and rings and pulses for
half a second; its trim was chosen on a model (the rendered layer added to the recorded plain shots at a few gains,
reading the peak added and the tail and band it adds) and then measured. At -22 dB (the accents -23; the layers start at
most every 0.12 s, on a voice group of four) the bench reads, re-cut minus plain:

| Weapon | Peak added, shot / burst (dB) | Loudest 400 ms / burst (LU) | Tail 0.08 to 0.5 s (dB) | 2 to 8 kHz band there (dB) | 250 to 500 Hz band (dB) | Centroid (Hz) |
| --- | --- | --- | --- | --- | --- | --- |
| Revolver (+ explosive accent) | +0.8 / -0.1 | +0.3 / +0.4 | +9.3 | +18.4 | -7.0 | 3062 to 6231 |
| Tommy gun | +0.1 / +0.9 | +0.3 / +0.3 | +16.2 | +23.0 | -17.6 | 3062 to 6044 |
| Rifle | +0.1 / -0.1 | +0.3 / +0.1 | +2.2 | +17.1 | +0.1 | 2731 to 4116 |
| Shotgun | +0.3 / +0.1 | -0.1 / +0.3 | -0.2 | +9.1 | +0.1 | 2458 to 3213 |
| Flare gun (+ fire accent) | +0.1 / +0.4 | +0.3 / +0.1 | +8.2 | +16.5 | -0.4 | 3028 to 5912 |
| Ray gun (`recut_deep`) | +1.2 / +0.6 | +0.1 / +0.0 | +0.3 | -1.7 | +6.7 | 2884 to 2936 |
| Freeze gun (`recut_deep`) | +0.2 / +0.8 | -0.5 / +0.4 | -0.5 | -2.3 | +23.5 | 5969 to 5966 |

- **Headroom kept.** The most the layer adds to a peak is 1.2 dB, and every re-cut shot or burst stays under -4.5 dBFS
  (the Tommy gun's burst, -4.8, and the freeze gun's, -4.7, are the closest). The loudest 400 ms moves by at most
  0.5 LU either way: the guns are as loud as they were, and the weapon is heard as upgraded by what rings after the
  report.
- **Heard.** The firearms gain 9 to 23 dB in the 2 to 8 kHz band of the tail. The shotgun's tail is its own 0.4 s of
  boom, so the whole tail moves by nothing and only its bright band shows the layer (+9.1 dB). The two wonder weapons'
  shots already fill that band with zaps and glass (the shared layer read -1.7 and -2.3 dB there: lost), so they have
  the same idea an octave and a half lower (`recut_deep`: a falling sweep, three low partials that pulse, a longer sub
  pulse): +6.7 dB and +23.5 dB in the 250 to 500 Hz band.
- **Still the same gun.** The report keeps its front (the share of a shot's energy in its first 50 ms is 0.94 to 0.91 for
  the revolver and 0.99 to 0.93 for the Tommy gun), but the window's energy is mostly the layer's ring: the bench's
  low-end share falls (the Tommy gun's 0.52 to 0.03, because its report lasts 70 ms and the layer 500) and the centroid
  roughly doubles. That is the audible difference, and why the layer is trimmed 22 dB and no more.
- **Elements.** #785 gives four re-cut elements: explosive rounds (the revolver), shock (the dual pistols), fire (the
  pump 870, and the flare gun's burning ground). Each plays an accent over the shared layer (`recut_blast`,
  `recut_shock`, `recut_fire`: no ring of their own, a different noise and pulse); the wonder weapons have no element.
  A weapon not yet in the catalogue (the dual pistols, the pump 870) has its element in `RecutLayer.WEAPON_ELEMENTS`
  already; a test pins the table to the design.

### The close sounds

The burst, the freeze, the creak, the thaw and the shatter can sound a metre from the listener, so they follow
[the close-sound rule](#close-sounds-under-gunfire): the loudest sample 1.2 m ahead leaves room for a shot. Read from a
recording of the bench's close stage (every variant, one at a time):

| Sound | Held to (dB over its file) | Highest sample (dBFS) | Loudest 400 ms (LUFS) |
| --- | --- | --- | --- |
| `burst_ray` | -6.0 | -11.0 | -20.9 |
| `freeze_shatter` | -5.0 | -10.9 | -19.0 |
| `freeze_thaw` | -2.5 | -10.9 | -18.8 |
| `freeze_hit` | -2.5 | -10.7 | -17.9 |
| `freeze_creak` | -3.0 | -11.8 | -20.2 |

The room is -9.8 dBFS (what the loudest firearm's -4.9 leaves under -1 dBFS). The first versions of the freeze's quiet
sounds read -31 to -37 LUFS, under the night's beds: made of ticks and drips (a crest of 25 dB), their body at the
highest level a close sound may have was inaudible. They are now limited to a crest of 10 dB in their recipes.

### What is left open

- The wonder weapons' reload steps follow the events `cell_out`, `cell_in`, `canister_out` and `canister_in` of their
  reload motions once those exist; until then they play at 0.12 and 0.55 of the reload.
- The freeze events (`zombie_frozen`, `zombie_thawed`, `zombie_shattered`) are named in `EnergySounds`; the status
  effect of [#788](https://github.com/Ryubara/deadnight/issues/788) sends them or calls the methods of the same names.
- Nobody can listen here: the sounds are judged by these numbers, and the clips on the pull request are for the
  maintainer's ears.

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
