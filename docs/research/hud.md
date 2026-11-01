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
- `Font.get_string_size` shapes the string, which is the cost of fitting text: guess the size from one measurement
  (size x room / width) and step down from there. Looping down 4 units at a time made one banner take 6 ms.
- Count node creation with `get_tree().node_added` filtered to a subtree (`is_ancestor_of`): it needs no engine hook and
  proves a part makes no nodes. `Performance` monitors count nodes waiting to be freed too.
- Parts refreshing on every change is invisible until something changes every frame (the break countdown) or a batch
  lands (58 events from one tick). Mark topics, announce once, and make `set_*` a no-op when the value is the same.
- A snapshot restore that calls `team.clear()` wipes what the snapshot does not carry (names). Rebuild from the snapshot
  and put back what the old state knew about the players still in it.

## In the night

The night feeds the HUD through `NightHudBinding` (`game/gameplay/night/`), from `ClientState.event_received` alone;
see [the slice](../design/slice.md#the-hud). Things the binding taught:

- Rules actions applied outside the server's tick (a test granting points) are not in any client's events: the server
  clears its outbox at each `step`. A test that needs the HUD to hear one delivers the returned events itself
  (`night.state.apply_events(rules.apply(...))`).
- `HudFeed.ITEM_NAMES` has no entry for `door_yard`: buying the generator yard is announced as "BOUGHT SOMETHING".
- At 1920 x 1080 the circuit labels under the generator bar touch each other ("SCREENSNACKSBOOTBACK LOT").

## Ammunition and equipment from the weapons

The ammo card and the equipment slot are fed by the weapons' events (`HudLoadout`), with no change to the weapons.

- The HUD never asks the weapons what a player holds; `weapon_equipped` carries `ammo` and `reserve`, and `shot_fired`
  and `reload_finished` carry them again, so the card is the last event's numbers. Whatever the shop does to the
  reserve (#152) reaches the card the same way, as long as the events keep those two fields.
- **Equipment is the weapon put away last.** The design page calls it "a flare, a trap" and nothing in the game is one,
  so the slot shows the other weapon of a swap with the rounds it has left (magazine and reserve together). A weapon
  with no ammunition (the crowbar, known from `WeaponDef.is_melee`) shows its name and no count, and the card shows `--`.
  With three weapons carried only the last two are in view.
- A HUD that joins after the weapons were given has heard no event: the binding hands it the frame's weapon once, then
  leaves the card to the events.
- `HudState` may hold no `Object` (a test checks), so the loadout is static functions over plain fields of the state
  (`weapon_id`, `holstered_id`, `rounds`), not a helper object kept in it.
- The equipment row measured the name and the count apart; shaping the pair is a couple of pixels wider, so the count
  was the part that got an ellipsis (`REVOLVER  x...`). It measures the whole text now and keeps one space.

## Left out, to do

- Markers are given in screen space; projecting world points (and hiding those behind walls) is the camera's job.
- The prompt looks only at one interaction; two in reach at once needs a choice rule from the player controller.
