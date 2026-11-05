class_name PlateTile
extends UIButton
## One calling card, emblem or frame on the equip screen (`CardsScreen`): its art, its title, and
## under it what it is to the player: the one they wear, one they may put on, or one still to earn
## with how to earn it. A piece not yet earned is dimmed and still shows what it looks like, so a
## player sees what they are playing for.

const WEARING := "WEARING"
const NONE_TITLES := {
	PlateCatalog.CARD: "No card", PlateCatalog.EMBLEM: "No emblem", PlateCatalog.FRAME: "No frame"
}
## The room under the art for the caption, in lines (the title's one and up to three for how to
## earn it or a riddle: an emblem's tile is narrow), and a line's height.
const CAPTION_LINES := 4
const CAPTION_LINE := 24.0
## An emblem's tile is wide enough for a title like "Open for Business".
const EMBLEM_TILE_WIDTH := 132.0

var kind: StringName = PlateCatalog.CARD
var piece_id: StringName = &""
var owned := false
var worn := false

var _art: Control
var _title: Label
var _status: Label


## A tile for the piece `id` of `kind` (`&""` is the choice of wearing none), `art_size` for the
## art. `status` says what the piece is to the player: how to earn it, or empty.
static func make(
	p_kind: StringName,
	id: StringName,
	art_size: Vector2,
	is_owned: bool,
	is_worn: bool,
	how_to_get: String
) -> PlateTile:
	var tile := PlateTile.new()
	tile.kind = p_kind
	tile.piece_id = id
	tile.owned = is_owned
	tile.worn = is_worn
	tile.variant = UIButton.Variant.GHOST
	tile.toggle_mode = false
	tile._build(art_size, how_to_get)
	return tile


func _build(art_size: Vector2, how_to_get: String) -> void:
	var catalog := PlateCatalog.shipped()
	var pad := 8.0
	var column_gap := 4
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 4)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = pad
	column.offset_top = pad
	column.offset_right = -pad
	column.offset_bottom = -pad
	add_child(column)
	if piece_id == &"" and kind != PlateCatalog.FRAME:
		_art = Control.new()
		_art.custom_minimum_size = art_size
	elif kind == PlateCatalog.FRAME:
		var frame := FrameArt.new()
		frame.frame_id = piece_id
		frame.ground = UITokens.active().bg
		frame.dim = 0.0 if owned else 0.55
		_art = frame
	elif kind == PlateCatalog.CARD:
		var card := CardArt.new()
		card.card_id = piece_id
		card.titled = true
		card.dim = 0.0 if owned else 0.55
		card.silhouette = catalog.is_hidden(kind, piece_id) and not owned
		_art = card
	else:
		var emblem := EmblemArt.new()
		emblem.emblem_id = piece_id
		emblem.dim = 0.0 if owned else 0.55
		emblem.silhouette = catalog.is_hidden(kind, piece_id) and not owned
		_art = emblem
	_art.custom_minimum_size = art_size
	_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_art)
	_title = _caption(
		NONE_TITLES[kind] if piece_id == &"" else catalog.shown_title(kind, piece_id, owned)
	)
	_title.add_theme_color_override(&"font_color", UITokens.active().ink)
	column.add_child(_title)
	_status = _caption(_status_text(how_to_get))
	_status.add_theme_color_override(
		&"font_color", UITokens.active().accent_bright if worn else UITokens.active().ink_muted
	)
	column.add_child(_status)
	# The captions under the art: the title and what it takes, which may wrap onto three lines.
	custom_minimum_size = Vector2(
		maxf(art_size.x, EMBLEM_TILE_WIDTH) + 2.0 * pad,
		art_size.y + 2.0 * pad + float(CAPTION_LINES) * CAPTION_LINE + float(column_gap)
	)


func _status_text(how_to_get: String) -> String:
	if worn:
		return WEARING
	if owned or piece_id == &"":
		return ""
	return how_to_get


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", MenuLook.SIZE_CAPTION)
	return label


## The caption lines for tests: the piece's title and what it is to the player.
func title_text() -> String:
	return _title.text


func status_text() -> String:
	return _status.text


func art() -> Control:
	return _art
