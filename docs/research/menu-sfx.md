# The menu's sound language (#894)

The menus were nearly silent. The tab bar, the tickets of the Play, Shop and More tabs, the challenge rows, the chips
and the map cards are plain `Button`s of the menu's own that never called the interface sound hook (`UIAudio`), so a
walk over the whole main menu made **two sounds in its first 26 seconds** (a stray focus click), while the Settings
screen, whose controls come from the `gds_ui` addon, clicked on every hover and ticked on every step of a slider drag
(**37 ticks in 1.7 s** at the widest drag; 16 in the walk below), and a Back played a click and a whoosh together with
nothing to say which mattered. The bus (`UI`), its slider (Settings, Audio, "Interface sounds", 80 percent) and seven
cues had existed since #87; nothing said which control plays what, so nothing capped the spam either.

This page is Deadnight's answer. The general research (which component takes a sound, weights, repetition, levels,
touch, accessibility, the sources and how far to trust each) is the kit's [Menu and interface
sounds](https://github.com/Ryubara/gdstudio/blob/main/docs/audio/ui-sounds.md). The code is
`game/core/audio/ui_sound_table.gd` (the table), `ui_sounds.gd` (the rules) and `tools/audio/ui_recipes.py` (the
sounds).

## What the research gave us (the short list)

1. A sound for what **changes or commits**; silence for what is continuous or automatic.
2. **Five weights**, each 4 to 6 dB louder and longer than the one below: hint, move, press, commit, moment. The same
   kind of event is always at the same weight.
3. **The hundredth press**: three or four files for what is heard every few seconds, never the same file twice, a small
   random pitch and level, and caps on spam that are numbers in a test.
4. A **UI bus of its own with its own slider**, under the game's loud sounds: no menu sound is louder than a pistol
   shot.
5. **No hover on a finger**: the tap is the press. A key or a pad moving the focus is a hint; a mouse that did not
   move is not.
6. **Nothing is sound-only**; the slider at 0 is mute.

## The menu's look, as sound

The menu is the drive-in's **box office and projection booth**: paper tickets with perforations and an "ADMIT ONE" stub,
marquee bulbs, a neon sign that lights a letter at a time, film burn and a projector iris between screens. So the sounds
are objects of that room, made by synthesis (no recordings, no third-party file, no licence entry):

| Object | Where it shows | Sound |
| --- | --- | --- |
| Marquee **bulb** | hover, focus | a glassy tick of a few milliseconds, the quietest sound |
| **Relay** in the booth | a slider step, a select | a small mechanical click; the toggle is a rocker switch, up for on and down for off |
| **Ticket punch** | every press | a thump, the metal of the punch and a snap of paper |
| **Ticket torn** along its perforation | the three ways to start, Start the night, Save, Join | a short rip of fourteen teeth, then the punch and a soft major third: the commit |
| **Slide projector** advance | a tab changes | a two-part "ka-chunk"; forward a little higher than back |
| **Film leader** | a screen pushed or popped | the old rising and falling whoosh, lower and lighter, under the press that caused it |
| **Shutter** | a refused press (a "Coming" row, a locked map) | a dull thud and a short low buzz |
| **Neon sign** | the menu appears, once | a relay clunk, then a buzz that swells with a tick for every letter that catches, to the sign's own timing, and falls away |

## The table (role, event, sound, level, variation)

The levels are the **peak of the Master mix at the default settings** (the UI bus at 80 percent), the target; the
measured numbers are [below](#measured). A *weight* is the rung of the ladder. *Files* are the variant files, *pitch*
the random spread of every play (a level jitter of +-0.8 dB is on every play too). Every line is a line of
`UiSoundTable.ROLES`; a control with no role fails `test_ui_sound_roles.gd`, which walks every screen.

| Role (controls) | Event | Sound | Weight | Level, dBFS | Files, pitch | Cap |
| --- | --- | --- | --- | --- | --- | --- |
| Every control | hover (pointer), focus (key, pad) | `ui_hover` / `ui_focus` | 1 hint | -27 / -26 | 4 and 4, +-0.5 st | 80 ms between hints, at most 5 in a second, none within 150 ms of a heavier sound, none on touch; focus only for keys and the pad, hover only for a pointer that moved |
| `ticket` (Play, Shop, More rows) | press | `ui_press` | 3 press | -17 | 3, +-0.4 st | |
| `ticket_start` (Play together, Quick join, Solo) | press | `ui_confirm` | 4 commit | -13 | 2, +-0.3 st | |
| `ticket_soon` (a "Coming" row) | hover, focus; press | the hint 4 dB under; `ui_refuse` | 1; 3 | -31 / -30; -18 | 2, +-0.3 st | |
| `tab` (a button of the bar) | hover, focus | as every control | 1 | | | the press is silent: the bar's change plays the tab sound once |
| `tab_bar` (the bar, the Settings tabs) | the tab changes (click, Q E, bumpers, PageUp PageDown) | `ui_tab`, +1.5 st going on, -1.5 st coming back | 2 move | -21 | 3, +-0.4 st | none for the tab already showing |
| `chip` (challenge families) | press | `ui_select` | 2 move | -23 | 3, +-0.4 st | |
| `sheet_row` (a challenge) | hover, focus | hint | 1 | | | a press is silent: it only reads |
| `sheet_row_swap` (an order) | press | `ui_select` | 2 | -23 | 3 | |
| `map_card` / `map_card_locked` | press | `ui_select` / `ui_refuse` | 2 / 3 | -23 / -18 | | |
| `button_primary` / `_secondary` / `_ghost` | press | `ui_press`, 0 / -2 / -3 dB | 3 press | -17 / -19 / -20 | 3, +-0.4 st | |
| `back_button` (a button named Back, Cancel, Close, Leave) | press | `ui_back` | 3 | -18 | 3, +-0.4 st | |
| `commit_button` (Start the night, Play, Save, Join, Quick join, Create a night, Continue) | press | `ui_confirm` | 4 commit | -13 | 2 | |
| `toggle` (switch, check box) | on / off | `ui_toggle_on` / `ui_toggle_off` | 2 | -22 | 2 each, +-0.3 st | |
| `slider` | a step crossed | `ui_tick`, -3 to +5 st with the value | 1 | -25 | 3, +-0.3 st | 70 ms between ticks; none for a value set by code |
| `option`, `choice_strip` | a step | `ui_select` | 2 | -23 | 3 | |
| `list` | the highlight moves; activate | `ui_tick`; `ui_press` | 1; 3 | -25; -17 | | as a slider |
| the router | push / pop, Esc | `ui_push` / `ui_pop`, then the back sound for Esc | 2 | -29 / -30 | 2 each, +-0.5 st | under the press that caused it |
| `field` (a text field) | hover, focus | hint | 1 | | | typing is silent |
| `any` (the router, a screen) | confirm, refuse, select, on, off, sign | as above | | | | |
| the neon sign | the menu appears, once | `ui_sign_on` | 5 moment | -18 | 1 | not with reduced motion (the sign is just lit) |

**Deliberately silent**, each written in the table with its reason:

| Control or event | Why |
| --- | --- |
| Scrolling a list, the Credits scroll | continuous: a drag is not an event |
| Typing in a name field | the field's own caret is the feedback; a click a letter tires |
| Dragging the stage to turn the soldier (`stage` role) | continuous |
| A press on a tab that is already showing | nothing changed |
| A challenge that only reads | pressing it does nothing |
| A hint on a finger | no hover on touch: the tap is the press |
| A hint just after a press, a tab or a screen change | the sound already made covers it; the focus moves by itself |
| The sign's flicker every 4.7 s | decided again with the bed in (#926): the bed does not hide it (a hint-weight tick would stand 14 to 24 dB over the bed on every speaker, see [the bed](#the-ambience-bed-926)), so it would be heard as a metronome, 13 times a minute for as long as a menu stays open, and it is the sign's own timer, not an event of the player's. The room is no longer silent, so the sign's lack of a tick no longer reads as a gap; the sign's ignition, once, is the whole of its sound |
| The lobby's "ready" and its countdown | there is neither: the lobby has Start (the host's) and Leave and a status line, and a night begins when the host presses Start. Decided for when they arrive (#926): *ready* is a `toggle` (the on and off pair, weight 2), a countdown is one `ui_tick` a second for the last three seconds and `ui_confirm` at zero; the tick is 17 dB or more over the bed on every speaker already, so the bed changes nothing. They are written here and not as rows of `UiSoundTable` because a row with no control to play it is a dead row, and the test that walks every control has nothing to say about it |
| "X joined" and "X left" in the lobby's note line | words only, a system event; a sound for it is new vocabulary (no weight of the ladder fits a notification) and belongs with the ready sound when the lobby gets one |
| The panel sliding in | the tab sound already went with it |
| Purchase and unlock | the Shop buys nothing yet (a real row's press only shows a note, an ordinary press); when buying lands its event is the till (`till_ring`) |

The menu has an **ambience bed** since #926, so it is no longer silent between its sounds: [below](#the-ambience-bed-926).
It is not a row of the table (it answers no control), and the hint levels above were checked against it and did not
move. A menu **music** bed was not made then ("the menu needs to feel more alive" was met by the bed); it is made
since (issue 979), synthesised, on the Music bus: [the menu's music](menu-music.md). The levels below are of the
first bed, the crickets and the projector; the margins with the music are in that page.

## The ambience bed (#926)

Between its sounds the menu was silent. Now the drive-in is there under it: the projector's motor and, very quietly,
the crickets. `MenuAmbience` (`core/audio/menu_ambience.gd`) starts two beds on the **Ambience** bus, so the slider is
Settings, Audio, "Ambience" (80 percent by default, 0 is mute). Since #979 the menu holds three beds more (a pad and
bells on the Music bus and a wind on the Ambience bus, [the menu's music](menu-music.md)); this section is the first two,
whose trims are now -31 dB (the projector) and -38 dB (the crickets), and the margins in the table are of the bed as it
was then (the new ones are in the music's page):

| Bed | File (the night's own) | Trim | The night's trim of the same file | What it is |
| --- | --- | --- | --- | --- |
| `bed_menu_projector` | `ambience/projector_1.ogg`, 12 s | -25 dB | -14 dB, 3D at the booth | the gate's 24 clatters a second over a motor and a fan: low, mostly under 300 Hz |
| `bed_menu_crickets` | `ambience/crickets_1.ogg`, 24 s | -31 dB | -26 dB | eight insects at 3.7 to 5.3 kHz, singing in bursts |

- **No new file and no new licence.** Both are the Ogg files of the night's beds (synthesised in `night_recipes.py`),
  under quieter trims, flat (2D) in the menu. A bed is a looping stream, never decoded to samples, so it is not in a
  deferred bank (a deferred bank would queue its 36 s for a decode it must not get).
- **When.** It starts with the main menu (`MainMenu.screen_enter`) and fades in over three seconds. Every screen pushed
  over the menu (Settings, Play together, the lobby, Credits) keeps it, so the Ambience slider can be heard as it is
  dragged. It fades out over two seconds when a night is being loaded (`NightScreen._ready`) and comes back with the
  menu (`MainMenu.screen_resume`) after Leave night.
- **Why these two.** They are the drive-in's own, so the night has no sound the menu did not hint at. The motor is low
  and is what a small speaker loses; the crickets are what a phone keeps, and they sing where the hints do
  (2.5 to 6 kHz), so they are the part that decides how loud the bed may be.

### Checked without ears, on a laptop speaker and a phone

The issue asked for a person's ears on a laptop and a phone. Nobody is asked to listen: the mix is **linear**, so a
hint over the bed is the hint plus the bed, and each can be put through a speaker model before they are compared
(`tools/audio/menu_speakers.py`, on the recording of `tests/captures/audio_menu_bed.tscn`, the bed alone through the
real service and buses at the default settings, and the recording of every hint of `audio_menu_levels.tscn`). The models
are **assumed curves, not measurements of a device**, written in the tool's header: `laptop` is a 4th-order high-pass at
280 Hz with a 3 dB presence bump at 2.5 kHz and a low-pass at 13 kHz; `phone` is one driver (the channels summed), a
4th-order high-pass at 500 Hz, a 4 dB bump at 2 kHz and a low-pass at 9 kHz; `flat` is the recording as it is
(headphones). Two margins for every hint:

1. **Peak over the bed's momentary loudness.** The kit's rule: a hint 10 dB over the loudest 400 ms of the bed (K-weighted,
   after the model) is plain. The gate is 10 dB.
2. **In the hints' own band** (1.5 to 8 kHz): the hint's loudest 50 ms rms over the bed's loud 50 ms (its 95th percentile)
   in the same band. A low motor is not in that band and masks nothing there, while a cricket chirp is and does; the
   first margin cannot tell them apart (a first version of the second margin, over the whole spectrum, counted the
   motor and failed the "Coming" hints for a bed that did not bury them). The gate is 6 dB.

| | flat | laptop | phone |
| --- | --- | --- | --- |
| Bed, loudest 400 ms (LUFS-M) | -42.4 | -45.7 | -49.5 |
| Bed, median 400 ms | -44.2 | -50.2 | -54.5 |
| Hover, peak over the bed / in its band, dB | 14.9 / 10.2 | 20.0 / 11.6 | 23.8 / 12.4 |
| Focus | 16.3 / 10.8 | 20.1 / 11.5 | 24.5 / 13.5 |
| Tick | 17.1 / 10.0 | 22.2 / 11.2 | 26.3 / 12.7 |
| Hover on a "Coming" row (4 dB under) | **10.9** / **6.2** | 16.0 / 7.7 | 19.8 / 8.5 |
| Focus on a "Coming" row | 12.3 / 6.8 | 16.1 / 7.5 | 20.4 / 9.5 |

- **Every hint passes on every model.** The quietest, the "Coming" hover on a flat speaker, has 0.9 dB over the first
  gate and 0.2 over the second: the bed is as loud as the hints allow (+2 dB on both trims fails both gates), *quiet
  but not silent*. The night's crickets alone are 5 dB louder (-26 dB against -31 dB).
- **The smaller the speaker, the plainer the hints.** The motor is under what a laptop plays (the bed's loudest 400 ms
  falls 3.3 dB) and what a phone plays (7.1 dB), and the hints sit where both speakers keep them. On a phone the bed is
  mostly the crickets. That is the price of a hint that stays plain, not a fault. **No hint trim moved**: the one-line
  changes in `ui_menu.tres` that the issue allowed for were not needed.
- **What was not tested** is what only a person can tell: whether the bed is pleasant, whether it is heard at all in a
  noisy room, and how a real speaker differs from the curves above. The numbers say the hints are plain; they do not
  say the bed is good. The slider is the answer to taste.
- **Pinned.** `tests/core/menu_bed_levels.json` (written by `menu_speakers.py --pin`) holds the trims, the hints' levels
  and the worst margins the check found; `test_menu_bed_levels.gd` fails when a trim or a hint level has changed since
  (the message says to run the tool again) and when a margin under the gates was written.

### What it costs to load

| | Cost |
| --- | --- |
| New bytes in the pack | **0**: the same two Ogg files (330 KiB) as the night's beds |
| The night's loading bar | **0** files read and **0** decoded for the bed: the night's warm-up finds both files read already (`test_the_nights_warm_up_has_nothing_more_to_read_or_decode_for_the_bed`). The web smoke's night load ratio is below |
| Starting the bed in the menu | **2.9 and 3.7 ms**, once, in the frame the menu is entered (reading and opening the two files), after the sign's own sound has paid the engine's first use of an Ogg (30 to 37 ms) |
| Mixing it, native | 0.009 and 0.014 ms per 60 Hz frame on average, 0.095 ms at the worst: 0.14 percent of a frame |
| The catalog | 199 sounds (197), two more rows in `tests/tuning/sound_defaults.json` |
| Web build, night load (`smoke.py`, headless Chromium, SwiftShader, this machine) | Night 10.4 s and 10.4 s, menu 6.8 s and 6.5 s, ratio **1.30** and **1.30** (two runs); `origin/main` without the bed on the same machine and day: night 11.6 s and 10.3 s, ratio 1.45 and 1.29. Both far under the gate (5.5), and no console or page error |

A bed's **player pool** was too small once the menu had a bed: the night's beds (up to seven: crickets, highway, score,
wind, the world's bed and the small map's two) take two seconds to fade out after the night and hold their players, and
the pool had six, so the menu's bed, started the moment Leave night returned to the menu, found no free player and was
silent (`start_bed` returns null with no warning). `AudioService.POOL_BEDS` was 10 and is 12 since the menu holds
five beds (#979), and `test_menu_ambience.gd` leaves a
night at once to prove it.

### The walk, before and after

The same walk (`tests/captures/menu_sfx_tour.tscn`, 52 s, mouse and keys as a player sends them) on #925's menu and with
the bed; a recording with sound of each, the plot of both and the speaker plot are on the pull request. The 97 sounds
are the same ones (a bed is no play of a sound: the service's `played` signal does not carry beds).

| | Before (#925, no bed) | After |
| --- | --- | --- |
| Quietest 100 ms of the walk after the sign | digital silence | -34.3 dBFS peak (the bed) |
| Silent stretches of 3 s or more (under -60 dBFS) | 0 | 0 |
| Peak of the mix | -12.1 dBFS | -12.2 dBFS |
| Most hints in one second; least gap between hints and between ticks | 5; 0.133 s; 0.100 s | 5; 0.133 s; 0.100 s |
| Clipped samples | 0 | 0 |

## The sounds and where they come from

All **synthesised** in `tools/audio/ui_recipes.py` (noise, filtered clicks, damped sines, the same `dsp.py` as the
rest), seeded from the sound's name, 36 files of 0.03 to 0.37 s and the sign's 2.5 s, every one normalised to -6 dBFS:
the levels are the trims in `core/audio/banks/ui_menu.tres`. Original work with nothing third-party, so there is no
licence entry and nothing waits on the maintainer. The seven old interface sounds (`ui_hover` and the rest) are made
again in the same family (same ids, new files, variants), and `ui_confirm`, `ui_tab`, `ui_select`, `ui_toggle_on`,
`ui_toggle_off`, `ui_refuse` and `ui_sign_on` are new. Seen without ears: a spectrogram sheet of each (`analyze.py
sheet`) for the shape; whether it *sounds good* is a human's call, and every number is one line of the bank.

## How they load

- **Not behind the night's loading bar.** The menu's sounds are the bank `ui_menu.tres` with `deferred = true`: a
  night's warm-up only queues their files. The seven old ones were behind the bar (0.75 s of sound decoded); now **0
  s**, and the budget test of the night (`WARM_DECODE_BUDGET_S`) reads less than before. The HUD's `points_*` and
  `challenge_*` stay in `ui.tres`, as before.
- **The menu decodes them in the background**: `Audio.start_background_preload` (after the menu's first second, 3 to
  40 ms a frame) decodes every sound, the UI bank first in the catalog's order. A sound played before its turn plays
  from its Ogg.
- **The amount.** 36 files, **6.9 s of sound, 187 KiB** (the old seven: 0.75 s, 28 KiB). Decoding all of it to samples
  is **70 to 86 ms** on this machine (32 to 40 ms of reading the files, the rest the decode), spread over many frames
  of the menu, none of them before the first paint. The web build's decode is a GDScript loop: 152 s of sound cost
  about 4 s there ([web export](web-export.md)), so 6.9 s is about **0.18 s**, in the menu's background slices, not
  behind a bar.
- **The first paint.** No sound plays before the menu shows (the sign's starts when the menu is entered, 0.4 s on). A
  cold first play of a sound costs 1.7 to 2.5 ms (reading its file); the very first sound of a session costs about 30
  to 37 ms once (the engine's first use of an Ogg and a player), which used to land on the player's first click and
  now lands on the sign at the menu's entry. `tests/core/test_menu_sound_levels.gd` caps the bank at 8 s of sound and
  230 KiB, and checks that it is deferred and on the `UI` bus.
- **In a browser.** A web export of this branch passed `tools/web_smoke/smoke.py` (headless Chromium, SwiftShader): no
  console or page error, the menu in 6.2 s and the night 10.5 s after it (ratio 1.31, the gate is 5.5).

## Measured

`tools/audio/menu_levels.py levels` on a recording of `tests/captures/audio_menu_levels.tscn` (every sound of the
table alone through the real service and the buses at the default settings, every variant file). Peak is dBFS of the
mix, LUFS-M the loudest 400 ms (K-weighted). Targets are `tests/core/menu_sound_levels.json`, also read by the test,
which predicts the level from the files and the trims and agrees with the recording within 0.1 dB (all eighteen rows
of the table).

| Sound (trim) | Peak, mean of variants | Target | LUFS-M |
| --- | --- | --- | --- |
| hover / focus | -27.5 / -26.2 | -27 / -26 | -46 / -46 |
| hover, focus on a "Coming" row | -31.5 / -30.1 | -31 / -30 | -50 / -50 |
| tick | -25.4 | -25 | -47 |
| select, toggle on, toggle off | -23.1, -22.4, -22.0 | -23, -22, -22 | -47, -44, -44 |
| tab | -21.2 | -21 | -38 |
| push, pop (under a press) | -29.2, -29.8 | -29, -30 | -40, -41 |
| press (primary, secondary, ghost) | -17.1, -19.0, -20.1 | -17, -19, -20 | -36, -38, -39 |
| back, refuse | -18.1, -17.9 | -18, -18 | -37, -35 |
| confirm | -13.2 | -13 | -27 |
| sign on | -18.4 | -18 | -32 |

- **Every sound within 0.6 dB of its target** (the tolerance is 2.5), no sample over -13 dBFS, **no clipped sample**
  in the recording. The ladder holds on the medians of the rungs: +4.7, +4.6 and +4.9 dB in peak, +4.5, +5.6 and +9.9
  LU in loudness (hint, move, press, commit).
- **Against the night** (same recording): a pistol shot at 1 m peaks -8.6 dBFS (-23.6 LUFS-M), a footstep of your own
  -20.0, a groan at 6 m -12.5, the till -6.8. The loudest menu sound, the commit, is -13.2 dBFS and 3 LU under the
  pistol, and a hint is 6 dB under your own footstep in loudness.
- **The walk** (`tests/captures/menu_sfx_tour.tscn`, the same script on `main` and here; `tools/audio/menu_levels.py
  tour`):

| | Before (main) | After |
| --- | --- | --- |
| Sounds in the 52 s walk | 48 (all from Settings, Credits, the Play screen and the wardrobe) | 97, in every tab |
| Silent stretches of 3 s or more | 3 (the Play column, the tabs, the Shop and the Challenges: the first 26 s made 2 sounds) | 0 |
| Ticks under one slider drag | 16 in 1.7 s, 66 ms apart | 9, 100 ms apart (the least gap allowed is 70 ms) |
| Most hints in one second | 2 (Settings only) | 5 (the cap), in a fast sweep over the three starts |
| Peak of the mix | 0.0 dBFS, 44 clipped samples (a Back played the click at -4 dBFS and the whoosh together) | -12.1 dBFS, none |

Plots and a recording with sound of both walks are on the pull request.

## Tests and tools

- `tests/core/test_ui_sounds.gd` (the rules: gap, burst cap, touch, pointer and keys, after a heavier sound, slider
  gap and pitch, tab direction, toggle, role by words, no role found, same-sound gap),
  `tests/ui/test_ui_sound_roles.gd` (every interactive control of every tab of the main menu and of Settings, the
  Play, Together, Join, Customize, Credits and lobby screens has a role with the rows its events need; the menu's
  controls send the right cues when driven; no `UIAudio.play` in the game or the addon is called without its source),
  `tests/core/test_menu_sound_levels.gd` (levels, ladder, load), `tests/core/test_audio_service.gd` (every sound of
  the table exists), `tests/tuning` (every sound's values).
- Captures: `tests/captures/menu_sfx_tour.tscn` (the walk, with Movie Maker, mouse and keys as a player sends them)
  and `tests/captures/audio_menu_levels.tscn` (every sound alone). Both through `gds godot --`, the mix is the movie's
  audio: `ffmpeg -i m.avi -vn -c:a pcm_s32le m.wav`.

## What went wrong, and what is open

- **The bank was the loud part of the menu.** The old `ui_press` peaked at -4 dBFS in the file (-6 in the mix): as
  loud as a gun, and a Back put a click and a whoosh on top of each other at 0 dBFS. The whooshes are noise: at the
  same *peak* as a click they are 8 to 10 LU louder, so the first set of levels (equal peaks by rung) had the screen
  change louder than the press that caused it and the commit louder than a pistol shot. The ladder is read on both the
  peak and the loudness now.
- **Open**: a person's taste on the bed and the hints (the speaker check says they are plain, not that they are good;
  see [the bed](#the-ambience-bed-926)); a person's taste on the menu's music (made since, #979); the shop's
  purchase sound when buying exists; the lobby's ready and countdown sounds when the lobby gets them (decided in the
  table of silences above).
