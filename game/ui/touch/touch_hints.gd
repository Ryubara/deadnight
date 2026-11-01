class_name TouchHints
extends Control
## First-run labels on the touch controls: "DRAG TO MOVE" over the stick's place, "DRAG TO LOOK" in
## the look area and "TAP TO USE" beside the Interact button the first time it shows. Each is
## short, appears once, and goes the moment its control is used; what was used is remembered in the
## setting `controls/touch_hints_seen` (one bit per hint), so a player sees each hint once, ever.
## Resetting the settings to their defaults brings them back.
##
## It draws over `TouchControls` and only reads its geometry; the controls tell it what was used
## (`mark_used`). It takes no touches.

const MOVE := &"move"
const LOOK := &"look"
const INTERACT := &"interact"
## The order is the bit each hint owns in the saved mask.
const ORDER: Array[StringName] = [MOVE, LOOK, INTERACT]

const TEXT := {
	MOVE: "DRAG TO MOVE",
	LOOK: "DRAG TO LOOK",
	INTERACT: "TAP TO USE",
}
## The interact button's caption for a prompt that is held, not tapped (the fence).
const HOLD_VERB := "HOLD"
const HOLD_TEXT := "HOLD TO REPAIR"

const TEXT_SIZE := 36
const PAD := Vector2(22.0, 14.0)
const ICON_WIDTH := 64.0
const ICON_GAP := 14.0
## Distance from the stick ring, and from the interact button, to the label.
const GAP := 26.0
## Where the look hint sits in the safe rectangle (share of its width and height).
const LOOK_AT := Vector2(0.7, 0.26)
const FADE_IN := 0.35
const FADE_OUT := 0.25
const PULSE_PERIOD := 1.6

## The controls this draws over: its safe area, buttons, scale and caption.
var controls: TouchControls
## Whether the seen mask is read from and written to the Settings service. Tests turn it off.
var persist := true

var _seen := 0
var _clock := 0.0
## Seconds each hint has been showing, and seconds a used one has left to fade.
var _age := {}
var _leaving := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if persist:
		var service := _service()
		if service != null:
			_seen = int(service.call(&"get_value", SettingsService.TOUCH_HINTS_SEEN))


## The hints on screen now, in order: controls up, not used yet, and for Interact only while the
## button shows.
func showing() -> Array[StringName]:
	var found: Array[StringName] = []
	if controls == null or not controls.is_active():
		return found
	for id in ORDER:
		if is_seen(id):
			continue
		if id == INTERACT and controls.interact_verb() == "":
			continue
		found.append(id)
	return found


func is_seen(id: StringName) -> bool:
	return _seen & _bit(id) != 0


## The player used this control: its hint fades out and does not come back.
func mark_used(id: StringName) -> void:
	if is_seen(id):
		return
	var was_showing := id in showing()
	_seen |= _bit(id)
	if was_showing:
		_leaving[id] = FADE_OUT
	var service := _service() if persist else null
	if service != null:
		service.call(&"set_value", SettingsService.TOUCH_HINTS_SEEN, _seen)
	queue_redraw()


## Forget everything used, so every hint shows again.
func reset() -> void:
	_seen = 0
	_age.clear()
	_leaving.clear()
	var service := _service() if persist else null
	if service != null:
		service.call(&"set_value", SettingsService.TOUCH_HINTS_SEEN, 0)
	queue_redraw()


func text_for(id: StringName) -> String:
	if id == INTERACT and controls != null and controls.interact_verb() == HOLD_VERB:
		return HOLD_TEXT
	return TEXT[id]


