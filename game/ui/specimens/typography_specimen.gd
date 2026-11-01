class_name TypographySpecimen
extends Control
## A mock main menu in one typeface pairing, for choosing the game's type (issue #24).
##
## Run with user arguments: `-- --pairing=<id or index> --fonts=<folder holding the font families>`.
## The mock holds what the real screens need to prove: a title, five menu items with one focused,
## a settings row, a HUD number and a ticket. Layout is fixed for 1920 x 1080 so every pairing
## is judged on the same ground.

const MENU_ITEMS: Array[String] = [
	"Start the Night", "Join Friends", "Settings", "Credits", "Leave the Lot"
]
const FOCUSED := 0
const MARGIN_X := 150.0
const MENU_TOP := 490.0
const MENU_STEP := 76.0
const RIGHT_EDGE := 1830.0
const GLOW_LAYERS: Array[Vector2] = [Vector2(30, 0.1), Vector2(16, 0.22), Vector2(7, 0.45)]

var _tokens := UITokens.active()
var _pairing: Dictionary
var _display: FontVariation
var _text: FontVariation


func _ready() -> void:
	var args := _parse_args()
	_pairing = _find_pairing(args.get("pairing", "0"))
	_display = TypographyPairings.load_face(_pairing["display"], args.get("fonts", ""))
	_text = TypographyPairings.load_face(_pairing["text"], args.get("fonts", ""))
	_build()


func _build() -> void:
	var backdrop := SpecimenBackdrop.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_build_title()
	_build_menu()
	_build_settings()
	_build_hud()
	_build_ticket()
	_label(
		"%s   |   %s + %s" % [_pairing["name"], _face_name("display"), _face_name("text")],
		null,
		22,
		_tokens.ink_muted,
		Vector2(40, 1030)
	)


func _build_title() -> void:
	var title: String = _pairing["title"]
	var size_px: int = _pairing["display"]["size"]
	_label(
		"A 1958 DRIVE-IN, AFTER DARK",
		_text,
		26,
		_tokens.ink_muted,
		Vector2(MARGIN_X + 6.0, 150.0),
		6
	)
	var pos := Vector2(MARGIN_X, 190.0)
	var colour := _tokens.accent_bright if _pairing["neon"] else _tokens.ink
	if _pairing["neon"]:
		for layer in GLOW_LAYERS:
			var glow := _label(title, _display, size_px, Color(0, 0, 0, 0), pos)
			glow.add_theme_constant_override("outline_size", int(layer.x))
			glow.add_theme_color_override("font_outline_color", Color(_tokens.hot, layer.y))
		colour = Color("ffe6c9")
	else:
		var shadow := _label(title, _display, size_px, Color(_tokens.hot, 0.9), pos + Vector2(6, 6))
		shadow.name = "TitleShadow"
	_label(title, _display, size_px, colour, pos).name = "Title"


func _build_menu() -> void:
	for i in MENU_ITEMS.size():
		var text := MENU_ITEMS[i].to_upper() if _pairing["upper_menu"] else MENU_ITEMS[i]
		var focused := i == FOCUSED
		var colour := _tokens.accent_bright if focused else _tokens.ink
		var pos := Vector2(MARGIN_X + 56.0, MENU_TOP + i * MENU_STEP)
		var item := _label(text, _text, _pairing["text"]["size"], colour, pos)
		if focused:
			_add_marker(Vector2(MARGIN_X + 8.0, pos.y + 4.0), item.get_minimum_size().y)


func _add_marker(at: Vector2, height: float) -> void:
	var marker := Polygon2D.new()
	var h := height * 0.62
	marker.polygon = PackedVector2Array([Vector2(0, 0), Vector2(h * 0.9, h * 0.5), Vector2(0, h)])
	marker.position = at + Vector2(0, (height - h) * 0.5)
	marker.color = _tokens.hot
	add_child(marker)


