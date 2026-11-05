class_name HudBotOrder
extends HudPart
## The standing order of the team's bots, as a tag beside the weapon places in the players' corner
## on a phone (#1286, `HudSlots`): the word of the order (FOLLOW, ROAM or HOLD) in the order's
## colour on a ticket, under a small BOTS. It is there only while the touch controls are up and the
## room has a bot, and it is the phone's bot control: the touch layer reads its box (`touch_zones`)
## and a tap presses `bot_order_next`, which `BotWheelDriver` turns into the next order of the
## round. The wheel (hold and drag) stays for the keyboard and the pad, where this tag is never
## made.
##
## The tag is a fingertip high and wide at least (`fit_touch`, `MenuScale.tap_units`) and its words
## are read at the HUD's least text for a phone (14 CSS px, `MenuScale.text_units`). One canvas
## item: it draws its own words, so a room without bots holds a single hidden node.

## The action a tap on the tag presses.
const ACTION := &"bot_order_next"
const CAPTION := "BOTS"
## The widest word, which sets the tag's width so it does not change size when the order does.
const WIDEST := "FOLLOW"

## Whether a finger holds the screen: the tag is shown (when there are bots) and takes touches.
var touch := false
## The order drawn now.
var order: StringName = BotWheel.DEFAULT_ORDER

var _finger := 0.0
var _text_px := HudStyle.MIN_TEXT
var _pressed := false


func _init() -> void:
	super()
	name = "BotOrder"
	visible = false
	set_process(false)


func topics() -> Array[StringName]:
	return [HudState.TEAM, HudState.BOT_ORDER]


func refresh() -> void:
	order = state.bot_order if state != null else BotWheel.DEFAULT_ORDER
	visible = touch and state != null and state.has_bots()
	queue_redraw()


## Puts the tag under a finger (or takes it away): at least `finger` canvas units high and wide, its
## words typed at `text_px`.
func fit_touch(on: bool, finger: float, text_px := HudStyle.MIN_TEXT) -> void:
	var changed := on != touch or not is_equal_approx(finger, _finger) or text_px != _text_px
	touch = on
	_finger = finger if on else 0.0
	_text_px = text_px
	set_process(on)
	if changed:
		custom_minimum_size = tag_size()
		queue_redraw()
	refresh()


## The tag's size: a fingertip high, as wide as `FOLLOW` and the card's padding, never narrower than
## a fingertip. Zero without a finger.
func tag_size() -> Vector2:
	if not touch:
		return Vector2.ZERO
	var words := HudStyle.text_width(_font(), WIDEST, _text_px)
	var wide := maxf(_finger, ceilf(words + float(HudStyle.PAD_LEFT + HudStyle.PAD)))
	return Vector2(wide, ceilf(_finger))


## What a finger can press: the tag's action and its box in the screen's canvas units. None while
## the tag is not under a finger or not shown (no bots, a pause).
func touch_zones() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if touch and is_visible_in_tree():
		found.append({&"action": ACTION, &"rect": get_global_rect()})
	return found


## The word the tag says for `of_order`, and the colour it is said in: three that differ in light
## as well as in hue (cream, amber, red-orange), and in the word.
func word() -> String:
	return String(BotWheel.NAMES.get(order, ""))


func colour_of(of_order: StringName) -> Color:
	match of_order:
		BotWheel.FOLLOW:
			return tokens.accent
		BotWheel.HOLD:
			return tokens.hot
	return tokens.ink


func _process(_delta: float) -> void:
	# Lit while a finger is on it: the one answer a tap gets before the bots' state changes.
	var down := Input.is_action_pressed(ACTION)
	if down != _pressed:
		_pressed = down
		queue_redraw()


func _font() -> Font:
	return tokens.display_font(tokens.embolden_display * 0.3)


func _draw() -> void:
	var accent := colour_of(order)
	HudStyle.draw_ticket(self, Rect2(Vector2.ZERO, size), accent, 1.0 if _pressed else 0.0)
	var font := _font()
	var caption_px := _text_px
	var lines := font.get_height(caption_px) + font.get_height(_text_px)
	var left := float(HudStyle.PAD_LEFT)
	var top := (size.y - lines) * 0.5
	draw_string(
		font,
		Vector2(left, top + font.get_ascent(caption_px)),
		CAPTION,
		HORIZONTAL_ALIGNMENT_LEFT,
		size.x - left,
		caption_px,
		tokens.ink_muted
	)
	draw_string(
		font,
		Vector2(left, top + font.get_height(caption_px) + font.get_ascent(_text_px)),
		word(),
		HORIZONTAL_ALIGNMENT_LEFT,
		size.x - left,
		_text_px,
		accent
	)
