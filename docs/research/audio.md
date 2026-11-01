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
- **A bed never goes quiet**, so an onset detector on the raw level finds nothing: `analyze.py` compares the short-term
  level with its own median over a second either side.

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