## The label's rectangle in the controls' coordinates (canvas units), pill and icon included.
func rect_of(id: StringName) -> Rect2:
	var size := _pill_size(text_for(id))
	var safe := controls.safe_rect()
	var scale_value := controls.touch_scale
	match id:
		MOVE:
			var rest := TouchLayout.stick_rest(safe, scale_value)
			var top := rest.y - TouchLayout.STICK_RADIUS * scale_value - GAP
			return Rect2(Vector2(rest.x - size.x * 0.5, top - size.y), size)
		LOOK:
			var at := safe.position + safe.size * LOOK_AT
			return Rect2(at - size * 0.5, size)
		INTERACT:
			var circle := controls.button_circle(TouchLayout.INTERACT)
			var centre: Vector2 = circle[&"centre"]
			var left: float = centre.x - float(circle[&"radius"]) - GAP * 0.6
			return Rect2(Vector2(left - size.x, centre.y - size.y * 0.5), size)
	return Rect2()


func _process(delta: float) -> void:
	_clock += delta
	var now := showing()
	for id in ORDER:
		if id in now:
			_age[id] = float(_age.get(id, 0.0)) + delta
		else:
			_age.erase(id)
	for id: StringName in _leaving.keys():
		_leaving[id] = float(_leaving[id]) - delta
		if float(_leaving[id]) <= 0.0:
			_leaving.erase(id)
	if not now.is_empty() or not _leaving.is_empty():
		queue_redraw()


func _draw() -> void:
	if controls == null:
		return
	for id in showing():
		var age := minf(float(_age.get(id, 0.0)) / FADE_IN, 1.0)
		_draw_hint(id, age)
	for id: StringName in _leaving:
		_draw_hint(id, float(_leaving[id]) / FADE_OUT)


func _draw_hint(id: StringName, alpha: float) -> void:
	var tokens := UITokens.active()
	var font := _font(tokens)
	var rect := rect_of(id)
	var fill := Color(tokens.surface, 0.88 * alpha)
	draw_rect(
		Rect2(rect.position + Vector2(3.0, 4.0), rect.size),
		Color(tokens.shadow, tokens.shadow.a * alpha)
	)
	draw_rect(rect, fill)
	draw_rect(rect, Color(tokens.accent, alpha), false, 3.0)
	_draw_icon(id, tokens, Rect2(rect.position, Vector2(ICON_WIDTH + PAD.x, rect.size.y)), alpha)
	var at := (
		rect.position + Vector2(PAD.x + ICON_WIDTH + ICON_GAP, rect.size.y * 0.5 + TEXT_SIZE * 0.35)
	)
	draw_string(
		font, at, text_for(id), HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Color(tokens.ink, alpha)
	)


## A finger: a ring with a dot. A drag hint slides the dot along a track; a tap hint pulses it.
func _draw_icon(id: StringName, tokens: UITokens, box: Rect2, alpha: float) -> void:
	var centre := box.get_center()
	var ink := Color(tokens.accent_bright, alpha)
	var wave := 0.5 if UIMotion.reduced else 0.5 + 0.5 * sin(_clock * TAU / PULSE_PERIOD)
	if id == INTERACT:
		draw_circle(centre, 8.0, ink)
		draw_arc(
			centre,
			14.0 + 8.0 * wave,
			0.0,
			TAU,
			32,
			Color(ink, alpha * (1.0 - wave * 0.6)),
			3.0,
			true
		)
		return
	var half := ICON_WIDTH * 0.5 - 10.0
	draw_line(
		centre - Vector2(half, 0.0), centre + Vector2(half, 0.0), Color(ink, alpha * 0.5), 3.0, true
	)
	draw_circle(centre + Vector2(lerpf(-half, half, wave), 0.0), 9.0, ink)


func _pill_size(text: String) -> Vector2:
	var width := (
		_font(UITokens.active()).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
	)
	return Vector2(PAD.x * 2.0 + ICON_WIDTH + ICON_GAP + width, PAD.y * 2.0 + TEXT_SIZE)


func _font(tokens: UITokens) -> Font:
	return tokens.display_font(tokens.embolden_display * 0.3)


func _bit(id: StringName) -> int:
	return 1 << ORDER.find(id)


func _service() -> Node:
	if not is_inside_tree():
		return null
	var service := get_tree().root.get_node_or_null(TouchMode.SETTING_PATH)
	if service == null or not service.has_method(&"set_value"):
		return null
	return service
