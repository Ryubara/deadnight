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
| The sign's flicker every 4.7 s | a sound that repeats on a timer is noise; revisit with an ambience bed (no menu music exists) |
| The panel sliding in | the tab sound already went with it |
| Purchase and unlock | the Shop buys nothing yet (a real row's press only shows a note, an ordinary press); when buying lands its event is the till (`till_ring`, #?) |

Not in the table because it does not exist yet: a menu **music** bed (the menu is silent between sounds) and a menu
**ambience** (the drive-in's crickets and the projector). Both would make the menu feel alive more than any click;
they are a follow-up, and the hint levels above are set for a silent room.

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
- **Open:** a human's ears on a laptop speaker and a phone (whether a hint at -27 dBFS is plain; it is one number in the
  bank); a menu ambience and music bed; the shop's purchase sound when buying exists; the lobby's ready and countdown
  sounds (the lobby has no countdown today).
