class_name HudRound
extends HudTicket
## The round number on a row of reel digits (a drum counter, not tally marks), with the zombies
## still to fall or the break countdown beneath it. With the touch layout up (`compact`) the card
## takes one row: the reels on the left, the caption and the detail stacked on the right, about
## 90 units high instead of 160, which the players' column under it takes as room (#1305).

const MIN_DIGITS := 2

## What the part says, for tests and tools.
var number_text: String:
	get:
		var text := ""
		for reel in _reels.get_children():
			text += (reel as HudReelDigit).digit
		return text
var detail_text: String:
	get:
		return _detail.text

## One row instead of three: set from the touch layout. The row and the box of words are made the
## first time it is asked for and freed when it is not, so a desktop's HUD never holds them.
var compact := false:
	set(value):
		if value != compact:
			compact = value
			_arrange()
			if state != null:
				refresh()

var _caption := HudStyle.label(
	"ROUND", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION
)
var _reels := HBoxContainer.new()
var _detail := HudStyle.label("", HudStyle.TEXT, tokens.ink_muted)
## The row of a compact card (the reels, then the words) and the words' box.
var _row: HBoxContainer
var _words: VBoxContainer


func _init() -> void:
	super()
	accent = tokens.hot
	_reels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reels.add_theme_constant_override(&"separation", HudStyle.XS)
	custom_minimum_size.x = HudStyle.COLUMN
	body.add_child(_caption)
	body.add_child(_reels)
	body.add_child(_detail)
	_detail.custom_minimum_size.y = HudStyle.TEXT + float(HudStyle.MD)
	_ensure_reels(MIN_DIGITS)


func topics() -> Array[StringName]:
	return [HudState.ROUND]


func refresh() -> void:
	var text := str(state.round_number).pad_zeros(MIN_DIGITS)
	_ensure_reels(text.length())
	for i in text.length():
		(_reels.get_child(i) as HudReelDigit).show_digit(text[i])
	var detail := ""
	match state.phase:
		HudState.PHASE_ACTIVE:
			detail = "%d LEFT" % state.zombies_left
		HudState.PHASE_BREAK:
			detail = "NEXT IN %d" % ceili(state.break_left)
		HudState.PHASE_OVER:
			detail = "THE END"
		_:
			detail = "DOORS OPEN SOON"
	if compact:
		# Beside the reels the words have what is left of the card's width; the type shrinks to the
		# floor before anything is cut.
		HudStyle.set_fitted(_detail, detail, HudStyle.TEXT, words_width())
	else:
		HudStyle.set_text(_detail, detail)


## The width the words beside the reels have on a compact card.
func words_width() -> float:
	var reels := float(_reels.get_child_count()) * HudReelDigit.TILE_COMPACT.x
	reels += float(_reels.get_child_count() - 1) * float(HudStyle.XS)
	return HudStyle.COLUMN - float(HudStyle.PAD + HudStyle.PAD_LEFT) - reels - float(HudStyle.MD)


func _ensure_reels(count: int) -> void:
	while _reels.get_child_count() < count:
		var reel := HudReelDigit.new()
		reel.colour = tokens.hot
		reel.compact = compact
		_reels.add_child(reel)
		if compact:
			update_minimum_size()


## Puts the caption, the reels and the detail in a column (the card as it was) or in a row.
func _arrange() -> void:
	for reel in _reels.get_children():
		(reel as HudReelDigit).compact = compact
	for part: Control in [_caption, _reels, _detail]:
		if part.get_parent() != null:
			part.get_parent().remove_child(part)
	if compact:
		_row = HBoxContainer.new()
		_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_theme_constant_override(&"separation", HudStyle.MD)
		_words = VBoxContainer.new()
		_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_words.alignment = BoxContainer.ALIGNMENT_CENTER
		_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_words.add_theme_constant_override(&"separation", 0)
		_words.add_child(_caption)
		_words.add_child(_detail)
		_row.add_child(_reels)
		_row.add_child(_words)
		body.add_child(_row)
		_detail.custom_minimum_size.y = 0.0
	else:
		body.remove_child(_row)
		_row.free()
		_row = null
		_words = null
		body.add_child(_caption)
		body.add_child(_reels)
		body.add_child(_detail)
		_detail.custom_minimum_size.y = HudStyle.TEXT + float(HudStyle.MD)
		# The detail goes back to its type.
		_detail.add_theme_font_size_override(&"font_size", HudStyle.TEXT)
	update_minimum_size()
