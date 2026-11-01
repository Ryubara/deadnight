class_name HudAmmo
extends HudTicket
## Ammo: the magazine as a big numeral, the reserve beside it, the weapon's name above. An empty
## or nearly empty magazine turns hot orange and asks for a reload.

const LOW_FRACTION := 0.25

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

var _weapon := HudStyle.label(
	"", HudStyle.SMALL, tokens.ink_on_accent, false, HudStyle.TRACK_CAPTION
)
var _bar := PanelContainer.new()
var _bar_fill := StyleBoxFlat.new()
var _magazine := HudStyle.label("0", HudStyle.NUMERAL, tokens.ink, true)
var _reserve := HudStyle.label("/ 0", HudStyle.MEDIUM, tokens.ink_muted, true)
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
	custom_minimum_size.x = 330.0


func refresh() -> void:
	_magazine_size = maxi(_magazine_size, state.ammo_magazine)
	is_low = state.ammo_magazine <= maxi(1, int(_magazine_size * LOW_FRACTION))
	HudStyle.set_text(_weapon, state.weapon_name.to_upper())
	HudStyle.set_text(_magazine, str(state.ammo_magazine))
	HudStyle.set_text(_reserve, "/ %d" % state.ammo_reserve)
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
