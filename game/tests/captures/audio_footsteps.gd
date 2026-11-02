extends Node
## Capture of the player's footsteps against the rest of a night's mix, for `docs/research/audio.md`
## (Footsteps) and `tools/audio/step_levels.py`. Run with Movie Maker (`--write-movie out.png
## --fixed-fps 10`), which writes the mix to `out.wav`; every step prints `STEP <seconds> <id>` and
## every stage `STAGE <seconds> <name>`.
##
## The scripted night (default) gives the player's own body a command every tick: standing in the
## night's bed, walking, sprinting and crouching on asphalt, walking on gravel, then firing the
## starting gun, and a teammate (made from frames, as an online night draws one) walking by. With
## `--autopilot` the night is the real thing: the bot fights through round after round, seen from
## its shoulder camera (`--seconds=S`, default 60). The body's own input and its mouse capture are
## off in both (`local_input`, `capture_mouse`), so nothing here depends on a person at the machine
## or takes their cursor.

const MOVIE_FPS := 10.0
const TURN_RATE := 0.9
## In the yard the player circles tighter (and the other way) to stay on its open ground.
const YARD_TURN_RATE := -1.4
## Where that ground is clear of the generator and the cages, from the first slab's centre.
const YARD_OPEN_GROUND := Vector3(-8.0, 0.3, 6.0)
const STAGES := [
	["bed", 7.0],
	["walk_asphalt", 7.0],
	["sprint_asphalt", 6.0],
	["crouch_asphalt", 7.0],
	["still", 4.0],
	["walk_gravel", 7.0],
	["gunfire", 6.0],
	["teammate", 8.0],
]
const CAMERA_BACK := Vector3(0.7, 2.1, 3.4)
const TEAMMATE_ID := 2
const TEAMMATE_SPEED := 4.8
const TEAMMATE_LANE := 6.0

var _night: Night
var _camera: Camera3D
var _label: Label
var _command := NightCommand.new()
var _yaw := 0.0
var _turn := TURN_RATE
var _teammate: ClientState
var _teammate_feet: FootstepSounds
var _teammate_tick := 0
var _teammate_from := Vector3.ZERO
var _teammate_walking := false
var _args := {}
var _peak_voices := 0


func _ready() -> void:
	_args = _parse_args()
	Audio.seed_random(239)
	if Audio.has_signal(&"played"):
		Audio.connect(&"played", _on_played)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	if _args.has("autopilot"):
		await _autopilot()
	else:
		await _scripted()
	print(
		"VOICES started %d culled %d peak at once %d" % [Audio.started, Audio.culled, _peak_voices]
	)
	Audio.stop_all()
	_night.queue_free()
	await _hold(3.0)
	get_tree().quit()


func _autopilot() -> void:
	_night = Night.new()
	add_child(_night)
	_night.shoulder_camera = true
	await _night.start(Night.Mode.AUTOPILOT, Night.SEED, _fast_tuning())
	_keep_the_cursor_free()
	_say("Autopilot night, shoulder camera")
	await _hold(float(_args.get("seconds", 60.0)))


func _scripted() -> void:
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, Night.SEED, _fast_tuning())
	_keep_the_cursor_free()
	_camera = Camera3D.new()
	_camera.fov = 62.0
	add_child(_camera)
	_camera.make_current()
	_far_gate_only()
	var field := _night.player().global_position
	_night.server.rules.apply(RulesAction.skip_break())
	for stage: Array in STAGES:
		var stage_name: String = stage[0]
		_say(stage_name)
		match stage_name:
			"walk_asphalt":
				_move(false, false)
			"sprint_asphalt":
				_move(true, false)
			"crouch_asphalt":
				_move(false, true)
			"still":
				_command = NightCommand.new()
			"walk_gravel":
				_night.player().teleport(_yard_point())
				_move(false, false)
				_turn = YARD_TURN_RATE
			"gunfire":
				_night.player().teleport(field)
				_fire()
			"teammate":
				_command = NightCommand.new()
				_start_teammate()
		await _hold(stage[1])
	_teammate_walking = false
	_teammate_feet.queue_free()


