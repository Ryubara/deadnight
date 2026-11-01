# HUD

What building the in-game HUD (`game/ui/hud/`) taught us. The design, parts and feed are in [HUD](../design/hud.md).

## What worked

- **One plain-data mirror between the rules and the screen.** `HudState` takes the rules' event dictionaries and the
  local player's own readings and nothing else; parts only read it. A test feeds a real `GameRules` night through it and
  another checks the state holds no `Object`. A snapshot (`GameRules.to_dict()`) rebuilds it for a late joiner.
- **Time as a parameter.** Every moving part has `advance(delta)` and `_process` only calls it, so tests step the HUD
  by fixed amounts and Movie Maker captures repeat frame for frame. Tweens are used only where no test needs the
  mid-value (the reel roll, the prompt shake).
- **A layout test beats looking.** Captures at 1080p and 1440p were clean; a test that builds the busiest HUD at the
  canvas of every window from 1024 x 768 to 4K at UI scales 0.8 to 1.25 (canvas = window / (fit x scale), stretch
  `canvas_items`, aspect `expand`) found 17 overlaps at 1536 x 864. The fixes were structural (fixed row widths, list
  caps, one party ticket), not nudges.
- **Fonts through two token slots.** `UITokens.font_display` and `font_text` default to null (the engine fallback). The
  HUD, drawn strings included, asks `tokens.display_font()` and `text_font()`. A capture loads the recommended pair from
  outside the repository, so the committed HUD runs and tests without a font file.

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

## In the night

The night feeds the HUD through `NightHudBinding` (`game/gameplay/night/`), from `ClientState.event_received` alone;
see [the slice](../design/slice.md#the-hud). Things the binding taught:

- Rules actions applied outside the server's tick (a test granting points) are not in any client's events: the server
  clears its outbox at each `step`. A test that needs the HUD to hear one delivers the returned events itself
  (`night.state.apply_events(rules.apply(...))`).
- `HudFeed.ITEM_NAMES` has no entry for `door_yard`: buying the generator yard is announced as "BOUGHT SOMETHING".
- At 1920 x 1080 the circuit labels under the generator bar touch each other ("SCREENSNACKSBOOTBACK LOT").

## Left out, to do

- Player health and blows are not rules events; `player_hurt` is a HUD event until the rules own them.
- Ammo comes from the frame (the held weapon), reload and equipment are not shown; the weapons' own events do not
  feed the HUD (#133).
- Markers are given in screen space; projecting world points (and hiding those behind walls) is the camera's job.
- The prompt looks only at one interaction; two in reach at once needs a choice rule from the player controller.
