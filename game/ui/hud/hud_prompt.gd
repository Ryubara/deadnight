class_name HudPrompt
extends HudTicket
## What you can do where you stand, as a concession menu card: the object's name on top, one line
## on what it does, the price (amber when you can pay, hot when you cannot), and the button to press
## below, a keycap or a gamepad button by the last device used. A refused purchase shakes the card
## and says why on the price line.

const DETAILS := {
	&"buy_door": "OPENS THE NEXT PART OF THE LOT",
	&"buy_weapon": "A NEW GUN FOR THE NIGHT",
	&"fill_fuel": "TOPS UP THE GENERATOR",
	&"repair": "NAIL THE BOARDS BACK UP",
	&"revive": "PULL THEM BACK TO THEIR FEET",
}
const DENIED_TEXT := {
	GameRules.BuyResult.NOT_ENOUGH_POINTS: "NOT ENOUGH POINTS",
	GameRules.BuyResult.ALREADY_OWNED: "YOU ALREADY HAVE THAT",
	GameRules.BuyResult.LOCKED: "NOT YET: OPEN THE ONE BEFORE",
	GameRules.BuyResult.LIMIT_REACHED: "YOU CANNOT CARRY MORE",
	GameRules.BuyResult.TANK_FULL: "THE TANK IS FULL",
	GameRules.BuyResult.WRONG_PHASE: "NOT RIGHT NOW",
}
const DENIED_SECONDS := 1.8

@export var action := &"interact"
var denied_left := 0.0
var title_text: String:
	get:
		return _title.text
var detail_text: String:
	get:
		return _detail.text
var price_text: String:
	get:
		return _price.text
## True while the action is held, for tests and tools.
var glyph_pressed: bool:
	get:
		return _glyph.pressed
var glyph_caption: String:
	get:
		return _glyph.caption()

var _title := HudStyle.label("", HudStyle.MEDIUM, tokens.ink, true)
var _detail := HudStyle.label("", HudStyle.SMALL, tokens.ink_muted, false, HudStyle.TRACK_CAPTION)
var _price := HudStyle.label("", HudStyle.TEXT, tokens.accent_bright, false, HudStyle.TRACK_CAPTION)
var _glyph := HudGlyph.new()


func _init() -> void:
	super()
	_glyph.action = action
	for label in [_title, _detail, _price]:
		(label as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(label)
	_glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(_glyph)
	body.add_theme_constant_override(&"separation", tokens.space_sm)
	custom_minimum_size.x = 560.0
	visible = false


func _process(delta: float) -> void:
	_glyph.action = action
	if denied_left > 0.0:
		denied_left = maxf(denied_left - delta, 0.0)
		if denied_left == 0.0:
			refresh()


func refresh() -> void:
	var prompt := state.prompt
	visible = not prompt.is_empty()
	if prompt.is_empty():
		denied_left = 0.0
		return
	var kind: StringName = prompt["kind"]
	HudStyle.set_text(_title, str(prompt["label"]).to_upper())
	var detail := str(prompt.get("detail", ""))
	HudStyle.set_text(_detail, detail.to_upper() if detail != "" else DETAILS.get(kind, ""))
	if denied_left > 0.0:
		return
	var cost := int(prompt["cost"])
	var can_pay := state.can_afford(cost)
	_price.visible = cost > 0
	HudStyle.set_text(_price, "%d POINTS" % cost if can_pay else "NEED %d POINTS" % cost)
	_price.add_theme_color_override(&"font_color", tokens.accent_bright if can_pay else tokens.hot)
	accent = tokens.accent if can_pay else tokens.hot


func on_event(event: Dictionary) -> void:
	if event.get("type") != &"purchase_denied":
		return
	if int(event.get("player_id", -1)) != state.local_player_id or state.prompt.is_empty():
		return
	denied_left = DENIED_SECONDS
	_price.visible = true
	HudStyle.set_text(_price, DENIED_TEXT.get(int(event["result"]), "NOT POSSIBLE"))
	_price.add_theme_color_override(&"font_color", tokens.hot)
	UIMotion.shake(self)
