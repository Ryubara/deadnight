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
##
## The pill (box, border, icon track, words) is drawn again only when something it shows changes:
## while it fades in or out, or when the layout or the theme change. The pulse of the finger icon
## (the dot sliding, the ring swelling) is a `_Mark` child whose position, scale and fade are set
## every frame: moving a drawn item makes no new draw command, while a `draw_circle` or `draw_arc`
## redrawn every frame makes the Compatibility renderer build a vertex array and buffers each time,
## and the web page keeps the WebGL ids of those for good (#834, #883).

const MOVE := &"move"
const LOOK := &"look"
const INTERACT := &"interact"
## The double tap on free ground that changes shoulder (#1288). It has no button to point at, so it
## waits until the player has looked, shows for `SWAP_SECONDS` and is then seen, used or not.
const SWAP := &"swap"
## The order is the bit each hint owns in the saved mask.
const ORDER: Array[StringName] = [MOVE, LOOK, INTERACT, SWAP]

const TEXT := {
	MOVE: "DRAG TO MOVE",
	LOOK: "DRAG TO LOOK",
	INTERACT: "TAP TO USE",
	SWAP: "DOUBLE TAP\nSWAP SIDE",
}
## The interact button's caption for a prompt that is held, not tapped (the fence).
const HOLD_VERB := "HOLD"
const HOLD_TEXT := "HOLD TO REPAIR"

## How long the shoulder hint stays, seconds: long enough to read it twice, short enough that a
## player who never needs the other shoulder is not shown it all night.
const SWAP_SECONDS := 8.0

const TEXT_SIZE := 36
## A hint of two lines (the shoulder's: a line break in its text) steps down this far between
## baselines: the smallest canvas has 436 units between the popup lane and the edge for a label.
const LINE_STEP := 44.0
const PAD := Vector2(22.0, 14.0)
const ICON_WIDTH := 64.0
const ICON_GAP := 14.0
## Distance from the stick ring, and from the interact button, to the label.
const GAP := 26.0
## Where the look hint sits down the safe rectangle (share of its height, its middle).
const LOOK_AT_Y := 0.24
## The look hint stands beside the column of the HUD's popup lane (cards in the middle of the
## screen, `PopupCard.WIDTH` wide), the look area's side of it, so a level up that comes while the
## hint is up covers neither (#1132): the hint is read, and so are the cards.
const LANE_HALF := PopupCard.WIDTH * 0.5
## The look hint goes down by this much at a time, and keeps this far from a button, canvas units.
const SEARCH_STEP := 8.0
const BUTTON_CLEAR := 8.0
const FADE_IN := 0.35
const FADE_OUT := 0.25
const PULSE_PERIOD := 1.6
## The tap hint's dot, and its ring at rest and at the most it swells.
const TAP_DOT := 8.0
const TAP_RING := 14.0
const TAP_SWELL := 8.0

## The controls this draws over: its safe area, buttons, scale and caption.
var controls: TouchControls
## Whether the seen mask is read from and written to the Settings service. Tests turn it off.
var persist := true

var _seen := 0
var _clock := 0.0
## Seconds each hint has been showing, and seconds a used one has left to fade.
var _age := {}
var _leaving := {}
var _painted := false
## What the pill drew last: a number that changes whenever the draw would, so `_process` redraws on
## a change only.
var _drawn_key := 0
## The marks, one per hint, made when first needed.
var _marks := {}
## Each hint's rectangle as of the last redraw.
var _rects := {}


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
		if id == SWAP and not is_seen(LOOK):
			continue  # first the look, then the other shoulder
		found.append(id)
	return found


## True while the last frame drawn had a label in it, fading out included.
func is_painted() -> bool:
	return _painted


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
	var mirrored := controls.left_handed
	match id:
		MOVE:
			var rest := TouchLayout.stick_rest(safe, scale_value, mirrored)
			var top := rest.y - TouchLayout.STICK_RADIUS * scale_value - GAP
			var rect := Rect2(
				Vector2(_off_the_lane(rest.x - size.x * 0.5, size.x, safe), top - size.y), size
			)
			# Ping stands under Pause, in the column above this hint on a short canvas (#1289).
			return _below_the_buttons(rect, safe)
		LOOK, SWAP:
			var middle := safe.get_center().x
			var left := middle - LANE_HALF - GAP - size.x if mirrored else middle + LANE_HALF + GAP
			var top := safe.position.y + safe.size.y * LOOK_AT_Y - size.y * 0.5
			return _below_the_buttons(Rect2(Vector2(left, top), size), safe)
		INTERACT:
			var circle := controls.button_circle(TouchLayout.INTERACT)
			var centre: Vector2 = circle[&"centre"]
			var beside := float(circle[&"radius"]) + GAP * 0.6
			var left: float = centre.x + beside if mirrored else centre.x - beside - size.x
			return Rect2(Vector2(left, centre.y - size.y * 0.5), size)
	return Rect2()


