class_name HudAmmo
extends HudTicket
## Ammo: the magazine as a big numeral, the reserve beside it, the weapon's name above. An empty
## or nearly empty magazine turns hot orange and asks for a reload. The card keeps its width: big
## numbers get a smaller type (the numeral and the reserve together), a long weapon name too, and
## then an ellipsis.

const LOW_FRACTION := 0.25
const WIDTH := 330.0
## The smallest the magazine and reserve scale to, as a fraction of their usual sizes.
const SMALLEST_SCALE := 0.5
const SCALE_STEP := 0.05
## Pixels a trimming label is given beyond its text, so its last glyph is never cut.
const LABEL_SLACK := 2.0

var is_low := false
var magazine_text: String:
	get:
		return _magazine.text
var reserve_text: String:
	get:
		return _reserve.text
var hint_text: String:
	get:
		return _hint.text

var _weapon := HudStyle.clip(
	HudStyle.label("", HudStyle.SMALL, tokens.ink_on_accent, false, HudStyle.TRACK_CAPTION)
)
var _bar := PanelContainer.new()
var _bar_fill := StyleBoxFlat.new()
var _magazine := HudStyle.clip(HudStyle.label("0", HudStyle.NUMERAL, tokens.ink, true))
var _reserve := HudStyle.clip(HudStyle.label("/ 0", HudStyle.MEDIUM, tokens.ink_muted, true))
var _hint := HudStyle.label("", HudStyle.SMALL, tokens.hot, false, HudStyle.TRACK_CAPTION)
var _magazine_size := 0


func _init() -> void:
	super()
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", tokens.space_md)
	line.alignment = BoxContainer.ALIGNMENT_END
	line.add_child(_magazine)
	line.add_child(_reserve)
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_END
	body.add_child(line)
	body.add_child(_hint)
	_bar_fill.bg_color = tokens.accent
	_bar_fill.set_content_margin_all(tokens.space_xs)
	_bar_fill.content_margin_left = tokens.space_md
	_bar.add_theme_stylebox_override(&"panel", _bar_fill)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bar.add_child(_weapon)
	body.add_child(_bar)
	custom_minimum_size.x = WIDTH


func topics() -> Array[StringName]:
	return [HudState.AMMO]


func refresh() -> void:
	_magazine_size = maxi(_magazine_size, state.ammo_magazine)
	is_low = state.ammo_magazine <= maxi(1, int(_magazine_size * LOW_FRACTION))
	HudStyle.set_fitted(_weapon, state.weapon_name.to_upper(), HudStyle.SMALL, _bar_room())
	_fit_numbers(str(state.ammo_magazine), "/ %d" % state.ammo_reserve)
	var hint := ""
	if state.ammo_magazine == 0:
		hint = "NO AMMO" if state.ammo_reserve == 0 else "RELOAD"
	elif is_low:
		hint = "LOW"
	HudStyle.set_text(_hint, hint)
	_magazine.add_theme_color_override(&"font_color", tokens.hot if is_low else tokens.ink)
	accent = tokens.hot if is_low else tokens.accent
	_bar_fill.bg_color = accent
	queue_redraw()


## The room inside the card (its padding off), and what is left of it on the weapon's bar.
func _line_room() -> float:
	return WIDTH - float(tokens.space_md * 2 + 10)


func _bar_room() -> float:
	return _line_room() - float(tokens.space_md + tokens.space_xs)


## Writes the magazine and the reserve, both scaled down together until the pair fits the card.
func _fit_numbers(magazine: String, reserve: String) -> void:
	var gap := float(tokens.space_md)
	var big := _magazine.get_theme_font(&"font")
	var small := _reserve.get_theme_font(&"font")
	var scale := 1.0
	var big_px := HudStyle.NUMERAL
	var small_px := HudStyle.MEDIUM
	while scale > SMALLEST_SCALE:
		big_px = int(HudStyle.NUMERAL * scale)
		small_px = maxi(int(HudStyle.MEDIUM * scale), HudStyle.MIN_TEXT)
		var used := (
			HudStyle.text_width(big, magazine, big_px)
			+ gap
			+ HudStyle.text_width(small, reserve, small_px)
		)
		if used <= _line_room():
			break
		scale -= SCALE_STEP
	# The labels may trim, so they take exactly the width their text needs, the reserve giving way
	# when even the smallest pair does not fit.
	var big_wide := HudStyle.text_width(big, magazine, big_px) + LABEL_SLACK
	var small_wide := minf(
		HudStyle.text_width(small, reserve, small_px) + LABEL_SLACK,
		maxf(_line_room() - gap - big_wide, 0.0)
	)
	_magazine.custom_minimum_size.x = big_wide
	_reserve.custom_minimum_size.x = small_wide
	_magazine.add_theme_font_size_override(&"font_size", big_px)
	_reserve.add_theme_font_size_override(&"font_size", small_px)
	HudStyle.set_text(_magazine, magazine)
	HudStyle.set_text(_reserve, reserve)
