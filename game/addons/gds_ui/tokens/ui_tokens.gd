class_name UITokens
extends Resource
## Design tokens: every colour, size, radius, duration and easing the UI uses.
##
## Components and the theme builder read these and nothing else, so a game restyles the whole UI by
## saving a UITokens resource and pointing the project setting `gds_ui/tokens` at it.

## Named easings. UIMotion maps each one to a Godot transition and ease.
enum Ease { STANDARD, EMPHASIZED, ENTER, EXIT, OVERSHOOT }

const SETTING_TOKENS := "gds_ui/tokens"

static var _active: UITokens

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


## The tokens in force: the resource named by the project setting, else the defaults.
static func active() -> UITokens:
	if _active == null:
		_active = _configured()
	return _active


static func set_active(tokens: UITokens) -> void:
	_active = tokens


static func _configured() -> UITokens:
	var path := str(ProjectSettings.get_setting(SETTING_TOKENS, ""))
	if path != "" and ResourceLoader.exists(path):
		var loaded := load(path) as UITokens
		if loaded != null:
			return loaded
	return UITokens.new()