## The left edge of a hint `width` wide that would have its left edge at `left`, moved sideways off
## the popup lane's column (a small canvas puts the stick's hint under it) and kept in the safe
## area.
func _off_the_lane(left: float, width: float, safe: Rect2) -> float:
	var middle := safe.get_center().x
	var lane := Rect2(
		middle - LANE_HALF - GAP, safe.position.y, (LANE_HALF + GAP) * 2.0, safe.size.y
	)
	if left + width <= lane.position.x or left >= lane.end.x:
		return left
	if controls.left_handed:
		return maxf(lane.end.x, safe.position.x)
	return minf(lane.position.x - width, safe.end.x - width)


## `rect` moved, a step at a time, to the nearest place where no touch button is under it, up or
## down: the buttons climb up to the look hint's place beside the lane, and on a short screen a hint
## sent far down lands on the ammo card (#1277), so the smaller move wins.
func _below_the_buttons(rect: Rect2, safe: Rect2) -> Rect2:
	var circles := controls.circles()
	var steps := int(safe.size.y / SEARCH_STEP)
	for step in steps:
		# Down first at a tie: the hint was always found below.
		for way in [1.0, -1.0]:
			var moved := rect
			moved.position.y += way * float(step) * SEARCH_STEP
			if moved.position.y < safe.position.y or moved.end.y > safe.end.y:
				continue
			if _clear_of(moved, circles):
				return moved
	return rect


## Whether no button of `circles` is under `rect` or within `BUTTON_CLEAR` of it.
func _clear_of(rect: Rect2, circles: Dictionary) -> bool:
	for button: StringName in circles:
		var centre: Vector2 = circles[button][&"centre"]
		var reach := float(circles[button][&"radius"]) + BUTTON_CLEAR
		if centre.clamp(rect.position, rect.end).distance_to(centre) <= reach:
			return false
	return true


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
	if float(_age.get(SWAP, 0.0)) >= SWAP_SECONDS:
		mark_used(SWAP)  # said once: it is seen now, used or not
	var painting := not now.is_empty() or not _leaving.is_empty()
	var key := _look_key(now) if painting else 0
	# One more redraw after the last label goes, or its last, faint frame stays on the screen.
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()
	_painted = painting
	_move_marks(now)


## A number that differs whenever the pills would be drawn differently: which show, how far each is
## faded, where they sit and the look of the theme. The pulse is not in it.
func _look_key(now: Array[StringName]) -> int:
	if controls == null:
		return 0
	var fades := []
	for id in now:
		fades.append([id, _alpha_of(id), text_for(id)])
	for id: StringName in _leaving:
		fades.append([id, float(_leaving[id]) / FADE_OUT, true])
	return hash(
		[
			fades,
			controls.safe_rect(),
			controls.touch_scale,
			controls.left_handed,
			controls.interact_verb(),
			UITokens.active().get_instance_id(),
			UIMotion.reduced,
		]
	)


func _alpha_of(id: StringName) -> float:
	return minf(float(_age.get(id, 0.0)) / FADE_IN, 1.0)


func _draw() -> void:
	if controls == null:
		return
	_rects.clear()
	var tokens := UITokens.active()
	for id in showing():
		_draw_hint(id, _alpha_of(id), tokens)
	for id: StringName in _leaving:
		_draw_hint(id, float(_leaving[id]) / FADE_OUT, tokens)


