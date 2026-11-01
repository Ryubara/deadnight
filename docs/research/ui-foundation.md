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
setting `gds_ui/tokens` at it. Only the engine's fallback font is used: a licensed font is a maintainer decision.

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

## Left out

Settings widgets (slider, toggle, option selector) came with the settings screen: see [Settings](settings.md).
