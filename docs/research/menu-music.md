# The menu's music (#979)

The maintainer asked for ambient music in the menu (#979): music that fits a main menu, quiet and calm enough that
people can stay on it for a long time without tiring of it, or ambient sounds such as the wind if not music. What we
read, what we built from it and what it measures.
The sounds are `tools/audio/menu_recipes.py`; how they play is `MenuAmbience` (`game/core/audio/menu_ambience.gd`); the
levels against the menu's hints are #926's check ([the bed](menu-sfx.md#the-ambience-bed-926)).

## What holds a long stay

A person who leaves a menu open hears it for as long as they sit there, so the question is repetition, not first
impressions.

| Source | What it says | What we took |
| --- | --- | --- |
| [Rethinking the audio loop in games](https://www.gamedeveloper.com/audio/rethinking-the-audio-loop-in-games) (Game Developer) | A loop should be as long as the time a player spends in it; a repeat is tolerable twice and too much from the third to the fifth; short loops give less room for contrast; its workarounds are reordering sections, silence after a few repeats and different tracks in a random order | No short loop and no tune that returns: the music is three loops of unequal length, so the combination is new each time round |
| [Breaking the loop: the music of Breath of the Wild](https://gamedeveloper.com/audio/breaking-the-loop-a-look-at-the-cinematic-music-of-breath-of-the-wild) (Game Developer) | Long silences between a few piano notes mean "you're no longer perceiving rhythm" and "you don't really get sick of it the way you would a looped track"; Minecraft is cited for ambient music that comes and goes | The bells are single notes 5 to 14 s apart with nothing between them; there is no pulse to tap along to |
| [Music for Airports](https://en.wikipedia.org/wiki/Music_for_Airports) (Wikipedia) | Made of tape loops of differing lengths, "irregular repetition rather than a perceptible pulse", set going and left to configure themselves; Eno wanted silence at least twice as long as the sound | The same method: loops of 76, 113 and 47 s |
| A Klei forum thread on [longer music loops](https://forums.kleientertainment.com/forums/topic/170358-longer-music-loops/) (player reports, not a study) | Players who came to hate a menu theme after hundreds of plays; a very short menu track drew complaints for being short and repetitive | Nothing with a hook: no melody to be sung back, no beat |

What the sources do not give, and what we decided:

- **No loop length is a number from a study.** None of the sources has one (a fan wiki's figure for another game was not
  used). We took the principle: every length is long (47 to 113 s) and, more important, they share no factor.
- **A key and a tempo that fit the drive-in night.** There is no tempo: nothing pulses. The key is D dorian (D E F G A B
  C): a minor colour with the major sixth that keeps it open and unthreatening rather than sad, over a D and an A held
  all the way round. It is the key of the night's own score (`bed_score`, in D minor) a step softer, so the menu and
  the break sound like the same place. Every note and chord tone is a **just ratio** of the root, so no two voices
  beat against each other's harmonics: with twelve-tone tuning a chord tone's third harmonic stood 0.5 Hz off its
  neighbour and the pad's level pulsed every two seconds, which is what a person tires of first.
- **Dark and soft on purpose.** Nothing in the pad or the wind is over 1.5 kHz to speak of, a bell's brightest partial
  is a faint 2.7 kHz, and there is no attack to speak of. The menu's own hints (the hover and the focus tick) live at
  1.5 to 8 kHz, so a dark bed leaves them plain (below).
- **Low dynamic range.** The pad's loudness moves about 3 dB over 76 s; the wind swells about 12 dB over ten seconds;
  the bells are the only events.

## What was built

Everything is **synthesised** (oscillators, filtered noise, seeded by the sound's name), as every sound of the game
is: no sample, no model, no licence. ElevenLabs credits were offered; its Sound Effects output is on the free tier
whose terms say attribution is required and no commercial use (the `eleven/LICENSE.md` of the generator hum, tracking
issue #252), so a music file from it would be another file waiting on the maintainer's licence decision. Music made
here has no such question. **If the maintainer wants a generated track after all, that is a licence question and his
to answer; this pull request does not take it.**

| Loop | Length | Bus | What it is |
| --- | ---: | --- | --- |
| `menu_pad` (`music/`) | 76 s | Music | a held D and A (and the D above) under four chords that fade into each other over 19 s each (C F A, G B E, C E A, F C G: D minor seventh, G sixth, A minor seventh, F with its ninth); every voice is two sines a few cents apart with a soft second and third harmonic whose level drifts, so each note opens and darkens by itself |
| `menu_bells` (`music/`) | 113 s | Music | 12 to 14 soft struck notes of D dorian in two octaves, one to three scale steps from the last, a few with a second note a fifth under; a dark echo and a six second tail that wraps round the loop's end |
| `menu_wind` (`ambience/`) | 47 s | Ambience | air in the mids a small speaker keeps (160 to 1500 Hz), swelling and falling over about ten seconds, with a thin ring of air near 500 Hz; no gust (a gust is an event and the menu holds still) |

Every sine has a whole number of cycles in its loop (its frequency is moved to the nearest one, under a tenth of a cent)
and every other control is periodic in the loop, so each loop is its own seam: the step from the last sample to the
first is smaller than any step inside (`menu_music_levels.py files`). The lengths 76, 113 and 47 share no factor, so
the three come back together after 403,636 s, about 4.7 days; and since every note of the bells is in the scale of the
chords, any meeting of them is in key.

**Wind.** It already existed for the night (`bed_wind` and its gusts, #782, [Wind](wind.md)); the night's base layer is
91 percent under 250 Hz, which a laptop and a phone do not play, so it would be silent where most people sit. The menu
has its own loop in the mids instead. The night's gusts are events placed round the listener on a night's clock and
were not carried into the menu.

## Why it plays as three beds

A bed is a looping stream the service fades in and out (`Audio.start_bed`), never decoded to samples (a deferred bank
would queue the files for a decode a stream never needs). The menu holds five beds now (the three above and #926's
projector and crickets, on lower trims) and the player pool was ten with the night's seven fading out for two seconds
after Leave night, so `AudioService.POOL_BEDS` is 12 (`test_the_menu_is_the_only_one_holding_all_five_beds_while_a_night_fades`).
The music is on the **Music** bus and the wind, projector and crickets on **Ambience**: each has its own slider in
Settings, Audio.

## What it measures

By `tools/audio/menu_music_levels.py` (the files, decoded from the shipped Ogg, and the mix as the game plays it) and
`tools/audio/menu_speakers.py` (#926's check, on a 120 s recording of `tests/captures/audio_menu_bed.tscn`: the five
beds through the real service and buses at the default settings, 80 percent on both sliders).

| The files | `menu_pad` | `menu_bells` | `menu_wind` |
| --- | ---: | ---: | ---: |
| Length | 76 s | 113 s | 47 s |
| Size | 509 KiB | 843 KiB | 145 KiB |
| Peak | -3.0 dBFS | -2.9 dBFS | -2.9 dBFS |
| Loudest 400 ms over its median (LU) | 1.5 | 16.4 (sparse notes) | 7.1 (a swell) |
| Energy over 1.5 kHz | -31.8 dB | -78.8 dB | -55.3 dB |
| Step across the loop seam, against the biggest step inside | 0.0003 against 0.034 | 0.0002 against 0.015 | 0.004 against 0.041 |
| Level 400 ms either side of the seam | 0.07 dB | 1.5 dB (a note's tail) | 0.17 dB |

The loops return together after 403,636 s (4.7 days). The pack grows by **1.5 MB** (the three files), against 89 MB of
assets.

| The mix (4 s to 119.5 s of the recording) | |
| --- | ---: |
| Peak | -31.3 dBFS (no clipping) |
| Integrated loudness | -44.6 LUFS |
| Loudest 400 ms / median / quietest | -42.3 / -44.6 / -46.5 LUFS-M |
| Loudness range (95th over 5th percentile of the 400 ms values) | 2.2 LU |
| Swing of the 3 s power over the two minutes | 2.1 dB |

The mix is as quiet as #926's bed was (its loudest 400 ms was -42.4): it is the same margin to the hints, with the
music, not the crickets, as most of it (the trims are in `beds.tres`: pad -31, bells -37, wind -33 and the projector
-31 dB, the crickets -38 dB, down from -25 and -31 for the last two).

### Under the hints, on a laptop and a phone

The same two gates as #926 (a hint's peak 10 dB over the bed's loudest 400 ms; 6 dB in the hints' own band over the
bed's loud 50 ms), the worst hint of each model:

| | flat | laptop | phone |
| --- | ---: | ---: | ---: |
| Bed, loudest 400 ms (LUFS-M) | -42.3 | -45.0 | -52.4 |
| Worst hint, peak over the bed (gate 10) | 10.8 | 15.3 | 22.7 |
| Worst hint, 1.5 to 8 kHz over the bed (gate 6) | 12.9 | 14.3 | 15.2 |

The worst is the "Coming" hover (4 dB under the others) on a flat speaker, as in #926; it has 0.8 dB over the gate (it
had 0.9). The in-band margin was 6.2 dB with the crickets at -31 dB and is 12.9 with them at -38: the crickets were what
sang in the hints' band, and the music is under 1.5 kHz. The pin is `tests/core/menu_bed_levels.json`.

### What was not tested

What only a person can tell: whether this is pleasant to sit in for an hour, and how a real speaker differs from the
assumed laptop and phone curves. The numbers say it is dark, slow, free of beats and pulses, quiet, seamless and under
the hints; they do not say it is good. Both sliders (Music, Ambience) are the answer to taste, and each layer's trim is
one line of `beds.tres` (and its row of `sound_defaults.json`).

### What it costs

Native: opening the five beds takes 2.7 to 4.8 ms each, once, in the frame the menu is entered; mixing them costs 0.009
to 0.020 ms a frame each (about 0.075 ms for the five, 0.4 percent of a 60 Hz frame), 0.21 ms the worst block. Not
measured: the web build's menu load (the pack is 1.5 MB larger).
