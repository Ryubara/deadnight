# gds_ui

Tokens, a generated theme, drawn components, motion and a screen router. It names no game: every colour, size,
duration, shader palette and backdrop is a token, so a second game restyles it by saving a resource. The decisions
behind it, with the measurements, are in the game's `docs/research/ui-foundation.md`.

## Contents

| Folder | What |
| --- | --- |
| `tokens/` | `UITokens` (the resource), `UIThemeBuilder` (tokens to `Theme`) |
| `components/` | `UIScreen`, `UIButton`, `UILabel`, `UIPanel`, `UIRow`, `UISlider`, `UIToggle`, `UIOptionSelector`, `UICheckBox`, `UILineEdit`, `UIScroll`, `UIFitScroll`, `UIItemList` |
| `router/` | `UIRouter` (the autoload) and the transitions: fade, slide, film burn, iris |
| `shaders/` | `film_burn`, `projector_iris`, and the shared hash include |
| `motion/`, `core/` | `UIMotion` (tweens, reduced motion), `UISpring`, `UIAudio`, `UIInputMode`, `UIFocusRing` |
| `demo/` | the demo menu, the component sheet, the transition tour, the restyle tour and `light_tokens.tres` |

## Setup and order of events

1. Enable the plugin (`plugin.cfg`): it adds the `UIRouter` autoload.
2. Project settings (section `gds_ui`):

   | Setting | Default | What |
   | --- | --- | --- |
   | `gds_ui/tokens` | none | Path of a saved `UITokens` resource. Empty or missing: the defaults (the shipped drive-in skin). |
   | `gds_ui/accessibility/reduced_motion` | `false` | Read once by the router at startup into `UIMotion.reduced`. |

3. At startup the first `UITokens.active()` loads the setting's resource. The router's `_ready` then builds the stage
   theme and sets the default clear colour from the token `bg`. A skin chosen later (from a saved profile) calls
   `UITokens.set_active(tokens)`: before the first screen is built there is nothing to restyle, afterwards the
   addon follows live (see below).
4. Screens extend `UIScreen` and are shown with the router (below).

## Tokens

`UITokens` is a `Resource`; open it in the inspector, every export has a doc comment. Groups:

| Group | Tokens | Read by |
| --- | --- | --- |
| Colour | `bg`, `bg_glow`, `surface`, `surface_raised`, `outline`, `ink`, `ink_muted`, `ink_disabled`, `ink_on_accent`, `accent`, `accent_bright`, `hot`, `danger`, `shadow` | theme, every component, the `UIScreen` backdrop |
| Transition colours | `burn_hot`, `burn_flame`, `burn_ember`, `burn_char`, `iris_shade`, `iris_rim`, `iris_rim_hot`, `slide_dim` | the film burn and iris shaders (as uniforms), the slide |
| Backdrop | `star_count` (0 = none), `star_seed`, `star_band` | `UIScreen` |
| Type faces and scale | `font_display`, `font_text`, `font_mono`, `size_*`, `embolden_display`, `embolden_heading_ratio`, `embolden_button_ratio`, `embolden_option_ratio`, `tracking_wide` | `UIThemeBuilder`, `display_font()`, `text_font()`, `mono_font()` |
| Spacing, shape, controls | `space_*`, `radius_*`, `border`, `focus_border`, `focus_gap`, `control_height`, `control_width`, `track_height`, `knob_inset` | components, rows |
| Elevation | `shadow_flat`, `shadow_raised`, `shadow_hover` | buttons, panels |
| Tint | `tint_hover`, `tint_press`, `ghost_hover_alpha`, `disabled_alpha` | buttons, toggle, option selector, the theme's plain `Button` |
| Marquee | `bulb_spacing`, `bulb_radius`, `chase_speed`, `chase_period` | `UIPanel` (marquee variant) |
| Motion | `dur_fast`, `dur_base`, `dur_slow`, `dur_screen`, `stagger`, `spring_stiffness`, `spring_damping`, `hover_scale`, `press_squash`, `shader_half_scale`, `slide_parallax` | `UIMotion`, springs, transitions |

Nothing in the addon reads a colour, factor or count that is not a token; what stays a named constant is the shape
of a drawing (the chevron's size, the focus ring's landing distance).

## Restyling