func _build_settings() -> void:
	var x := 1140.0
	var y := 470.0
	_label("SETTINGS", _text, 24, _tokens.ink_muted, Vector2(x, y - 50.0), 6)
	var rule := ColorRect.new()
	rule.color = _tokens.outline
	rule.position = Vector2(x, y - 12.0)
	rule.size = Vector2(620, 2)
	add_child(rule)
	var row := y + 12.0
	var name_label := _label("Music volume", _text, 36, _tokens.ink, Vector2(x, row))
	var track_start := maxf(x + 290.0, x + name_label.get_minimum_size().x + 36.0)
	var track_width := x + 540.0 - track_start
	var track := ColorRect.new()
	track.color = _tokens.outline
	track.position = Vector2(track_start, row + 28.0)
	track.size = Vector2(track_width, 8)
	add_child(track)
	var fill := ColorRect.new()
	fill.color = _tokens.accent
	fill.position = track.position
	fill.size = Vector2(track_width * 0.7, 8)
	add_child(fill)
	var knob := ColorRect.new()
	knob.color = _tokens.accent_bright
	knob.size = Vector2(14, 30)
	knob.position = Vector2(fill.position.x + fill.size.x - 7.0, row + 17.0)
	add_child(knob)
	_label("70", _text, 36, _tokens.accent_bright, Vector2(x + 560.0, row))
	_label("Subtitles", _text, 36, _tokens.ink, Vector2(x, row + 72.0))
	_label("ON", _text, 36, _tokens.accent_bright, Vector2(x + 560.0, row + 72.0))


func _build_hud() -> void:
	var x := 1360.0
	var face := _numerals()
	var number_size: int = _pairing.get("hud_size", 150)
	_label("ROUND", _text, 26, _tokens.ink_muted, Vector2(x, 60.0), 6)
	_label("7", face, number_size, _tokens.hot, Vector2(x - 6.0, 78.0 + (150 - number_size) * 0.3))
	var points := _label(
		"1,250", face, int(number_size * 0.56), _tokens.accent_bright, Vector2(0.0, 104.0)
	)
	points.position.x = RIGHT_EDGE - points.get_minimum_size().x
	var caption := _label("POINTS", _text, 26, _tokens.ink_muted, Vector2(0.0, 60.0), 6)
	caption.position.x = RIGHT_EDGE - caption.get_minimum_size().x


func _build_ticket() -> void:
	var ticket := SpecimenTicket.new()
	ticket.position = Vector2(1140.0, 780.0)
	ticket.size = Vector2(640, 150)
	add_child(ticket)
	var ink := SpecimenTicket.INK
	var stub_right := ticket.position.x + ticket.size.x - 26.0
	_label("ADMIT ONE", _numerals(), 54, ink, ticket.position + Vector2(28, 14))
	_label("THE LOT  |  1958", _text, 24, ink, ticket.position + Vector2(30, 92), 3)
	_right_label("No. 0458", _text, 22, ink, stub_right, ticket.position.y + 24.0)
	_right_label("NIGHT 7", _text, 22, ink, stub_right, ticket.position.y + 74.0, 3)


## A label whose right edge sits at `right`.
func _right_label(
	text: String,
	font: Font,
	font_size: int,
	colour: Color,
	right: float,
	y: float,
	extra_track := 0
) -> Label:
	var label := _label(text, font, font_size, colour, Vector2(0.0, y), extra_track)
	label.position.x = right - label.get_minimum_size().x
	return label


## A Label at `pos` in `font` (null: the engine default), made once and added to the specimen.
func _label(
	text: String, font: Font, font_size: int, colour: Color, pos: Vector2, extra_track := 0
) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	if font != null:
		label.add_theme_font_override("font", _with_track(font, extra_track))
	add_child(label)
	return label


func _with_track(font: Font, extra: int) -> Font:
	if extra == 0 or not font is FontVariation:
		return font
	var copy := (font as FontVariation).duplicate() as FontVariation
	copy.spacing_glyph += extra
	return copy


## The face for big numbers and ticket headings: the display face unless the pairing says "text".
func _numerals() -> FontVariation:
	return _text if _pairing.get("hud", "display") == "text" else _display


func _face_name(which: String) -> String:
	return str(_pairing[which]["file"]).get_file().get_basename()


func _find_pairing(key: String) -> Dictionary:
	if key.is_valid_int():
		return TypographyPairings.ALL[clampi(int(key), 0, TypographyPairings.ALL.size() - 1)]
	for p in TypographyPairings.ALL:
		if p["id"] == key:
			return p
	return TypographyPairings.ALL[0]


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var parts := arg.substr(2).split("=", true, 1)
			out[parts[0]] = parts[1]
	return out
