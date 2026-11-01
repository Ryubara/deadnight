# HUD

What building the in-game HUD (`game/ui/hud/`) taught us. The design, parts and feed are in [HUD](../design/hud.md).

## What worked

- **One plain-data mirror between the rules and the screen.** `HudState` takes the rules' event dictionaries and the
  local player's own readings and nothing else; parts only read it. A test feeds a real `GameRules` night through it and
  another checks the state holds no `Object`. A snapshot (`GameRules.to_dict()`) rebuilds it for a late joiner.
- **Time as a parameter.** Every moving part has `advance(delta)` and `_process` only calls it, so tests step the HUD
  by fixed amounts and Movie Maker captures repeat frame for frame. Tweens are used only where no test needs the
  mid-value (the reel roll, the prompt shake).
- **A layout test beats looking, if its values are the worst ones.** Captures at 1080p and 1440p were clean; a test that
  builds the busiest HUD at the canvas of every window from 1024 x 768 to 4K at UI scales 0.8 to 1.25 (canvas = window /
  (fit x scale), stretch `canvas_items`, aspect `expand`) found 17 overlaps at 1536 x 864. It then passed while real
  names, a three-digit round, 12,345,678 points, 999 / 9999 ammo and the Marquee typeface overlapped there (#141): it had
  short values and the fallback font. It now also runs the longest content and a wide face (a `FontVariation` of the
  fallback stretched 1.4 times, so CI without font files still tests a wide face) and the real Marquee pair when
  `refs/fonts` is found. The fixes are structural (a width per part, text that shrinks then ellipsizes, one line per
  feed row, the prompt reflowed), not nudges.
- **Fonts through two token slots.** `UITokens.font_display` and `font_text` default to null (the engine fallback). The
  HUD, drawn strings included, asks `tokens.display_font()` and `text_font()`. A capture loads the recommended pair from
  outside the repository, so the committed HUD runs and tests without a font file.

- **Test the ordinary as well as the worst.** The worst-case suite proves nothing overlaps because text gives way, so
  it passes while everyday text is cut (#170: at 1080p `SNACKS` and "PLAYER 1 OPENED THE CONCESSION STAND" ended in
  ellipses). A second suite holds the typical values at the common canvases to "no ellipsis"; a label counts as cut when
  its text is wider than its box (a trimmed label's `text` still holds the whole string). Fix the layout (a grid, a
  wider row) before reaching for abbreviations.
- A part's own width is not its neighbours' room: the event rows are wider than the column because the space left of it
  is empty. The overlap test found the one neighbour (the banner, at a fraction of the screen height) at once.

## Godot behaviour worth knowing

- `Control.set_anchors_preset(PRESET_FULL_RECT)` on a Control made in code leaves it 0 x 0 (the offsets keep the old
  rect); use `set_anchors_and_offsets_preset`. Nothing warns: the HUD's world markers drew at the top-left corner.
- A custom `_draw` that depends on `size` must redraw on `resized`, or it keeps the first (zero-size) frame.
- Redraw when a value falls to zero too: a frame that fades out stayed on screen because `queue_redraw` ran only
  while the strength was above zero.
- `GameRules.BuyResult` values are usable as constant dictionary keys outside the rules (`HudPrompt.DENIED_TEXT`).
- Movie Maker records at the window size from the project, not `--resolution`; use an uncommitted `override.cfg` with
  `window/size/window_width_override` and `window_height_override`.
- Strict GDScript warnings are errors here: `var x := a if c else {}` types as `Variant`; write `var x: Dictionary =`.
- A new worktree has no `game/addons/gdUnit4` (git-excluded): copy it from another worktree and import once.

- A `Label` takes its text's width as its minimum unless it may trim: with `clip_text` or an ellipsis overrun its minimum
  width is 0, so give it a `custom_minimum_size.x` or an expanding parent. Containers then stay the width you chose.
  Autowrap labels in rows inflate the row (a wrapped feed row doubled the column until it was made one line).
- A card whose words must all be read wraps instead of ellipsizing (#308): `HudStyle.wrap` turns autowrap on with no extra
  line gap and `HudStyle.set_wrapped` shrinks the type, then sets `custom_minimum_size.y` from
  `Font.get_multiline_string_size` at the room it has. An autowrap `Label` learns its wrapped height a frame after it is
  resized, so reserving the height at once keeps the card from jumping. `test_hud_prompt_fit.gd` walks every prompt the
  night makes (through `NightHudBinding.show_prompt`), every refusal and every card kind at desktop and phone-landscape
  canvases and fails on an ellipsis, a line wider or taller than its label, or a card off the screen or over a part.
- `Font.get_string_size` shapes the string, which is the cost of fitting text: guess the size from one measurement
  (size x room / width) and step down from there. Looping down 4 units at a time made one banner take 6 ms.
- Count node creation with `get_tree().node_added` filtered to a subtree (`is_ancestor_of`): it needs no engine hook and
  proves a part makes no nodes. `Performance` monitors count nodes waiting to be freed too.
- Parts refreshing on every change is invisible until something changes every frame (the break countdown) or a batch
  lands (58 events from one tick). Mark topics, announce once, and make `set_*` a no-op when the value is the same.
- A snapshot restore that calls `team.clear()` wipes what the snapshot does not carry (names). Rebuild from the snapshot
  and put back what the old state knew about the players still in it.

## Alignment, scale and the player boxes (#218)

- **Align by measuring rectangles, from two lines.** The left text line (`PAD_LEFT`) and the right one (`PAD`) are
  constants of `HudStyle`; every card pads by them and the feed rows end on the right one. `test_hud_grid.gd` then
  checks edges, gaps and first labels against them at every canvas; a one-unit nudge of either constant fails it.
  Picking edges by eye had left the left column's text at three different lines.
- **Baselines come from the font, not from the box.** Two labels of different sizes in one row share a baseline when
  each is placed at `baseline - font.get_ascent(size)` (a plain `Control` with positions) or, in a container, when the
  smaller one is lifted by the difference of the descents (`MarginContainer` bottom margin on the reserve in the ammo
  card). `SIZE_SHRINK_END` alone aligns the bottoms of the boxes, which is not the baseline.
- **A label is taller than its text.** At 32 units a label's line is about 45 units; a 42-unit box put its label
  rectangle outside the box (the grid test caught it). Size a box from the line height it must hold.
- **One scale constant.** Lengths are the old ones times `HudStyle.UNIT`, written out (GDScript constants are folded:
  `const A := int(120 * U)` works, but plain numbers read better); type is scaled less and floored at `MIN_TEXT`.
  The menu tokens' spacing is not the HUD's: `HudStyle.XS` to `LG` are.
- **A portrait in a HUD costs one frame.** A `SubViewport` with its own `World3D`, the assembled Soldier and
  `render_target_update_mode = UPDATE_ONCE` two frames after the model enters (its idle clip has to pose it) gives a
  texture a `TextureRect` shows forever. Tests that have no use for the picture set `HudPortrait.live = false`; the
  fixture does by default.
- **Do not `git checkout` a file to undo an experiment** in a worktree full of uncommitted work: it reverts all of it.
  Use `git stash` or edit the line back.

## In the night

The night feeds the HUD through `NightHudBinding` (`game/gameplay/night/`), from `ClientState.event_received` alone;
see [the slice](../design/slice.md#the-hud). Things the binding taught:

- Rules actions applied outside the server's tick (a test granting points) are not in any client's events: the server
  clears its outbox at each `step`. A test that needs the HUD to hear one delivers the returned events itself
  (`night.state.apply_events(rules.apply(...))`).
- `HudFeed.ITEM_NAMES` has no entry for `door_yard`: buying the generator yard is announced as "BOUGHT SOMETHING".
- At 1920 x 1080 the circuit labels under the generator bar touch each other ("SCREENSNACKSBOOTBACK LOT").

## Ammunition and equipment from the weapons

The ammo card and the equipment slot are fed by the weapons' events and the frame (`HudLoadout`), with no change to the
weapons.

- The HUD never asks the weapons what a player holds; `weapon_equipped`, `shot_fired`, `reload_finished` and
  `ammo_added` carry `ammo` and `reserve`, so the card is the last event's numbers, and the frame's `weapon`, `ammo`,
  `reserve`, `reloading` and `arms` correct it every tick (`HudLoadout.sync`).
- **Rounds bought did not show until a swap (2026-11-01).** The card listened to equip, shot and reload only, so a
  locker or a wall buy of a weapon already carried (`ammo_added`, which the server did send) changed the server and
  not the card; the next `weapon_equipped` of a swap re-read it. A test that bought rounds and asserted the card,
  instead of one that only fired and reloaded, would have caught it (`test_night_hud_ammo.gd`). The rule that
  follows: a readout of a number the server owns reads it from the frame, and events only make it quicker.
- **Equipment is the weapon put away last.** The design page calls it "a flare, a trap" and nothing in the game is one,
  so the slot shows the other weapon of a swap. A weapon with no ammunition (the crowbar, known from
  `WeaponDef.is_melee`) shows `--` on the card. With three weapons carried only the last two are in view. The slot
  first showed the rounds it has left too (`REVOLVER x6`); the maintainer called that readout redundant on 2026-11-01
  (#218) and it is gone: the slot is the weapon's name, the state still holds `equipment_count`.
- A HUD that joins after the weapons were given has heard no event: the frame's weapons fill the card on the first tick.
  The frame reaches the HUD one tick after the server built it, so a change with no event shows on the second tick.
- `HudState` may hold no `Object` (a test checks), so the loadout is static functions over plain fields of the state
  (`weapon_id`, `holstered_id`, `rounds`), not a helper object kept in it.
- A count beside a name must be measured with the name (shaping the pair is wider than the two measured apart); with
  no count in the slot this no longer applies, the name alone is cut to the card's width.

## Left out, to do

- Markers are given in screen space; projecting world points (and hiding those behind walls) is the camera's job.
- The prompt looks only at one interaction; two in reach at once needs a choice rule from the player controller.

## Stacking rows that slide (#240)

- **A `VBoxContainer` teleports.** It sorts its children on every change, so a row that leaves moves every row under it
  at once. `HudRowStack` is a plain `Control` that sets each row's `position.y` itself and eases it toward the slot.
- **Ease by a fraction of what is left, not by a distance per frame.** `1 - exp(-delta * 3 / SETTLE_TIME)` of the
  remaining distance gives the same place after the same time at any step (a test steps 1, 2, 4 and 8 times over 0.08 s).
  Because every row moves by the same fraction, the gap between two rows is a blend of the old gap and the slot gap and
  never shrinks below the slot gap: rows cannot overlap while they slide.
- **A new row must start under the row before it.** Starting at its own slot overlapped the previous row whenever that
  row was still on its way (six gains in one frame, the cap dropping the oldest as each came in): the first test of the
  burst failed on it. The start is the lower of the slot plus the rise and the previous row's bottom plus the gap.
- Fade a new row in with `self_modulate`, which multiplies with the `modulate` the owner already uses for its own fade.
- A capture of a slide needs 30 fps: at 10 fps the 0.18 s slide is two frames.