1. Save a `UITokens` resource (New Resource, `UITokens`), change what differs, point `gds_ui/tokens` at it. Anything
   left alone keeps the default. `demo/light_tokens.tres` is a worked second palette: paper and blue, no stars, a blue
   burn and iris.
2. Look at it: `demo/demo.tscn` (the menu), `demo/states_sheet.tscn` (every component state) and
   `demo/transition_tour.tscn`. `demo/restyle_tour.tscn` run with `-- --tokens=res://your.tres` walks the menu, one
   burn and the sheet with that resource, for captures (add `--live` to swap the tokens while the menu shows).
3. Shader transitions take their colours from the tokens: `UITransitionShader.feed_tokens(material, tokens)` sets every
   shader uniform that is named like a colour token. A game's own shader gets the same palette by declaring
   `uniform vec3 burn_flame;` (or any other colour token name).
4. Do not edit a shader or a component for a colour, a factor or a count: add a token (an `@export` with a doc
   comment on `UITokens`, read where the literal was).
5. A light palette needs a `surface_raised` darker than `surface`: hover lightens a raised fill (`tint_hover`).
6. Fonts: three slots. `font_display` is for display and title labels (and a game's sign or big numbers),
   `font_text` for headings, buttons, captions and body, `font_mono` for `UILabelMono` (unset: the text face with
   tabular figures). An unset slot is the engine's fallback font, which is also the fallback for a glyph a chosen face
   lacks. Use an inline or decorative display face only at large sizes. In code ask `tokens.display_font(embolden,
   tracking)` (and `text_font`, `mono_font`); a node that caches one connects to `active_changed()`.

### Changing the tokens while the game runs

`UITokens.set_active(tokens)` is the one call. It stores the tokens and emits `UITokens.active_changed()`; then:

- the router rebuilds the stage theme (every label, button and panel variation under it follows) and sets the clear
  colour; a transition already playing finishes with the tokens it started with;
- every addon component re-reads what it cached (spring tuning, radii, minimum sizes, the star field) and redraws:
  the screens, buttons, panels, rows, sliders, toggles and option selectors already on the stage;
- screens built afterwards take the new tokens as they are built.

`set_active(null)` returns to the project setting's resource; setting the tokens that are already active does
nothing. What does **not** follow on its own is code outside the addon that caches `UITokens.active()` in a variable
(a game's HUD, a skin node): connect to `UITokens.active_changed()` in `_ready` and re-read, as the components do (a
freed listener is disconnected automatically), or the node keeps its look until it is built again. A game that never
changes tokens after startup needs none of this.

## Reduced motion

`UIMotion.reduced = true` (or `false`) is the one call, at any time: a settings screen assigns it. It emits
`UIMotion.changed()` with the new value (only when the value changes); the router swaps slide, burn and iris for the
fade from the next transition on, springs of sliders, toggles and selectors snap, and a marquee panel's chase stops
or starts. A skin follows the same way: connect to `UIMotion.changed()` in `_ready` instead of reading the flag once.
The setting `gds_ui/accessibility/reduced_motion` only gives the starting value (`UIMotion.load_settings()`, run by
the router); saving the player's choice is the game's job.

## Audio cues

The addon ships no sounds. Set `UIAudio.handler` to a `Callable` taking one `StringName` and play what you like (an
unset handler is a silent no-op):

| Cue | When |
| --- | --- |
| `hover` | the pointer enters a button, toggle, slider or option selector |
| `focus` | a control takes focus (keyboard, gamepad or hover) |
| `press` | a button is pressed, a toggle flips, an option selector steps |
| `tick` | a slider's value changes |
| `push`, `pop` | the router starts showing a new screen, or going back |
| `back` | Esc or gamepad B pops the top screen |

## Button prompts

`UIGlyph` draws the button to press for an action: a keycap or mouse button for the keyboard and mouse, or the gamepad
button (a lettered disc, the four PlayStation shapes, a shoulder or trigger, a d-pad cross, a stick, start or back),
chosen by the last device used (`UIInputMode`). It reads the action's binding from the `InputMap`, so a rebound key shows
the new key (call `refresh()` after changing the map), and it sinks while the action is held. `UIHint` is a glyph with
its words ("Select", "Back"); a row of them is the key-hint line at the foot of a screen, and they hide under a finger.

```gdscript
var hint := UIHint.new()
hint.action = &"ui_accept"
hint.text = "Select"
footer.add_child(hint)
```

`UIInputMode.changed()` is emitted when `gamepad`, `touch` or `family` changes: glyphs follow it, so none polls.
`UIInputMode.family` (`GENERIC`, `PLAYSTATION`, `NINTENDO`) comes from the name the OS gives the pad
(`UIInputMode.family_for(name)`). Nothing is an image: every shape is drawn from tokens, so there is no asset to license
and a restyle reaches it. See `demo/glyph_sheet.tscn`.

## Router calls

`UIRouter` is an autoload; every call takes a `PackedScene`, a scene path or a `Control` instance (usually a
`UIScreen`) and a `UITransition.Kind` (`CUT`, `FADE`, `SLIDE`, `BURN`, `IRIS`). Calls made while a transition runs are
queued and run in order, and input is blocked meanwhile.

| Call | What |
| --- | --- |
| `push(source, kind = FADE, params = {})` | show a screen over the current one, which stays alive underneath |
| `replace(source, kind = FADE, params = {})` | show a screen in place of the current one, which is freed |
| `pop(kind = -1)` | go back and free the top screen; `-1` plays the transition it arrived with, mirrored |
| `reset(source, kind = CUT, params = {})` | free the whole stack and show one screen |
| `depth()`, `top()`, `screens()` | the stack, root to top |
| signals `idle`, `screen_changed(depth)`, `error_reported(message)` | the queue drained; the stack changed; a source could not be shown |

`params` arrive as `UIScreen.params`. A `UIScreen` has the hooks `screen_enter`, `screen_pause` and `screen_resume`,
an `initial_focus` path, `allow_back` (whether Esc pops it) and `stars` (the token star backdrop, per screen);
`glow` overrides the bottom of the backdrop gradient. Esc and gamepad B (`ui_cancel`) pop while more than one screen
is on the stack.

With nothing focused, the router spends the first arrow or accept key giving the top screen its focus (and marks it
handled). A screen that is a live game overrides `wants_focus_key()` to return false while it has nothing to focus, so
that its keys reach the game: a gamepad's Start is `ui_accept` and also the game's `pause`.

## Adding a router transition

A transition is a `UITransition` whose `play(ctx)` is awaited by the router. Before it merges, check each item and
attach the captures to the pull request.

1. **Push and pop, both captured.** `demo/transition_tour.tscn` walks every kind with the keyboard (Enter pushes, Esc
   pops); capture it with Movie Maker at 10 fps and look at the frames of the pop, not only the push. A pop must
   mirror the push, with the leaving screen on top where the push had the entering one on top.
2. **Layering is explicit.** Call `ctx.raise(screen)` for the screen that must be on top; never rely on the stage's
   child order.
3. **Tweens belong to the stage.** Create them on `ctx.stage`, or with `UIMotion.fade_in(control, delay, owner)` and the
   stage as `owner`; never on a screen. A tween on a freed screen never emits `finished`, and the router waits forever.
4. **Check `is_instance_valid` after every await**, through `ctx.has_outgoing()` and `ctx.swap()`. Add the case to
   `tests/ui/test_ui_router.gd` next to the existing ones: the outgoing, the incoming and the popped screen freed
   mid-transition must each leave `busy` false and the stack right.
5. **The queue drains.** Push, pop and replace queued during the transition run in order (`test_queued_calls_*`).
6. **Reduced motion snaps.** With `UIMotion.reduced` nothing moves: the router swaps the slide, burn and iris for the
   fade (`UIRouter._make`).
7. **Compatibility renderer.** A shader transition does not sample the screen (`hint_screen_texture` needs a back-buffer
   copy); the colour behind the fade is the token `bg`, set as the default clear colour by the router.
8. **A paused screen still animates.** The router restores a screen's `process_mode` before the transition; do not
   create tweens on a node whose mode is disabled.

## Animating the children of a container

`UIMotion.stagger_in` tweens `position`, which a container owns. It waits until the container has sorted (two
`process_frame`s: the sort is a deferred call that runs after the signal, and an input event is handled before it in
the same frame), stops an earlier rise of the same control, and asks the container to sort again when the rise ends.
Do the same for any tween of a container child's position: never read `position` in the frame the child was shown.
