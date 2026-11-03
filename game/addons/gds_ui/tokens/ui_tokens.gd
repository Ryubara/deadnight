class_name UITokens
extends Resource
## Design tokens: every colour, size, radius, duration and easing the UI uses.
##
## Components, shaders and the theme builder read these and nothing else, so a game restyles the
## whole UI by saving a UITokens resource and pointing the project setting `gds_ui/tokens` at it.
## The defaults are the shipped drive-in skin (a night sky, an amber marquee, a film burn and a
## projector iris); every other look is another resource. See the addon's README for the order of
## events and how to swap the tokens while the game runs (`set_active`).

## Named easings. UIMotion maps each one to a Godot transition and ease.
enum Ease { STANDARD, EMPHASIZED, ENTER, EXIT, OVERSHOOT }

const SETTING_TOKENS := "gds_ui/tokens"


## Carries the `active_changed` signal: a static variable cannot declare one itself.
class Bus:
	extends RefCounted
	signal changed(tokens: UITokens)


static var _active: UITokens
static var _bus := Bus.new()

@export_group("Colour")
@export var bg := Color("0d0b14")
@export var bg_glow := Color("1d1730")
@export var surface := Color("171320")
@export var surface_raised := Color("221c31")
@export var outline := Color("3b3350")
@export var ink := Color("f4ead2")
@export var ink_muted := Color("b6a98f")
@export var ink_disabled := Color("8a806d")
@export var ink_on_accent := Color("1a1209")
@export var accent := Color("ffb347")
@export var accent_bright := Color("ffd98a")
@export var hot := Color("ff5a36")
@export var danger := Color("e5484d")
@export var shadow := Color(0.0, 0.0, 0.0, 0.55)

@export_group("Transition colours")
## The film burn runs hot, flame, ember, char from its front inward; the iris closes to
## `iris_shade` behind a rim that cools from `iris_rim_hot` through `iris_rim`. The shaders read
## these as uniforms, so a light or cold game recolours them here and edits no shader.
@export var burn_hot := Color(1.0, 0.96, 0.78)
@export var burn_flame := Color(1.0, 0.62, 0.16)
@export var burn_ember := Color(0.78, 0.2, 0.05)
@export var burn_char := Color(0.04, 0.03, 0.03)
@export var iris_shade := Color(0.02, 0.015, 0.02)
@export var iris_rim := Color(1.0, 0.72, 0.3)
@export var iris_rim_hot := Color(1.0, 0.95, 0.8)
## The colour a screen is dimmed to while another slides over it (white leaves it undimmed).
@export var slide_dim := Color(0.45, 0.45, 0.5)

@export_group("Backdrop")
## Stars a `UIScreen` draws over its gradient; 0 draws none (a daytime or indoor game). They sit in
## the top `star_band` share of the screen and `star_seed` fixes their places, so a capture repeats.
@export var star_count := 70
@export var star_seed := 1
@export_range(0.0, 1.0) var star_band := 0.6

@export_group("Type faces")
## The display face (the sign, title and display type, big numbers), the text face (headings,
## buttons, captions, menus, small print) and the mono face (code, keys, tabular numbers). Null
## keeps the engine's fallback font (the mono slot falls back to the text face with tabular
## figures), so a game that has not picked a typeface still runs; setting these resources restyles
## everything that asks `UITokens.display_font`, `text_font` or `mono_font`.
@export var font_display: Font
@export var font_text: Font
@export var font_mono: Font

@export_group("Type scale")
@export var size_display := 104
@export var size_title := 60
@export var size_heading := 38
@export var size_body := 26
@export var size_button := 28
@export var size_caption := 20
@export var size_overline := 18
## Synthetic weight (FontVariation.variation_embolden) for display and heading text.
@export var embolden_display := 0.5
## How much of `embolden_display` a heading, a button and an option selector's text take.
@export var embolden_heading_ratio := 0.5
@export var embolden_button_ratio := 0.4
@export var embolden_option_ratio := 0.2
## Extra pixels between letters for overlines and buttons.
@export var tracking_wide := 3.0

@export_group("Spacing")
@export var space_xs := 4
@export var space_sm := 8
@export var space_md := 16
@export var space_lg := 24
@export var space_xl := 40
@export var space_xxl := 64

@export_group("Shape")
@export var radius_sm := 4
@export var radius_md := 8
@export var radius_lg := 16
@export var border := 2
@export var focus_border := 3
@export var focus_gap := 6

@export_group("Controls")
## Height of a slider, toggle or option selector, and the width a form row gives its control.
@export var control_height := 52
@export var control_width := 440
@export var track_height := 10
## Gap between a knob or thumb and the edge of its track.
@export var knob_inset := 6

