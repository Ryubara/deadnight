# The drive-in's wind

The maintainer asked (issue #782) for an ambient wind: quiet, subtle but noticeable, different each time it plays so
that it does not repeat, made the way other game developers do it, and suited to the empty feel of a zombie apocalypse.
What shipped games do, what we built from it, and what it measures. The sounds are
`tools/audio/wind_recipes.py`; how they play is `WindSounds` and `WindPlan` (`game/gameplay/night/`); the design is
[Sound](../design/audio.md#the-wind).

## How other games build wind

Every source below builds wind the same way: **a steady base, and events on top that arrive at random.** Nobody ships
one long loop and hopes it hides its repeat.

| Source | What it says | What we took |
| --- | --- | --- |
| [Ghost Recon Advanced Warfighter 2, multiplayer wind system](https://designingsound.org/2010/10/audio-implementation-greats-9-ghost-recon-advanced-warfighter-2-multiplayer-dynamic-wind-system) (Designing Sound, an award winner at the 2008 GANG awards): three looping base layers (breezy, windy, gusty), each with three random overlay loops that add gusts and swells; the playback level drives the rest. Emitters on buildings play creaks, rattles and groans from sets of 4 to 8 files split in high, medium and low intensity; the stronger the wind the more often they play (about every 2 to 6 s at the top, every 20 to 30 s in a light wind). | A base plus random overlays, and details that ride on the wind's strength: sharp creaks and rattles only on the strong gusts, low groans on the weak. | `WindPlan.next_gust`: a detail only on a gust at least as strong as `DETAIL_MIN_DB`, drawn from three kinds |
| [Ambience design in ADX2 (CRI Atom Craft, part 1)](https://blog.criware.com/index.php/2020/12/14/ambience-design-in-atom-craft-part-1-2/): the gust is a one-shot "random no repeat" cue over a looping nature bed; each variation has its volume and band-pass curve drawn by hand (same start and end value), a 600 cent pitch random range and a 1.5 s random start offset, so "ebb and flow" comes from a small pool without engine logic. | The shape of a gust (its level and its filter colour) lives in the file, so a gust is a played sound; the pitch is random per play; the next gust starts at a random time, not on the loop. | `wind_gust`: eight files with their own envelope and low-pass sweep, `pitch_semitones` 2 (about 400 cents), a seeded random lull |
| [Eon Altar's ambience system](https://www.gamedeveloper.com/audio/video-game-audio---under-the-hood---eon-altar-ambience-system) (Game Developer): each zone has a bed, and random "sweeteners" are played from a point above the party plus a random offset, after a random wait (5 to 10 s in the demo) and never stacked: the next wait starts when the clip ends. | Sweeteners are placed round the listener at a random offset, and a new one is not started while one plays. | A gust blows from a random bearing 10 to 16 m off; the lull is counted from the previous gust's end, so gusts never overlap |
| [Sound Design Toolkit, wind model](https://sdt.lim.di.unimi.it/docs/API/v2.2-078/group__windflow.html): turbulence modelled as band-pass filtered white noise whose amplitude follows the air speed. Farnell's *Designing Sound* (MIT Press, 2010, the procedural wind in Pure Data; read only as summarised in forum threads, not in full) uses noise through a low-pass or band-pass filter whose cutoff a slow random control moves. | A gust is noise whose brightness rises and falls with its strength, which is why a strong gust sounds open and a weak one dull. | `wind_gust`: noise through a 24 dB per octave low-pass swept from 130 Hz to 400 to 1400 Hz with the envelope, over a body under 110 Hz |
| Wwise random containers, and [a forum question on a gust raising a looping bed](https://audiokinetic.com/qa/12360/how-can-drive-volume-file-with-start-files-random-container) (Audiokinetic; the thread is a question, not a documented method): the usual wiring is a random container of gusts over a loop, with an RTPC from the gust to the bed's level. | The base swells with the gust that is blowing. | `WindSounds` raises the base layer up to 2 dB (`BASE_SWELL_DB`) with the blowing gust's envelope |
| Joanna Orland, "Bringing Ambience to the Foreground" (GDC 2009; the page lists the title and speaker, the session is for members only, so it is not read). | Not used beyond its title. | None |

What the sources do not say, and what we decided for the empty feel:

- **Not a storm.** The wind is low and mid: the gust files sit at 300 to 870 Hz in their centroid, with the low-pass
  only opening to 1.4 kHz at the top of the brightest file; only one of eight files has a whistle, a thin narrow band
  of noise near 940 Hz that speaks only at the gust's peak (it is a gust in eight).
- **Long lulls on purpose.** The lull between gusts is 1.5 to 26 s skewed short, and one in twelve is 35 to 60 s. A
  bed that never changes reads as a machine; a minute with nothing but the crickets and the highway is the emptiness.
- **Nothing in the wind carries any life.** The details are a sign on a rusted hinge, a loose sheet of tin and a tarp
  on crates, each a long way off: they are the places the wind finds, not creatures.

## What was built

| Part | What it is |
| --- | --- |
| `bed_wind` | a 30 s loop (circular, like the other beds): low pressure under a dull breath, 91 percent of its energy under 250 Hz, a crest factor of 13 dB; level wanders and swells at runtime, so the loop's repeat is never the same level |
| `wind_gust` 1 to 8 | one-shot gusts of 3.6, 5.2, 7.5, 9.8, 6.4, 11.5, 4.4 and 8.6 s, each with its own rise (30 to 70 percent of its length before the peak), its own peak brightness (420 to 1400 Hz) and, for one, a second push and, for one, a whistle; every file holds the same crest factor (9 dB over its loudest 400 ms, `limit_crest`) so one trim fits all |
| `wind_creak` 1 to 3, `wind_rattle` 1 to 3, `wind_flap` 1 to 2 | the details: a stick-slip creak, irregular dull clanks of tin, slack cloth snapping |
| `WindPlan` | every draw of a night from one seed, no clock, no engine randomness: the night's character (lulls scaled 0.7 to 1.4, the whole wind -2.5 to +1 dB), then for each gust the lull before it, its level (0 to 4 dB under the files' trim), the side it blows from, how fast it drifts round, and sometimes a detail |
| `WindSounds` | the clock and the sounds: the base as a bed, each gust an `Audio.play` of `wind_gust` at the draw's position (the service picks the file and the pitch, so the length varies again by plus or minus 12 percent), followed round the listener each frame |

**Why not a bus effect.** The web build plays sounds as samples and ignores bus effects ([Audio in the
browser](web-export.md#audio-in-the-browser), #755). A gust is a played sound with its colour and level baked into the
file, and everything else is a volume (the bed's level, a sound's `volume_db`); a test checks the Ambience bus has no
effect on it.

**Why the gust is 3D, a short distance off.** A flat gust would be a swell in the middle of the head. At 10 to 16 m on a
random bearing, drifting up to 0.12 rad/s, a gust crosses the field, follows a walking player (it is moved with the
listener each frame) and, behind a wall, is dulled by the service's own occlusion like a cricket would be.

## Variety, in numbers

A seeded draw (`WindPlan`, tests in `tests/night/test_wind_sounds.gd`): over 80 gusts the lulls span more than 25 s,
the levels more than 3 dB, the bearings more than 4 rad and the drifts more than 0.15 rad/s; no two consecutive gusts
share a lull or a level; one lull in twelve is a long one; a detail rides on about one gust in seven and never on a weak
one; the eight files differ by 7.9 s in length; the same seed replays the same gusts and another seed does not; each
night's character differs (30 seeds: calm 0.7 to 1.4, level -2.5 to +1 dB).

## Levels

Measured with the pinned ffmpeg's `ebur128` (K-weighted, LUFS; a momentary value is 400 ms) by
`tools/audio/wind_levels.py`, on the files with the catalog's trims laid over them (`files`) and on the Ambience bus of
`tests/captures/audio_wind_night.tscn` (`night`): a night with the first round on and nothing spawned, 120 s, seed 785,
three runs with the same seeds (the beds and the wind, the wind alone, the beds alone).

| What | Level |
| --- | ---: |
| The crickets / the highway / the projector alone (files with trims, integrated) | -40.7 / -38.1 / -34.6 LUFS |
| The night's three beds together (capture, 6 to 120 s) | -33.1 LUFS |
| The base layer alone, between gusts (momentary, median, range) | -49.7 (-52.3 to -47.5) LUFS |
| A gust's peak (5 gusts, momentary; draws from 4.6 dB under to 1.5 dB under) | -40.5 to -37.6 LUFS, median -39.5 |
| A gust over the base | +9.2 to +12.1 LU |
| A gust's peak over the beds' level a moment before | +0.6 to +4.0 LU (median +2.3) |
| The wind alone, integrated over the two minutes | -46.1 LUFS |
| What the wind adds to the night's integrated loudness | +0.20 LU (-33.1 to -32.9 LUFS) |
| The loudest 400 ms of the beds / of the beds with the wind | -29.3 / -29.0 LUFS |
| A creak (computed from its file and trim; 14 to 30 m off, 0 to 4 dB under) | -43 to -36 LUFS-M at most; in the capture it reads under its gust |

### Headroom with the wind at its strongest

`audio_headroom.tscn` with `--wind` (the base at its own level and a strongest gust, 0 dB under the files' trim, every
3 s) against the same run without it, each own gun firing without a break with a reload, a teammate's gun, the dead's
voices or the lot's sounds landing on it (`tools/audio/headroom.py`, peak of the mix in dBFS, without then with the
wind; no sample over -1 dBFS in any of the 50 cells):

| Own gun | alone | + reload | + teammate's gun | + zombie voices | + lot's sounds |
| --- | --- | --- | --- | --- | --- |
| Pistol | -5.9 / -5.4 | -4.0 / -3.7 | -2.2 / -3.5 | -3.4 / -3.3 | -3.4 / -3.6 |
| SMG | -5.7 / -5.3 | -1.2 / -1.9 | -2.7 / -3.1 | -2.7 / -2.9 | -2.6 / -2.2 |
| Rifle | -5.4 / -5.2 | -3.5 / -3.1 | -2.3 / -2.3 | -3.3 / -3.2 | -3.7 / -3.8 |
| Shotgun | -5.6 / -5.4 | -3.0 / -3.1 | -3.0 / -3.0 | -2.9 / -2.7 | -3.4 / -3.4 |
| Flare gun | -5.4 / -5.1 | -3.8 / -4.7 | -2.5 / -2.5 | -2.4 / -2.0 | -3.3 / -3.9 |

The wind alone at that strength peaks at -27.2 dBFS (the same capture with no gun), 21 dB under the quietest gun peak,
so the most it can add to a sum, if its peak met a gun's, is 0.7 dB; the table's moves (up to 0.5 dB up, 1.3 dB down)
are the runs' random draws (variants and pitch) and not the wind. The rules of #718, #753 and #762 hold: every gun
alone peaks at -5.1 dBFS or lower (the rule is -4.5), the worst sum is -1.9 dBFS (SMG under a teammate's reload), and
the guns' loudest 400 ms and bursts do not move by more than 0.3 LU (pistol burst -16.7 / -16.5 LUFS, SMG -13.1 /
-13.1). The beds the gun rules are read against (`gun_levels.py`, -35.3 LUFS) do not include the wind; with it they
rise by 0.2 LU (below), which takes the same 0.2 LU off the guns' margin over the beds (the tests ask 14 and 17 LU;
they read the bench's beds, which start from `NightSounds.NIGHT_BEDS`, a list the wind is not in).

The wind is under the other beds in every number (its strongest gust is 8 LU under the beds' loudest moment, and what
it adds to the whole is 0.2 LU), is 9 to 12 LU over itself during a gust (so a gust is a gust), and stands out against
the beds by 0.6 to 4 LU at its peak: a swell on the highway's rumble, heard in the quiet between rounds and gone under
a gun. The weakest gust that can be drawn peaks 5.5 dB over the base, so no gust is one the base hides.

![The wind's levels over two minutes](wind-levels.png)

*The momentary loudness of the wind alone (dark) and of the Ambience bus with the other beds (grey); the gusts shaded.
A creak rides on the gust at 96 s, after the minute-long lull.*

## The second map

The depot map has two wind loops of its own: `bed_roof_wind` (a 20 s loop, under the roof's hole, set per room by
`SmallMapSoundTuning.roof_db`) and four copies of `yard_wind` (a 24 s loop, at the yard's corners, routed through the
windows by `SmallMapWays`). `NightSounds` runs on both maps, so the new wind plays there too, as the open-air layer
over the whole night, like the crickets and the highway do.

**Decision: the two loops stay as they are, and the new wind is the open-air layer over them.** The numbers
(`tools/audio/wind_levels.py files` for the files with their trims, momentary loudness at the source in LUFS; the
window figures are the same sounds taken down by the window numbers of `smallmap_levels.py table`: 12.3 dB for an open
window and 18.8 dB for a boarded one):

| Sound | At its place (momentary) | Through an open window | Through a boarded one |
| --- | ---: | ---: | ---: |
| `bed_roof_wind`, under the hole | -34.2 | | |
| `yard_wind` (four corners, 10 m) | -27.3 | -39.6 | -46.1 |
| the new base layer | -49.7 | | |
| the new gust, at its peak | -37.6 to -40.5 | | |

- The loops are 4 to 15 dB over the new base. Replacing them with the new system would take the second map's wind down
  by that much and lose what they do, which is *place*: the roof's moan is heard under the hole and is gone in the
  next room (`SmallMapSoundTuning.roof_db`), the yard's wind comes in at the windows (`SmallMapWays`). A global gust
  cannot do that, so they stay as the located wind.
- The new wind is there on that map already, because `NightSounds` runs on both: a base 4 dB under the yard's wind
  through a boarded window, and gusts at the level of the yard's wind through an open one (-39.6) and 6 to 9 dB over
  it through a boarded one. In the depot's quiet a gust is the one thing that varies, and it does not bury the located
  loops. The loops repeat every 20 and 24 s; what plays over them is what the drive-in's base has too.
- Then, when the loops were heard to repeat (#809): the blowing gust drives them, below.

### The gust drives the loops (#809)

`SmallMapSounds` reads `WindSounds.swell()` (0 to 1, the blowing gust's envelope) ten times a second and raises the roof
wind and the yard's four wind loops by it, the way the base layer follows it (2 dB there): **the roof wind 3 dB and each
yard wind loop 6 dB at the gust's peak** (`SmallMapSoundTuning.roof_gust_db`, `yard_gust_db`). The rooms' levels
(`roof_db`) are where the roof wind rests and the #657 reach numbers (`max_distance`, the ways) are not touched: with no
wind, or no gust, the sound is what it was (a test checks the rest level against the old -19 dB trim plus the room's, that
nothing swells with no wind, and that a gust does not make the yard carry further).

A bed cannot be raised over its own level, and the roof wind's upstairs room rests at 0 dB, so its trim went from -19 to
-16 dB (`SmallMapSoundTuning.ROOF_HEADROOM_DB`) and every room reads 3 dB lower: the heard level at rest is the same
(kit [Swelling a bed][kit-swell]). The yard loops are 3D players and have no such limit.

[kit-swell]: https://github.com/Ryubara/gdstudio/blob/main/docs/godot/audio.md#swelling-a-bed-with-an-event

**Why 6 dB on the yard and 3 on the roof.** A first try had both at 3 dB, and the yard's swell barely showed: the
loops there are heard through a window, 10 dB or more under the rest of the bus, and a 3 dB swell on a sound that far
under raised the bus by 0.1 to 0.2 LU, not heard (that run also had the lot's crickets and highway under it, which
this map does not play, so its numbers are not kept). At 6 dB the swell is heard through an open window and stays a
texture through a boarded one; the roof wind is the loudest located wind and 3 dB is all the headroom the trim has.

Measured on `tests/captures/audio_smallmap_gusts.tscn` with `tools/audio/gust_levels.py`: the second map as it will play
(its room tone, roof wind, yard and the night's wind, **without the lot's crickets and highway**, which the map's sound
replaces), 120 s, seed 785, the listener in one place, the Ambience bus recorded, once with the swell and once without
(the same gusts, six in each run); momentary loudness (LUFS, 400 ms):

| Where | The loop's own level at rest, at the gust's peak | The bus between gusts | A gust's peak on the bus, without / with the swell | The swell raises the bus at the peak | The night's integrated loudness |
| --- | --- | ---: | ---: | ---: | ---: |
| upstairs, under the hole (roof wind) | -19.0, -16.0 dB (+3.0) | -34.3 | -31.2 / -30.7 | +1.3 to +2.0 LU (median 1.7) | -33.6 to -33.3 (+0.3 LU) |
| the hall, in line with a boarded window (yard wind) | -37.7, -31.7 dB (+6.0) | -34.8 | -33.2 / -32.8 | +0.3 to +0.6 LU (median 0.5) | -34.5 to -34.4 (+0.1 LU) |
| the same window, boards off (yard wind) | -31.2, -25.2 dB (+6.0) | -32.8 | -31.4 / -30.8 | +0.6 to +1.3 LU (median 1.1) | -32.8 to -32.6 (+0.2 LU) |

The loop's level follows the gust's swell (a test checks it within 0.6 dB of `swell * size` all through a gust; the
captures' traces read +2.9 to +3.0 and +6.0 at every gust's peak). Without a gust the loops are where they were.
Upstairs the roof wind's own moan (a 20 s loop, the bus wobbling by 2 to 3 dB in the plot) is the loudest thing in the
room, and a gust now lifts it with the rest of the wind: the loudest 400 ms upstairs rises 1.1 LU (-30.1 to -29.0
LUFS), still far under a shot's loudest 400 ms (-12 to -17). A gust's peak stands 3.6 LU over the bus between gusts
upstairs (3.1 before), 2.0 LU in the hall (1.6 before) and 2.0 LU at the open window (1.4 before).

![The second map's night with and without the swell](gust-levels.png)

*The Ambience bus of three stands over two minutes, the gusts shaded: grey, the loops as they were; dark, the gust
driving them.*
