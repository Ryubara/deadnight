class_name HudGains
extends HudPart
## Your point gains as a short list beside the crosshair: "+100 HEADSHOT KILL". Rows stack (never
## overlap), the oldest fades first, and a run of small hit payments merges into one row so a
## 28-zombie round cannot flood the screen. The list is `WIDTH` wide: a row's type shrinks to fit
## it, so the list never reaches the ammo card or the lists on the right.

const MAX_ROWS := 3
## The room until the `Hud` says how much the canvas leaves (see `set_room`).
const WIDTH := 225.0
const LIFE := 2.4
const FADE := 0.5
## Hits within this many seconds of the last row of the same kind add to it.
const MERGE_WINDOW := 0.7
## What each rules reason is called on screen. Reasons not listed are shown as their own name.
const REASON_TEXT := {
	&"kill": "KILL",
	&"headshot_kill": "HEADSHOT KILL",
	&"melee_kill": "MELEE KILL",
	&"hit": "HITS",
	&"headshot_hit": "HEADSHOT HITS",
	&"repair": "REPAIR",
	&"round_bonus": "ROUND BONUS",
	&"special_reward": "SPECIAL ROUND REWARD",
	&"purchase": "BOUGHT",
	&"down_penalty": "DOWN PENALTY",
}
const MERGES := [&"hit", &"headshot_hit", &"repair"]

## Rows alive, oldest first: {"reason", "amount", "age", "label", "size"}.
var rows: Array[Dictionary] = []
## How wide the list may be: a row's type shrinks to fit.
var room := WIDTH

var _stack := HudRowStack.new()
## Labels that left the list, kept for the next gains (a kill makes one every time): the plain
## ones and the big ones, which are in another font.
var _spare: Array[Array] = [[], []]
## Where the spare labels wait, hidden: in the tree, so they are freed with the part and are never
## orphans.
var _shelf := Control.new()


func _init() -> void:
	super()
	_stack.gap = HudStyle.XS
	_stack.custom_minimum_size.x = room
	add_child(_stack)
	_shelf.visible = false
	add_child(_shelf)
	_stack.minimum_size_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	return _stack.get_combined_minimum_size()


func _process(delta: float) -> void:
	advance(delta)


## Gives the list `width` to lay out in (the canvas leaves more room on a wide screen) and fits
## the rows again.
func set_room(width: float) -> void:
	if is_equal_approx(width, room):
		return
	room = width
	_stack.custom_minimum_size.x = room
	for row in rows:
		_write(row)


## The texts shown, oldest first, for tests.
func texts() -> Array[String]:
	var list: Array[String] = []
	for row in rows:
		list.append((row["label"] as Label).text)
	return list


func on_event(event: Dictionary) -> void:
	if event.get("type") != &"points_changed":
		return
	if int(event["player_id"]) != state.local_player_id or int(event["delta"]) == 0:
		return
	var began := PerfProbe.begin()
	add_gain(StringName(event.get("reason", &"")), int(event["delta"]))
	PerfProbe.end(&"hud.gain", began)


func add_gain(reason: StringName, amount: int) -> void:
	if reason == &"start" or reason == &"grant":
		return
	var last: Dictionary = rows.back() if not rows.is_empty() else {}
	if MERGES.has(reason) and last.get("reason") == reason and float(last["age"]) < MERGE_WINDOW:
		last["amount"] = int(last["amount"]) + amount
		last["age"] = 0.0
		_write(last)
		return
	var gain := {"reason": reason, "amount": amount, "age": 0.0}
	var big := amount >= 60
	gain["size"] = HudStyle.MEDIUM if big else HudStyle.TEXT
	gain["label"] = _label(gain["size"], _colour(reason, amount), big)
	rows.append(gain)
	_stack.add_row(gain["label"])
	_write(gain)
	while rows.size() > MAX_ROWS:
		_drop(rows[0])


## Ages the rows by `delta` seconds and fades or removes them.
func advance(delta: float) -> void:
	for row in rows.duplicate():
		row["age"] = float(row["age"]) + delta
		var left := LIFE - float(row["age"])
		(row["label"] as Label).modulate.a = clampf(left / FADE, 0.0, 1.0)
		if left <= 0.0:
			_drop(row)
	_stack.advance(delta)


func _write(row: Dictionary) -> void:
	var amount := int(row["amount"])
	var words: String = REASON_TEXT.get(row["reason"], String(row["reason"]).to_upper())
	var sign_text := "+%d" if amount > 0 else "%d"
	HudStyle.set_fitted(row["label"], (sign_text % amount) + "  " + words, row["size"], room)
	(row["label"] as Label).modulate.a = 1.0


func _drop(row: Dictionary) -> void:
	rows.erase(row)
	var label: Label = row["label"]
	_stack.take_row(label)
	var spare: Array = _spare[1 if row["size"] == HudStyle.MEDIUM else 0]
	if spare.size() < MAX_ROWS:
		_shelf.add_child(label)
		spare.append(label)
	else:
		label.queue_free()


## A label for a row: one that left the list when there is one, made otherwise.
func _label(size: int, colour: Color, big: bool) -> Label:
	var spare: Array = _spare[1 if big else 0]
	if spare.is_empty():
		return HudStyle.clip(HudStyle.label("", size, colour, big))
	var label: Label = spare.pop_back()
	_shelf.remove_child(label)
	label.add_theme_color_override(&"font_color", colour)
	label.add_theme_font_size_override(&"font_size", size)
	label.modulate.a = 1.0
	return label


func _colour(reason: StringName, amount: int) -> Color:
	if amount < 0:
		return tokens.ink_muted
	if reason == &"headshot_kill" or reason == &"headshot_hit":
		return tokens.accent_bright
	return tokens.accent if reason == &"melee_kill" else tokens.ink
