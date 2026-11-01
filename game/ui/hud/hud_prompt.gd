class_name HudPrompt
extends HudTicket
## What you can do where you stand, as a concession menu card: the button to press at its left, a
## keycap or a gamepad button by the last device used, and beside it the object's name, one line on
## what it does and the price (amber when you can pay, hot when you cannot). A refused purchase
## shakes the card and says why on the price line. The card is a fixed width and three lines high:
## each line shrinks to its room, then ends in an ellipsis, so no content makes it grow.

const DETAILS := {
	&"buy_door": "OPENS THE NEXT PART OF THE LOT",
	&"buy_weapon": "A NEW GUN FOR THE NIGHT",
	&"buy_ammo": "ROUNDS FOR YOUR RESERVE",
	&"buy_crane": "A RANDOM GUN YOU LACK",
	&"crane_take": "TAKE IT BEFORE IT FADES",
	&"crane_busy": "ONLY THE BUYER CAN TAKE IT",
	&"fill_fuel": "TOPS UP THE GENERATOR",
	&"repair": "NAIL THE BOARDS BACK UP",
	&"circuit": "SWITCH THE LIGHTS",
	&"revive": "PULL THEM BACK TO THEIR FEET",
}
const DENIED_TEXT := {
	GameRules.BuyResult.NOT_ENOUGH_POINTS: "NOT ENOUGH POINTS",
	GameRules.BuyResult.ALREADY_OWNED: "YOU ALREADY HAVE THAT",
	GameRules.BuyResult.LOCKED: "NOT YET: OPEN THE ONE BEFORE",
	GameRules.BuyResult.LIMIT_REACHED: "YOU CANNOT CARRY MORE",
	GameRules.BuyResult.TANK_FULL: "THE TANK IS FULL",
	GameRules.BuyResult.AMMO_FULL: "YOUR RESERVE IS FULL",
	GameRules.BuyResult.WRONG_PHASE: "NOT RIGHT NOW",
	GameRules.BuyResult.CRANE_BUSY: "THE CRANE IS BUSY",
}
## Why the crane would not hand the weapon over (`crane_take_denied`'s reason).
const TAKE_DENIED_TEXT := {
	&"not_buyer": "ONLY THE BUYER CAN TAKE IT",
	&"nothing_to_take": "NOTHING TO TAKE",
	&"downed": "GET UP FIRST",
	&"already_owned": "YOU ALREADY HAVE THAT",
}
const DENIED_SECONDS := 1.8
const WIDTH := HudStyle.CARD

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

var _title := HudStyle.clip(HudStyle.label("", HudStyle.MEDIUM, tokens.ink, true))
var _detail := HudStyle.clip(
	HudStyle.label("", HudStyle.SMALL, tokens.ink_muted, false, HudStyle.TRACK_CAPTION)
)
var _price := HudStyle.clip(
	HudStyle.label("", HudStyle.TEXT, tokens.accent_bright, false, HudStyle.TRACK_CAPTION)
)
var _glyph := HudGlyph.new()


func _init() -> void:
	super()
	_glyph.action = action
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in [_title, _detail, _price]:
		(label as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		words.add_child(label)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", HudStyle.MD)
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_glyph)
	row.add_child(words)
	body.add_child(row)
	custom_minimum_size.x = WIDTH
	visible = false


func _process(delta: float) -> void:
	_glyph.action = action
	if denied_left > 0.0:
		denied_left = maxf(denied_left - delta, 0.0)
		if denied_left == 0.0:
			refresh()


func topics() -> Array[StringName]:
	return [HudState.PROMPT, HudState.POINTS]


func refresh() -> void:
	var prompt := state.prompt
	visible = not prompt.is_empty()
	if prompt.is_empty():
		denied_left = 0.0
		return
	var kind: StringName = prompt["kind"]
	HudStyle.set_fitted(
		_title, str(prompt["label"]).to_upper(), HudStyle.MEDIUM, _room(), HudStyle.TEXT
	)
	var detail := str(prompt.get("detail", ""))
	HudStyle.set_fitted(
		_detail,
		detail.to_upper() if detail != "" else DETAILS.get(kind, ""),
		HudStyle.SMALL,
		_room()
	)
	if denied_left > 0.0:
		return
	var cost := int(prompt["cost"])
	var can_pay := state.can_afford(cost)
	_price.visible = cost > 0
	_say_price("%d POINTS" % cost if can_pay else "NEED %d POINTS" % cost)
	_price.add_theme_color_override(&"font_color", tokens.accent_bright if can_pay else tokens.hot)
	accent = tokens.accent if can_pay else tokens.hot


func on_event(event: Dictionary) -> void:
	var type: StringName = event.get("type", &"")
	if type != &"purchase_denied" and type != &"crane_take_denied":
		return
	if int(event.get("player_id", -1)) != state.local_player_id or state.prompt.is_empty():
		return
	denied_left = DENIED_SECONDS
	_price.visible = true
	if type == &"crane_take_denied":
		_say_price(TAKE_DENIED_TEXT.get(event["reason"], "NOT POSSIBLE"))
	else:
		_say_price(DENIED_TEXT.get(int(event["result"]), "NOT POSSIBLE"))
	_price.add_theme_color_override(&"font_color", tokens.hot)
	UIMotion.shake(self)


## The width of the lines beside the button: the card less its padding, the button and the gap.
func _room() -> float:
	return WIDTH - float(HudStyle.PAD + HudStyle.PAD_LEFT + HudStyle.MD) - HudGlyph.SIZE.x


func _say_price(text: String) -> void:
	HudStyle.set_fitted(_price, text, HudStyle.TEXT, _room())
