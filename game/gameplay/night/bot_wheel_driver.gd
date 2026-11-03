class_name BotWheelDriver
extends Node
## Runs the bot command wheel for the person playing: it reads the `bot_wheel` action (Q, the pad's
## d-pad left, or the touch layer's BOTS button, which all press it), feeds the `BotWheel` from
## whatever points (the mouse's motion, the right stick, the finger dragging from the BOTS button),
## keeps the view still while the pointer is on the wheel, and gives the order at the release
## through `BotOrderLink`. The HUD says the new order for a moment.
##
## Sits under the night screen, which hands it the night, the HUD's wheel and the touch layer.
## `step` is the whole of a frame, so a test can run it by hand.

## The order was sent: the order and what `BotOrders.issue` answered.
signal ordered(order: StringName, sent: Dictionary)

const ACTION := &"bot_wheel"
## The right stick's dead zone, as the look reads it.
const STICK_DEADZONE := 0.25

var night: Night
## The HUD's drawing of the wheel; null in a test that draws nothing.
var hud_wheel: HudBotWheel
## The touch layer, for the finger on the BOTS button; null without one.
var touch: TouchControls
var model := BotWheel.new()
var link: BotOrderLink

var _stick_used := false
## Whether the action was down last frame: a hold that began while the night would not take it
## (paused) is not an open wheel the moment the night resumes.
var _was_down := false


func _ready() -> void:
	process_priority = -10
	if link == null and night != null:
		link = BotOrderLink.for_night(night)
	if hud_wheel != null:
		hud_wheel.wheel = model


func _process(delta: float) -> void:
	step(delta)


## One frame: opens or closes the hold by the action, moves the pointer, and gives the order when
## the hold ends on one.
func step(delta: float) -> void:
	_read_standing_order()
	var allowed := _can_command()
	var down := Input.is_action_pressed(ACTION)
	if model.is_holding() and not allowed:
		# The night paused or the controls went off under the hold: no order.
		model.cancel()
	elif down and allowed and not model.is_holding() and not _was_down:
		model.press()
		_stick_used = false
	elif not down and model.is_holding():
		_finish()
	_was_down = down
	if model.is_holding():
		_read_pointer()
	model.advance(delta)
	_lock_look(model.is_holding())


## While the wheel is held the mouse picks, not the view: a motion goes to the pointer and no
## further. A finger's stray copy in a browser is the touch layer's business, not a pointer.
func _input(event: InputEvent) -> void:
	if not model.is_holding() or not event is InputEventMouseMotion:
		return
	if TouchLook.is_stray(event) or (event as InputEventMouseMotion).device == TouchLook.DEVICE:
		return
	model.move_by((event as InputEventMouseMotion).relative)
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_lock_look(false)
	if Input.is_action_pressed(ACTION):
		Input.action_release(ACTION)


## The pointer from the right stick (its place, so letting go of the stick centres it) or from the
## finger on the BOTS button (its drag; a lifted finger leaves the pointer where it was, for the
## release that follows).
func _read_pointer() -> void:
	var stick := Input.get_vector(
		&"look_left", &"look_right", &"look_up", &"look_down", STICK_DEADZONE
	)
	if stick != Vector2.ZERO:
		_stick_used = true
		model.point_at(stick)
	elif _stick_used:
		_stick_used = false
		model.point_at(Vector2.ZERO)
	if touch != null and touch.has_wheel_finger():
		model.point_at(touch.wheel_offset() / BotWheel.TOUCH_REACH)


func _finish() -> void:
	var before := model.current
	var order := model.release()
	if order == &"":
		return
	var player := _player()
	var at := player.global_position if player != null else Vector3.ZERO
	var issuer_id := night.state.player_id if night != null and night.state != null else 0
	var sent := link.issue(order, issuer_id, at) if link != null else {}
	if sent.is_empty():
		# Refused before it left: nothing changed, and the wheel keeps the order that stands.
		model.current = before
		return
	ordered.emit(order, sent)
	if night != null and night.hud != null:
		night.hud.notices.push(BotWheel.NOTICES[order])


## The wheel can be held while the person has the controls on, in a night that is on.
func _can_command() -> bool:
	if night == null or night.state == null or night.state.over or not night.running:
		return false
	var player := _player()
	return player != null and player.controls_enabled()


## The team's standing order as the night's frame says it, when the night can say.
func _read_standing_order() -> void:
	if night == null or night.state == null or link == null:
		return
	var said := link.current(night.state.frame)
	if said != &"":
		model.current = said


func _lock_look(locked: bool) -> void:
	var player := _player()
	if player != null:
		player.look_locked = locked


## The person's body, once the night has one (not before it starts, not after it is freed).
func _player() -> Player:
	if night == null or not is_instance_valid(night) or night.state == null:
		return null
	var body := night.player()
	return body if body != null and is_instance_valid(body) else null