@export_group("Elevation")
@export var shadow_flat := 0
@export var shadow_raised := 14
@export var shadow_hover := 26

@export_group("Tint")
## How far a raised fill lightens on hover and darkens when pressed (Color.lightened/darkened
## amounts), and the alpha of a ghost button's fill on hover and of any control that is disabled.
@export_range(0.0, 1.0) var tint_hover := 0.14
@export_range(0.0, 1.0) var tint_press := 0.18
@export_range(0.0, 1.0) var ghost_hover_alpha := 0.85
@export_range(0.0, 1.0) var disabled_alpha := 0.9

@export_group("Marquee")
## A marquee panel's chase of bulbs: spacing along the border and radius in pixels, the chase in
## laps of `chase_period` steps per second (the lit bulb moves `chase_speed * chase_period` places a
## second), and `chase_period` is also how many bulbs apart the lit ones are.
@export var bulb_spacing := 34.0
@export var bulb_radius := 4.5
@export var chase_speed := 2.2
@export var chase_period := 3

@export_group("Motion")
@export var dur_fast := 0.14
@export var dur_base := 0.24
@export var dur_slow := 0.40
## Length of one screen transition (a burn or iris uses it for each half).
@export var dur_screen := 0.5
@export var stagger := 0.05
@export var spring_stiffness := 360.0
@export var spring_damping := 24.0
@export var hover_scale := 0.035
@export var press_squash := 0.05
## What a scrolling area keeps free at its left and right so that a hovered button can grow without
## being cut off (the theme gives every ScrollContainer this margin): the growth of a button this
## wide (`hover_scale` of its width, half at each side) and the focus ring. A button wider than
## `(hover_room - ring) * 2 / hover_scale` units grows by what is left (`UIButton`).
@export var hover_room := 24
## What a scrolling area keeps free above its first row and below its last (the theme gives every
## ScrollContainer this margin): the focus ring (`focus_gap` and `focus_border`, grown with the
## button) and the growth of a row up to 80 units tall. A screen that sizes a scroll area from its
## content adds `UIScroll.margins`, and one that reads how far it scrolls reads the bar's page.
@export var scroll_room := 12
## Each half of a shader transition (burn, iris) lasts this many `dur_screen`.
@export var shader_half_scale := 1.2
## How far the screen below moves, as a share of the width, while another slides over it.
@export var slide_parallax := 0.33


## The tokens in force: the resource named by the project setting, else the defaults.
static func active() -> UITokens:
	if _active == null:
		_active = _configured()
	return _active


## The display face with a synthetic weight and extra letter spacing (pixels); the fallback font
## when the tokens name none.
func display_font(embolden := 0.0, tracking := 0.0) -> FontVariation:
	return _variation(font_display, embolden, tracking)


## The text face, same arguments.
func text_font(embolden := 0.0, tracking := 0.0) -> FontVariation:
	return _variation(font_text, embolden, tracking)


## The mono face, same arguments. Without one it is the text face with tabular figures (every digit
## the same width, so a column of numbers lines up).
func mono_font(embolden := 0.0, tracking := 0.0) -> FontVariation:
	if font_mono != null:
		return _variation(font_mono, embolden, tracking)
	var font := _variation(font_text, embolden, tracking)
	font.opentype_features = {"tnum": 1}
	return font


## Makes `tokens` the look: screens built afterwards take it, and everything that listens to
## `active_changed()` (the router and every addon component) restyles at once. Passing null returns
## to the project setting's resource. Call it before the first screen to avoid any restyle at all.
static func set_active(tokens: UITokens) -> void:
	var next := tokens if tokens != null else _configured()
	if next == _active:
		return
	_active = next
	_bus.changed.emit(next)


## Emitted with the new tokens whenever `set_active` changes them. Connect to it in `_ready` and
## re-read the tokens you cached; a freed listener is disconnected on its own.
static func active_changed() -> Signal:
	return _bus.changed


static func _configured() -> UITokens:
	var path := str(ProjectSettings.get_setting(SETTING_TOKENS, ""))
	if path != "" and ResourceLoader.exists(path):
		var loaded := load(path) as UITokens
		if loaded != null:
			return loaded
	return UITokens.new()


static func _variation(face: Font, embolden: float, tracking: float) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = face if face != null else ThemeDB.fallback_font
	if face != null:
		# A glyph the chosen face lacks comes from the engine's font, not as an empty box.
		font.fallbacks = [ThemeDB.fallback_font]
	font.variation_embolden = embolden
	font.spacing_glyph = int(tracking)
	return font
