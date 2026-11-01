class_name HudFeed
extends HudPart
## A short list of one-line notices that fade out oldest first. `EVENTS` (top right) says what
## happened on the lot: "RUBY OPENED THE CONCESSION STAND", someone down, the generator failing.
## `NOTICES` (beneath it, quieter) says who joined and who left. Time-driven (`advance`).

enum Kind { EVENTS, NOTICES }

## Rows kept at once: the event list is longer than the join and leave notices.
const MAX_EVENTS := 3
const MAX_NOTICES := 1
## Width of a row: wider than the column it hangs from, so an ordinary line ("PLAYER 1 OPENED THE
## CONCESSION STAND") shows in full. A row is one line (a wrapped row doubles the column's height
## and reaches the point gains below it): a long text first shrinks toward the smallest size, then
## ends in an ellipsis. The space left of the column under the banner is empty, so it costs nothing.
const ROW_WIDTH := 480.0
const LIFE := 4.5
const FADE := 0.6
const ITEM_NAMES := {
	&"door_concession": "OPENED THE CONCESSION STAND",
	&"door_booth": "OPENED THE PROJECTION BOOTH",
	&"door_back_lot": "OPENED THE BACK LOT",
	&"weapon_shotgun": "BOUGHT THE SHOTGUN",
	&"weapon_rifle": "BOUGHT THE RIFLE",
	&"crane_play": "PLAYED THE CRANE",
	&"fuel_can": "FILLED THE GENERATOR",
}
const CIRCUIT_WORDS := {
	&"screen_lot": "THE SCREEN LOT",
	&"concession": "THE CONCESSION STAND",
	&"booth": "THE BOOTH",
	&"back_lot": "THE BACK LOT",
}

@export var kind := Kind.EVENTS
## Rows alive, oldest first: {"label", "age"}.
var rows: Array[Dictionary] = []

var _box := VBoxContainer.new()
var _pad := MarginContainer.new()


func _init() -> void:
	super()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override(&"separation", HudStyle.GAP)
	# The rows end where the cards' text does, on the same right line.
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.add_theme_constant_override(&"margin_right", HudStyle.PAD)
	_pad.add_child(_box)
	add_child(_pad)
	_pad.minimum_size_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	return _pad.get_combined_minimum_size()


func _process(delta: float) -> void:
	advance(delta)


func texts() -> Array[String]:
	var list: Array[String] = []
	for row in rows:
		list.append((row["label"] as Label).text)
	return list


func on_event(event: Dictionary) -> void:
	var text := _text_for(event)
	if text != "":
		push(text)


func push(text: String, colour := Color.TRANSPARENT) -> void:
	var plain := tokens.ink if kind == Kind.EVENTS else tokens.ink_muted
	var label := HudStyle.clip(
		HudStyle.label(text, HudStyle.TEXT, colour if colour.a > 0.0 else plain, false, 1.0)
	)
	HudStyle.set_fitted(label, text, HudStyle.TEXT, ROW_WIDTH)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.custom_minimum_size.x = ROW_WIDTH
	rows.append({"label": label, "age": 0.0})
	_box.add_child(label)
	while rows.size() > (MAX_EVENTS if kind == Kind.EVENTS else MAX_NOTICES):
		_drop(rows[0])


func advance(delta: float) -> void:
	for row in rows.duplicate():
		row["age"] = float(row["age"]) + delta
		var left := LIFE - float(row["age"])
		(row["label"] as Label).modulate.a = clampf(left / FADE, 0.0, 1.0)
		if left <= 0.0:
			_drop(row)


func _drop(row: Dictionary) -> void:
	rows.erase(row)
	_box.remove_child(row["label"])
	(row["label"] as Label).queue_free()


func _text_for(event: Dictionary) -> String:
	var type := StringName(event.get("type", &""))
	if kind == Kind.NOTICES:
		return _notice(type, event)
	var who := _who(event)
	var text := ""
	match type:
		&"purchase_made":
			var item := StringName(event.get("item_id", &""))
			text = "%s %s" % [who, ITEM_NAMES.get(item, "BOUGHT SOMETHING")]
		&"player_downed":
			text = "%s IS DOWN" % who
		&"player_revived":
			text = "%s IS BACK UP" % who
		&"circuit_changed":
			var words: String = CIRCUIT_WORDS.get(event["circuit_id"], "THE LOT")
			text = "LIGHTS %s: %s" % ["ON" if event["on"] else "OFF", words]
		&"fuel_low":
			text = "GENERATOR RUNNING LOW"
		&"fuel_empty":
			text = "GENERATOR DEAD"
		&"fuel_restored":
			text = "GENERATOR IS BACK"
	return text


func _notice(type: StringName, event: Dictionary) -> String:
	if type == &"player_added":
		return "%s CONNECTED" % _who(event)
	if type == &"player_removed":
		return "%s LEFT" % state.left_name.to_upper()
	return ""


func _who(event: Dictionary) -> String:
	var member: Dictionary = state.team.get(int(event.get("player_id", -1)), {})
	return str(member.get("name", "SOMEONE")).to_upper()
