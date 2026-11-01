# UI foundation

Decisions behind the `gds_ui` addon (`game/addons/gds_ui/`), written while building it. The addon names no Deadnight
content, so it can move to the GDStudio kit unchanged.

## Tokens and theme

`UITokens` (a `Resource`) holds every colour, type size, spacing, radius, duration and spring value. Nothing else reads
a literal. `UIThemeBuilder.build(tokens)` generates the `Theme`: label type variations (`UILabelDisplay` ... `Overline`),
button variations (`UIButtonPrimary/Secondary/Ghost`) and panel variations, plus a usable look for plain `Button`,
`Label` and `PanelContainer`. A game restyles everything by saving a `UITokens` resource and pointing the project
setting `gds_ui/tokens` at it. Only the engine's fallback font is used: a licensed font is a maintainer decision.

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
| Slide | 0.5 s, expo out, old screen at 1/3 distance and dimmed | Parallax shows depth; pop reverses |
| Shader transitions | 1.2 x 0.5 s per half | One sweep to cover, one to reveal |

No easing is linear. Reduced motion (`UIMotion.reduced`, project setting `gds_ui/accessibility/reduced_motion`) makes
movement snap and swaps slide, burn and iris for the fade.

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

## Router

`UIRouter` is an autoload (the plugin adds and removes it) on a `CanvasLayer`. Calls are queued while a transition runs
and input is blocked. A pop repeats the transition the screen arrived with, reversed. Tweens must not be created on a
screen whose `process_mode` is disabled (paused screens are), or they never run: the router restores the mode before
each transition.

## Left out

Settings widgets (slider, toggle, option selector) came with the settings screen: see [Settings](settings.md).
