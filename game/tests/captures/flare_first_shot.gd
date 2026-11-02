extends Node
## The frame times around the first flare shot of a night, with the night's warm-up on or off
## (`-- --warm=1` or `--warm=0`): the number of #483 that the first shot hitched. Not part of the
## game. Run windowed through the kit (`gds godot -- --path game
## res://tests/captures/flare_first_shot.tscn
## -- --warm=1`); it prints each frame's time after the trigger, and the worst, in milliseconds,
## then quits.

const SECOND := 60
const WATCH_FRAMES := SECOND * 3

var _night: Night
var _times: Array[float] = []
var _fired_at := -1
var _recording := false


func _ready() -> void:
	var warm := NetArgs.new().get_int("warm", 1) == 1
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 1.0
	_night = Night.new()
	_night.warm_up = warm
	add_child(_night)
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	await get_tree().physics_frame
	var player := _night.player()
	player.local_input = false
	player.capture_mouse = false
	player.camera_rig.yaw = PI
	player.camera_rig.snap_to(player.global_position)
	_night.server.combat.apply(CombatAction.give_weapon(_night.PLAYER_ID, &"flare_gun"))
	_night.server.combat.apply(CombatAction.equip(_night.PLAYER_ID, &"flare_gun"))
	_recording = true
	await _wait(SECOND)
	_fired_at = _times.size()
	_button(true)
	await _wait(3)
	_button(false)
	await _wait(WATCH_FRAMES)
	_recording = false
	var after := _times.slice(_fired_at)
	var worst := 0.0
	var worst_at := 0
	for i in after.size():
		if after[i] > worst:
			worst = after[i]
			worst_at = i
	print(
		(
			"first flare shot, warm-up %s: worst frame %.1f ms at frame %d, frames over 25 ms: %d"
			% [warm, worst, worst_at, after.filter(func(t: float) -> bool: return t > 25.0).size()]
		)
	)
	print(
		"frames ms: ", ",".join(after.slice(0, 40).map(func(t: float) -> String: return "%.1f" % t))
	)
	get_tree().quit()


func _process(delta: float) -> void:
	if _recording:
		_times.append(delta * 1000.0)


func _wait(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
