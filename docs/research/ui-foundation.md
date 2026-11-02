# UI foundation

Decisions behind the `gds_ui` addon (`game/addons/gds_ui/`), written while building it. The addon names no Deadnight
content, so it can move to the GDStudio kit unchanged; its own `README.md` is the reference for the tokens, the project
settings, the audio cues, the router calls and how to restyle.

## Tokens and theme

`UITokens` (a `Resource`) holds every colour, type size, spacing, radius, duration, tint, shader palette and spring
value. Nothing else in the addon reads a literal of those kinds ([below](#every-literal-is-a-token-21)).
`UIThemeBuilder.build(tokens)` generates the `Theme`: label type variations (`UILabelDisplay` ... `Overline`),
button variations (`UIButtonPrimary/Secondary/Ghost`) and panel variations, plus a usable look for plain `Button`,
`Label` and `PanelContainer`. A game restyles everything by saving a `UITokens` resource and pointing the project
setting `gds_ui/tokens` at it. Fonts are three token slots (`font_display`, `font_text`, `font_mono`, #11): the theme
applies the display face to the display and title labels, the text face to the rest and the mono face to
`UILabelMono`; an unset slot is the engine's fallback font (mono: the text face with tabular figures). Deadnight sets
Bungee Inline and Barlow Condensed ([typography](../design/typography.md#decision)).

### Every literal is a token (#21)

Review (#21) found that the first version still hid its drive-in look in literals, so a second game could not restyle
it through tokens. They are now tokens, with the old values as defaults (a capture of the default look before and after
is the same picture, apart from the stars' places):

- **Shader colours** are uniforms (`burn_hot`, `burn_flame`, `burn_ember`, `burn_char`, `iris_shade`, `iris_rim`,
  `iris_rim_hot`) named like the tokens; `UITransitionShader.feed_tokens` sets every shader uniform that has a colour
  token of the same name, so a game's own shader gets a palette by naming a uniform. A test lists each `vec3` uniform
  of both shaders and fails when one is not a token. The uniforms carry no `source_color` hint: the colours are the
  raw values that were constants, and the Compatibility renderer draws them unchanged.
- **Slide** dim and parallax (`slide_dim`, `slide_parallax`), the **shader half length** (`shader_half_scale`),
  **button tints** (`tint_hover` 0.14, `tint_press` 0.18, `ghost_hover_alpha` 0.85, `disabled_alpha` 0.9), the
  **marquee** chase (`bulb_spacing`, `bulb_radius`, `chase_speed`, `chase_period`) and the **emboldening** ratios
  (`embolden_heading_ratio`, `embolden_button_ratio`, `embolden_option_ratio`).
  One drift: the toggle, option selector and plain `Button` used 0.14, 0.1, 0.12 and 0.2 for their hover and press tint;
  they now share `tint_hover` and `tint_press`, so their tints moved by at most 0.04.
- **The star backdrop** is `star_count` (0 draws none), `star_seed` and `star_band` on the tokens plus `UIScreen.stars`
  per screen. The old seed was the year of the game's setting; the default seed is now 1, so the demo's stars sit
  elsewhere.
- The demo says "UI DEMO" and tints its detail screens from tokens (the old fixed browns made a light palette look
  half-restyled in the first capture).

### Changing tokens at runtime (#21)

`UITokens.set_active(tokens)` emits `UITokens.active_changed()`. The router listens (stage theme, clear colour) and so
does every addon component (springs, radii, minimum sizes, stars); `set_active(null)` returns to the project setting.
Before this, `set_active` after the router's `_ready` did nothing, because the router and each component cached the
tokens. The pattern for a component is one `_apply_tokens()` that reads the active tokens into everything the node
cached, called from `_init` and from the signal handler; game nodes outside the addon (the HUD, the skin) still cache
`UITokens.active()` and need the same two lines to follow a swap, which no screen does today.
`UIMotion.reduced` already followed live (a setter emitting `changed()`); the marquee panel did not: it decided in
`_ready` whether to run its chase. It now follows `changed()`.

A light palette (`game/addons/gds_ui/demo/light_tokens.tres`) restyles the demo menu, the component sheet and the film
burn with no change to a screen (captured at startup and swapped live while the menu showed;
`test_ui_tokens_restyle.gd` asserts the same on the instances). Two lessons from making it: hover *lightens* a raised
fill, so a light palette needs `surface_raised` darker than `surface`; and the default `shadow` (black at 55%) is a
dark-skin value, so a light palette sets its own, softer one.

## Components are drawn, not styled

A `StyleBox` cannot ease between states, so the theme gives the button's states an empty box (plus content margins) and
`UIButton` draws its own fill, shadow and focus ring from springs. The drawing goes on a child control with
`show_behind_parent`: a script `_draw` on a `Button` runs after the native draw, so a fill drawn there covers the text
(found by capture, not by reading the docs).

## Motion values

| What | Value | Why |
| --- | --- | --- |
| Hover lift | scale +3.5%, shadow 14 to 26 px | Reads as "raised" without moving layout |
| Press squash | scale -5%, shadow to 0 | Immediate, so it uses the stiffer spring |
| Focus ring | gap 6 px, closes in from 16 px, 3 px stroke | The ring "lands" on the button |
| Spring | stiffness 360, damping 24, fixed 1/240 s step | Settles in about 0.3 s, no visible overshoot; the fixed step makes captures repeat |
| Screen fade | 0.14 s out (cubic in), 0.40 s in (quart out, rise and settle) | Leave fast, arrive gently |
| Slide | 0.5 s, expo out, old screen at 1/3 distance and dimmed | Parallax shows depth; a pop mirrors the push with the popped screen on top |
| Shader transitions | `shader_half_scale` 1.2 x `dur_screen` 0.5 s per half | One sweep to cover, one to reveal |

No easing is linear. Reduced motion (`UIMotion.reduced = value` at any time; project setting `gds_ui/accessibility/reduced_motion`
gives the start value) makes movement snap and swaps slide, burn and iris for the fade.

The focus ring shows only after keyboard or gamepad input (`UIInputMode.pointer` is false); a mouse user sees hover.
Hovering also moves focus, so the two never disagree.

## Shader transitions in the Compatibility renderer

The film burn and the iris are canvas-item shaders on a full-screen `ColorRect`. They are procedural (hash-based value
noise, four octaves) and never sample the screen: `hint_screen_texture` needs a back-buffer copy, which is slow and
fragile in WebGL2. Instead the transition runs in two halves over a black that belongs to the shader: it closes over the
old screen, the router swaps the screens behind it, then it opens on the new one. Both halves are driven by one
`progress` uniform eased in GDScript.

- Closing eases in (quad) and opening eases out: with cubic in-out both tails sat on a blank or black frame for a third
  of a second.
- The burn front is `mix(-edge, 1 + edge, progress) - (0.72 * distance + 0.28 * noise)`, so the fire is always fully
  closed at `progress = 1` and fully clear at the end of the reveal.
- The iris origin and the burn origin are the focused control's centre, so the transition grows from the button pressed.
- Tested: the burn, the iris and the slide ran in a web export (Chrome, WebGL2, Compatibility) with no console error;
  not yet on Firefox or a mobile GPU. The burn stops its close at `BURN_CLOSE_TO` and starts its reveal at
  `BURN_REVEAL_FROM` so the screen is not held on char; the hash is the shared sine-free `gds_hash.gdshaderinc`
  and the iris `atan` is defined at the origin. Details in [Main menu](main-menu.md).
- `UIMotion.changed()` signals a change of `reduced`; skins listen to it instead of reading the flag once.

## Router

`UIRouter` is an autoload (the plugin adds and removes it) on a `CanvasLayer`. Calls are queued while a transition runs
and input is blocked. A pop mirrors the push it undoes ([below](#a-pop-mirrors-the-push)), not a plain reversal: for the
slide, the layering differs. Tweens must not be created on a screen whose `process_mode` is disabled (paused screens
are), or they never run: the router restores the mode before each transition.

### A pop mirrors the push

| Kind | Push | Pop |
| --- | --- | --- |
| Fade | old fades out, new rises in | the same, with the popped screen fading out |
| Slide | new slides in from the right on top; old moves 1/3 left and dims | popped screen slides off to the right on top; old moves in from 1/3 left and brightens |
| Burn, iris | close over old, swap behind the overlay, open on new | the same, from the focused button |

Fade, burn and iris show one screen at a time (the shader overlay covers the swap), so their child order does not
matter. Only the slide has two screens on show at once, so it raises the leaving screen (pop) or the entering one
(push) to the top of the stage itself (`UITransitionContext.raise`); the stage's child order is never relied on.

### A freed screen must not stall the router

A screen can be freed while a transition runs (game over, a disconnect, a scene change). Rules that keep the queue
draining:

- **Bind a transition's tweens to the stage, never to a screen.** A tween created on a node is killed when the node is
  freed and its `finished` signal never fires, so `await tween.finished` waits forever, `busy` stays true and `_input`
  swallows every event. A tween on the stage whose target is freed simply ends. `UIMotion.fade_in` takes the node to
  bind to for this reason.
- **Check `is_instance_valid` after every await** (`UITransitionContext.has_outgoing()` and `swap()` do it for the
  context). A freed outgoing screen is skipped; a freed incoming screen makes the push fail quietly and the screen
  underneath stays on top, as if the push never happened.
- **A screen leaves the stack when it leaves the tree** (`tree_exiting`), so `depth()` and `top()` never return a freed
  instance (that is a script error in a typed getter).
- **A source that cannot be shown** (a path that does not exist or is not a scene, a scene whose root is not a
  `Control`, any other type) logs one `UIRouter: cannot show ...` error and the router carries on. A freed object is
  rejected before any `is` test (that raises a script error on a freed instance), and a `Control` that is already on
  the stack or already has a parent is refused the same way (it is the caller's: never freed here). Every refusal also
  emits `error_reported(message)`, which is what the tests count.
- **A screen freed on top while the router is idle** reveals the one below it: shown, enabled, at rest and focused (the
  path a pop ends with), `screen_changed` emitted. If it was the last screen the stack is empty (`depth() == 0`, a
  blank stage, `screen_changed(0)`) until the next `push` or `reset`. A pop or reset that loses its screen mid-way ends
  the same way, with one `push_error` and `error_reported`. While a job runs it finishes the stack itself.

### Found by review

Review of the router (#12, fixed in #51) found two things that no unit test had asked about; both are in the sections
above, and both came from looking at the behaviour, not the code:

- **The slide pop drew the leaving screen underneath.** Playing the push backwards kept the stage's child order, so the
  popped screen slid off behind the one it revealed. The fix raises the right screen itself and does not rely on child
  order ([a pop mirrors the push](#a-pop-mirrors-the-push)); the test is `test_a_slide_pop_mirrors_the_push`.
- **A freed screen stalled the router for good** ([the rules](#a-freed-screen-must-not-stall-the-router)); the kit has
  it as a [lesson](https://github.com/Ryubara/gdstudio/blob/main/docs/lessons/2026-11-01-a-screen-freed-mid-transition-locked-the-router-for-good.md).

The general findings (a script `_draw` on a `Button` paints over its text, tweens on a node with disabled processing
never run, `hint_screen_texture` needs a back-buffer copy, set the default clear colour) are in the kit's
[UI controls page](https://github.com/Ryubara/gdstudio/blob/main/docs/godot/ui-controls.md). The router sets the clear
colour from the token `bg` (`UIRouter._ready`), so a fade never passes through the engine's grey. What to check when
adding a transition is the [checklist](https://github.com/Ryubara/deadnight/blob/main/game/addons/gds_ui/README.md#adding-a-router-transition)
next to the code.

### Tests

`game/tests/ui/test_ui_router_robustness.gd` adds a reset that loses a screen, a screen that frees itself in `_ready`
and the tree paused mid-transition. `game/tests/ui/test_ui_router.gd` (GdUnit4): queued push, pop and replace order,
pop and back at the root, back ignored
while busy, a screen freed mid-transition (every transition kind, outgoing, incoming and popped), a bad source, and the
slide pop mirroring the push. Run: `godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a
res://tests -c --ignoreHeadlessMode`. Do not add `-d`: the debugger then stops at the first script error and waits for
input forever.

### The router is shared by every suite

`UIRouter` is an autoload, so one run of all the suites has one router. A screen a suite leaves on it keeps running,
and a `create_timer` it started (the main menu's entrance, `MainMenu.ITEMS_DELAY`, 0.55 s of wall time) ends in
whichever test is running by then and calls `focus_initial()`. `test_main_scene.gd` runs just before
`test_customize_screen.gd`: on an idle machine the timer ended a few tests earlier, on a loaded one (many suites
at once) it ended in `test_the_gamepad_walks_down_the_rows_and_back_up` and took the focus from the `hair` row
(#178). Traced with a print in the menu's `screen_enter` and the test's `before_test`. A suite that shows the real
menu through the router, or the main scene, clears the router when it is done, and a suite that builds its own
screen clears it before (`RouterFixture.clear` in `game/tests/ui/router_fixture.gd`). The pair `test_main_scene.gd`
plus `test_customize_screen.gd` (about 6 s) reproduces it under load without the 5-minute full run.

### A screen takes focus only while it is the top (#190)

The cause of #178 was also a product bug: `SceneTree.create_timer` keeps running while the router disables a covered
screen (`process_mode` disabled does not stop it), so a screen pushed over the menu inside the 0.55 s entrance lost
its focus to the covered menu's `Play`. `MainMenu` now waits with a child `Timer` (it stops with the disabled screen
and is freed with it), brings its items in at once when it is covered (`screen_pause`, so they are there on return)
and focuses only if `UIRouter.top()` is the menu (`finish_entrance`). The delay is `MainMenu.items_delay` (a static
a test can set; `ITEMS_DELAY` is the design value) and `entered` says the items are up, so no test waits on wall
time. No other screen waits before focusing: a screen that must (a timer, an `await`) checks the router's top
afterwards, or uses a node timer. Capture: `game/tests/captures/menu_focus_cover.tscn`.

## Self-test (#11)

`game/tests/ui/test_gds_ui_self.gd` (GdUnit4, headless, in the CI job) covers the addon on its own: a spring settles
on its target with less than 8 percent overshoot and ends in the same place at 30, 60 and 144 fps; the theme builds
every label, button and panel style; every `UILabel.Style` has a variation; the router's depth follows push and pop;
each face slot reaches its styles, an unset slot is the engine font, the mono slot is the text face with equal digit
widths, a missing glyph falls back, and a token swap changes the face on a shown screen and on the neon sign.
`test_menu_type.gd` covers the game side: the footer plate and contrast, the sign and buttons in the game's faces, the
credits naming every committed font, a licence text and entry for each font folder, and the credits fitting one
screen.

## Button prompts (#10)

`UIGlyph` and `UIHint` (`game/addons/gds_ui/components/`) are the generic form of the HUD's `HudGlyph`, which stays as it
is: it draws the four face buttons only, in the HUD's face. What the addon version adds, and why:

- **Drawn, not an image set.** A glyph is a rounded rect, a disc, a cross, a pill or a few lines from `UITokens`, so the
  question the issue asked (a licence entry for each asset) does not arise, and a restyle reaches the prompts. The four
  PlayStation shapes (cross, circle, square, triangle) are plain geometry; the letters of the other sets are letters.
- **The set follows the pad, not just "gamepad".** `UIInputMode.family` is read from `Input.get_joy_name(device)` of the
  last pad event (`PS3` to `PS5`, `DualShock`, `DualSense`, `Sony`: PlayStation; `Nintendo`, `Switch`, `Joy-Con`,
  `Pro Controller`: Nintendo; anything else generic). The engine numbers face buttons by position (`JOY_BUTTON_A` is the
  bottom one), so the Nintendo set swaps the letters: its bottom button reads B.
- **Glyphs do not poll the device.** `UIInputMode` has a change signal (a static variable cannot declare one, so a small
  `Bus` class carries it, as `UIMotion` does), emitted from the setters of `gamepad`, `touch` and `family`. A glyph that
  is not on screen costs nothing; `HudGlyph` still polls each frame and could move to the signal.
- **A rebinding is not announced.** The `InputMap` has no change signal, so a screen that rebinds calls `refresh()`.
- **Hints hide under a finger** (`UIInputMode.touch`), as the `UIInputMode` comment always said they would.
- **Sounds:** the cues (`hover`, `focus`, `press`, `back`, `push`, `pop`, `tick`) were wired to real sounds in #87; the
  catalog and the night's sounds were not touched here.
- **Tests and capture:** `game/tests/ui/test_ui_glyph.gd` (captions per kind of binding and family, follows the device
  and the family, a rebound key, an unbound action, held sink, the change signal, pad names, the hint under a finger);
  `game/tests/captures/gds_glyphs_tour.tscn` shows the sheet and the live hint line as the device changes (keyboard,
  pad, PlayStation pad, Nintendo pad, finger).

## Left out

Settings widgets (slider, toggle, option selector) came with the settings screen: see [Settings](settings.md).

## Form controls: check box, text field, scroll area, item list (#9)

`UICheckBox`, `UILineEdit`, `UIScroll` and `UIItemList` in `game/addons/gds_ui/components/`, themed by `UIThemeBuilder`
and shown in every state on `demo/controls_sheet.tscn` (the demo menu's "Form controls").

- **Check box** is a `Button` in toggle mode. The box and the tick are drawn (`_draw`), the label is the button's own
  `text`: the theme variation `UICheckBox` gives it the body face and a left content margin of
  `space_sm + UICheckBox.box_size(tokens) + space_md`, so the engine lays the text out and the control only paints the
  box. The tick strokes itself by a spring (`_on`): a polyline cut to a share of its length, so it overshoots a little
  with the fill. Hover grabs focus like the other controls; the ring goes round the whole row.
- **Text field** is a `LineEdit`: the engine keeps typing, selection and the caret; the theme variation `UILineEdit`
  gives the fill, border, caret and selection colours from tokens, and `_draw` adds a hover tint and the focus ring.
  **The ring shows only when the field took focus from the keyboard or a gamepad** (`UIInputMode.pointer` is false when
  it gains focus). Typing a letter flips `UIInputMode.pointer` to false (a key is not a pointer), so asking
  `UIInputMode.pointer` on every frame, as the buttons do, would put a ring round a field the player clicked into and
  is typing in; the field remembers how it got focus instead.
- **Scroll area** is a `ScrollContainer` (vertical, `follow_focus` on). The bars are the theme's `VScrollBar` and
  `HScrollBar` styleboxes, so every scroll container under the stage theme gets them. A shade at the top and bottom
  edge, on a spring, says there is more; it is drawn by an internal child on top, because a container draws its own
  background before its children. `keyboard_scroll` makes it take focus and scroll on Up, Down, Page Up, Page Down,
  Home and End and the d-pad, for a page of text with nothing to focus. (`CreditsScreen` has its own version of
  this from #85; it could use `UIScroll` and does not yet.)
- **Item list** is one `Control` that draws its rows, not a `Tree` or a `VBox` of buttons: the highlight is a single
  bar that slides between rows on a spring (the text colour follows the bar), the hovered row is a second, fainter
  bar, and the list scrolls itself (`visible_rows`, the wheel, the choice kept in view, a thin bar on the right).
  Keys: Up and Down (Down from no choice picks the first row), Page Up and Page Down, Home and End, accept activates;
  a click selects, a double click activates. A list scrolls inside itself, so it needs no `ScrollContainer` round it.
- **Tests** (`game/tests/ui/test_ui_check_box.gd`, `test_ui_line_edit.gd`, `test_ui_scroll.gd`, `test_ui_item_list.gd`)
  send real key events with `Input.parse_input_event` and mouse events with `get_viewport().push_input(event, true)`
  (a headless window is 64 x 64 pixels, so a window position is scaled by the stretch before it arrives). A control
  built in a test needs `theme = UIThemeBuilder.build()`, or its theme variation does not exist.
- **Capture:** `tests/captures/gds_controls_tour.tscn` types into the field, ticks a box, walks both lists and
  scrolls the area, one PNG per beat at the window's real pixels. Mouse events there are virtual and go through the
  viewport's final (stretch) transform; nothing captures the real mouse.