## A windowed capture never takes the cursor of the person at the machine: the body's input and its
## mouse capture are off (the night already builds it so; this says it again) and the mouse is
## left visible.
func _keep_the_cursor_free() -> void:
	var body := _night.player()
	body.local_input = false
	body.capture_mouse = false
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the capture must not hold the mouse")
	print("MOUSE mode %d (0 is visible)" % Input.mouse_mode)


## The dead come from the gate farthest from the player, so none reaches them during the capture.
func _far_gate_only() -> void:
	var gates := _night.world.spawn_gates()
	var far: Vector3 = gates.keys()[0]
	for point: Vector3 in gates:
		if (
			point.distance_to(_night.player().global_position)
			> far.distance_to(_night.player().global_position)
		):
			far = point
	var only: Array[Vector3] = [far]
	_night.server.director.spawn_points = only


func _yard_point() -> Vector3:
	var ground := _night.world.greybox.get_node("GeneratorYard/Ground0_0") as CSGBox3D
	return ground.global_position + YARD_OPEN_GROUND


func _move(sprint: bool, crouch: bool) -> void:
	_command = NightCommand.new()
	_command.motion.move = Vector2(0.0, -1.0)
	_command.motion.sprint = sprint
	_command.motion.crouch = crouch
	_turn = TURN_RATE


## The trigger held, at a point down the lot.
func _fire() -> void:
	_command = NightCommand.new()
	var eye := _night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	_command.origin = eye
	_command.aim_along(Vector3(0.0, -0.02, -1.0))
	_command.muzzle = eye + _command.dir * 0.8
	_command.fire = true


func _physics_process(delta: float) -> void:
	_peak_voices = maxi(_peak_voices, Audio.active_voices())
	if _camera == null or _night == null or _night.player() == null:
		return
	if _command.motion.move != Vector2.ZERO:
		_yaw += _turn * delta
	_command.motion.yaw = _yaw
	_night.link.send(_command.to_dict())
	var at := _night.player().global_position
	_camera.look_at_from_position(
		at + Basis(Vector3.UP, _yaw) * CAMERA_BACK, at + Vector3(0.0, 1.4, 0.0)
	)
	if _teammate_walking:
		_step_teammate()


## A second player as an online client sees one: frames, and nothing else (`FootstepSounds` reads
## the stride from the positions). Their own state, so the night's frames are left alone.
func _start_teammate() -> void:
	_teammate = ClientState.new()
	_teammate.player_id = Night.PLAYER_ID
	_teammate_feet = FootstepSounds.new()
	add_child(_teammate_feet)
	_teammate_feet.setup(_teammate, func(_id: int) -> Player: return null, 7)
	var at := _night.player().global_position
	_teammate_from = at + Vector3(-18.0, 0.0, -TEAMMATE_LANE)
	_teammate_tick = 0
	_teammate_walking = true


func _step_teammate() -> void:
	_teammate_tick += 1
	if _teammate_tick % 2 != 0:
		return
	var at := _teammate_from + Vector3(TEAMMATE_SPEED * _teammate_tick / 60.0, 0.0, 0.0)
	var frame := {
		"type": &"frame",
		"tick": _teammate_tick,
		"players": {TEAMMATE_ID: {"pos": at, "downed": false}},
		"zombies": ZombieCodec.encode({}),
	}
	_teammate.apply_events([frame])


func _fast_tuning() -> RulesTuning:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.intro_seconds = 3.0
	tuning.rounds.first_spawn_delay = 0.5
	return tuning


func _on_played(id: StringName, position: Variant) -> void:
	var text := String(id)
	if text.begins_with("step_"):
		print("STEP %.2f %s %s" % [Engine.get_frames_drawn() / MOVIE_FPS, id, position != null])
	elif text.begins_with("shot_"):
		print("SHOT %.2f %s" % [Engine.get_frames_drawn() / MOVIE_FPS, id])


func _say(text: String) -> void:
	_label.text = text
	print("STAGE %.2f %s" % [Engine.get_frames_drawn() / MOVIE_FPS, text])


func _hold(seconds: float) -> void:
	for _i in int(seconds * 60.0):
		await get_tree().physics_frame


func _parse_args() -> Dictionary:
	var out := {}
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		out[parts[0]] = parts[1] if parts.size() > 1 else true
	return out