func _draw_hint(id: StringName, alpha: float, tokens: UITokens) -> void:
	var font := _font(tokens)
	var rect := rect_of(id)
	_rects[id] = rect
	var fill := Color(tokens.surface, 0.88 * alpha)
	draw_rect(
		Rect2(rect.position + Vector2(3.0, 4.0), rect.size),
		Color(tokens.shadow, tokens.shadow.a * alpha)
	)
	draw_rect(rect, fill)
	draw_rect(rect, Color(tokens.accent, alpha), false, 3.0)
	_draw_icon(id, tokens, _icon_box(rect), alpha)
	var lines := text_for(id).split("\n")
	var at := (
		rect.position
		+ Vector2(
			PAD.x + ICON_WIDTH + ICON_GAP,
			rect.size.y * 0.5 + TEXT_SIZE * 0.35 - LINE_STEP * 0.5 * (lines.size() - 1)
		)
	)
	for line in lines:
		draw_string(
			font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Color(tokens.ink, alpha)
		)
		at.y += LINE_STEP


func _icon_box(rect: Rect2) -> Rect2:
	return Rect2(rect.position, Vector2(ICON_WIDTH + PAD.x, rect.size.y))


## The still part of the finger icon: the track a drag hint slides along, or the tap hint's dot.
## What moves is the `_Mark`.
func _draw_icon(id: StringName, tokens: UITokens, box: Rect2, alpha: float) -> void:
	var centre := box.get_center()
	var ink := Color(tokens.accent_bright, alpha)
	if _is_tap(id):
		draw_circle(centre, TAP_DOT, ink)
		return
	var half := _track_half()
	draw_line(
		centre - Vector2(half, 0.0), centre + Vector2(half, 0.0), Color(ink, alpha * 0.5), 3.0, true
	)


## A hint of a tap (a dot and a swelling ring), not of a drag.
func _is_tap(id: StringName) -> bool:
	return id == INTERACT or id == SWAP


func _track_half() -> float:
	return ICON_WIDTH * 0.5 - 10.0


## The wave of the pulse, 0 to 1: still at the middle under reduced motion.
func _wave() -> float:
	return 0.5 if UIMotion.reduced else 0.5 + 0.5 * sin(_clock * TAU / PULSE_PERIOD)


## Places the marks of the hints on screen, and hides the others. Only a position, a scale and a
## fade change, so nothing is drawn again.
func _move_marks(now: Array[StringName]) -> void:
	var wave := _wave()
	var tokens := UITokens.active()
	for id in ORDER:
		var mark: _Mark = _marks.get(id)
		var alpha := 0.0
		if id in now:
			alpha = _alpha_of(id)
		elif _leaving.has(id):
			alpha = float(_leaving[id]) / FADE_OUT
		if alpha <= 0.0 or not _rects.has(id):
			if mark != null:
				mark.visible = false
			continue
		if mark == null:
			mark = _Mark.new()
			mark.ring = _is_tap(id)
			add_child(mark)
			_marks[id] = mark
		mark.set_ink(tokens.accent_bright)
		mark.visible = true
		var centre := _icon_box(_rects[id]).get_center()
		if mark.ring:
			mark.position = centre
			mark.scale = Vector2.ONE * ((TAP_RING + TAP_SWELL * wave) / _Mark.RING_RADIUS)
			mark.modulate.a = alpha * (1.0 - wave * 0.6)
		else:
			var half := _track_half()
			mark.position = centre + Vector2(lerpf(-half, half, wave), 0.0)
			mark.modulate.a = alpha


func _pill_size(text: String) -> Vector2:
	var width := 0.0
	var lines := text.split("\n")
	for line in lines:
		width = maxf(
			width,
			(
				_font(UITokens.active())
				. get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE)
				. x
			)
		)
	return Vector2(
		PAD.x * 2.0 + ICON_WIDTH + ICON_GAP + width,
		PAD.y * 2.0 + TEXT_SIZE + LINE_STEP * (lines.size() - 1)
	)


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


## What moves in a hint's icon, drawn once at the size it is biggest and then scaled, moved and
## faded: a dot for a drag hint, a ring for a tap.
class _Mark:
	extends Node2D

	const RING_RADIUS := 22.0
	const DOT_RADIUS := 9.0

	var ring := false
	var _ink := Color.TRANSPARENT

	func set_ink(ink: Color) -> void:
		if ink != _ink:
			_ink = ink
			queue_redraw()

	func _draw() -> void:
		if ring:
			draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 32, _ink, 3.0, true)
		else:
			draw_circle(Vector2.ZERO, DOT_RADIUS, _ink)
