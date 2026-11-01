class_name HudRound
extends HudTicket
## The round number on a row of reel digits (a drum counter, not tally marks), with the zombies
## still to fall or the break countdown beneath it.

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

var _caption := HudStyle.label(
	"ROUND", HudStyle.SMALL, tokens.accent, false, HudStyle.TRACK_CAPTION
)
var _reels := HBoxContainer.new()
var _detail := HudStyle.label("", HudStyle.TEXT, tokens.ink_muted)


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
	HudStyle.set_text(_detail, detail)


func _ensure_reels(count: int) -> void:
	while _reels.get_child_count() < count:
		var reel := HudReelDigit.new()
		reel.colour = tokens.hot
		_reels.add_child(reel)
