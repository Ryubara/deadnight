class_name BotWheelDriver
extends Node
## Runs the bot command wheel for the person playing: it reads the `bot_wheel` action (Q, the pad's
## d-pad left), feeds the `BotWheel` from whatever points (the mouse's motion, the right stick),
## keeps the view still while the pointer is on the wheel, and gives the order at the release
## through `BotOrderLink`. A phone has no wheel: a tap on the HUD's tag presses `bot_order_next`
## (#1286), which gives the order after the one that stands, through the same link. The HUD says
## the bots' state for a moment once the night's frame shows it changed, so an order the server
## refused (or the link did) says nothing and changes nothing.
##
## Sits under the night screen, which hands it the night, the HUD's wheel and the touch layer.
## `step` is the whole of a frame, so a test can run it by hand.

## The order was sent: the order and what `BotOrders.issue` answered.
signal ordered(order: StringName, sent: Dictionary)

const ACTION := &"bot_wheel"
## Pressed by a tap on a phone's tag: the next order of the round.
const NEXT_ACTION := &"bot_order_next"
## The right stick's dead zone, as the look reads it.
const STICK_DEADZONE := 0.25

var night: Night
## The HUD's drawing of the wheel; null in a test that draws nothing.
var hud_wheel: HudBotWheel
var model := BotWheel.new()
var link: BotOrderLink

var _stick_used := false
## The order the night's frame said last (`&""` before the first), to tell a change from the start.
var _known: StringName = &""
## Whether the next-order action was down last frame (a tap gives one order, not one a frame).
var _was_next := false
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
	_read_next(allowed)
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


## The pointer from the right stick (its place, so letting go of the stick centres it).
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


## A tap on the tag gives the order after the one that stands, unless the night would not take an
## order now (paused, over, a body that cannot act): then the press is spent on nothing, and a press
## that began then is not an order the moment the night resumes.
func _read_next(allowed: bool) -> void:
	var down := Input.is_action_pressed(NEXT_ACTION)
	if down and not _was_next and allowed:
		_give(BotWheel.next_after(model.current))
	_was_next = down


func _finish() -> void:
	var before := model.current
	var order := model.release()
	if order == &"":
		return
	if not _give(order):
		# Refused before it left: nothing changed, and the wheel keeps the order that stands.
		model.current = before


## Gives `order` for the person through the link. False when it was refused before it left.
func _give(order: StringName) -> bool:
	var player := _player()
	var at := player.global_position if player != null else Vector3.ZERO
	var issuer_id := night.state.player_id if night != null and night.state != null else 0
	var sent := link.issue(order, issuer_id, at) if link != null else {}
	if sent.is_empty():
		return false
	ordered.emit(order, sent)
	return true


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
	if said == &"":
		return
	if _known != &"" and said != _known and night.hud != null:
		night.hud.notices.push(BotWheel.NOTICES[said])
	_known = said
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
