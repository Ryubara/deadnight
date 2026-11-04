extends Node
## A player sprints at a line of five of the dead standing shoulder to shoulder and holds forward
## (#914), from the  player's own shoulder camera with the HUD. With `--dead=off` the dead stop
## nobody (how the game was before): the body runs through the line. With the dead on
## (`--dead=timed|wade|ramp`) it is stopped at the middle one, the push builds, and the zombie
## yields and the body follows it. The dead are the real ones (the server's sim, drawn from the
## frames, swinging at the player) but hurt nobody, so the film is not cut short. Not part of the
## game. Run with Movie Maker through the kit's `gds godot`: `gds godot -- --path game
## res://tests/captures/dead_push.tscn --fixed-fps 20 --write-movie out.png --quit-after 300 --
## --dead=ramp`.

const PLAYER_NAME := "Ruby"
## Seconds of the film before the player starts, and the seconds the push is held.
const LEAD_IN := 1.0
const PUSH_SECONDS := 9.0
## Metres from the player to the line of the dead, and the metres between them along it.
const LINE_AHEAD := 7.0
const LINE_GAP := 0.8
const LINE_COUNT := 5

var _night: Night
var _hud: Hud
var _pushing := false
var _args := {}


func _ready() -> void:
	_args = _parse_args()
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(_hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = _hud
	add_child(_night)
	var tuning := (load("res://gameplay/rules/default_tuning.tres") as RulesTuning).duplicate(true)
	tuning.rounds.first_spawn_delay = 600.0
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	_set_dead()
	_night.ticked.connect(_send)
	var player := _night.player()
	player.capture_mouse = false
	player.local_input = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _ticks(2)
	player.camera_rig.camera().make_current()
	_hud.state.set_player_name(1, PLAYER_NAME)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	var door: Vector3 = _night.world.door_points(_night.world.door_ids()[0])[0]
	var start := Vector3(door.x, 0.1, door.z - 18.0)
	_night.server.body_of(1).teleport(start)
	player.teleport(start)
	player.camera_rig.snap_to(start)
	player.camera_rig.yaw = 0.0
	player.camera_rig.pitch = -0.12
	for i in LINE_COUNT:
		var profile := ZombieProfile.plain(_night.server.sim.tuning)
		profile.damage = 0.0
		var zombie := _night.server.sim.spawn(
			900 + i,
			0.0,
			start + Vector3((i - LINE_COUNT / 2) * LINE_GAP, 0.0, -LINE_AHEAD),
			PI,
			profile
		)
		zombie.enter(ZombieBody.Mode.CHASE)
	await _seconds(LEAD_IN)
	print("STAGE push begins, dead: ", String(_args.get("dead", "timed")))
	_pushing = true
	await _seconds(PUSH_SECONDS)
	for i in LINE_COUNT:
		var zombie: ZombieBody = _night.server.sim.zombies[900 + i]
		print(
			(
				"zombie %d moved %.2f m"
				% [
					i,
					zombie.position.distance_to(
						start + Vector3((i - LINE_COUNT / 2) * LINE_GAP, 0.0, -LINE_AHEAD)
					)
				]
			)
		)
	print("player moved %.2f m" % player.global_position.distance_to(start))
	get_tree().quit()


func _set_dead() -> void:
	var tuning := _night.server.dead_tuning
	match String(_args.get("dead", "timed")):
		"off":
			tuning.enabled = false
		"wade":
			tuning.policy = DeadContactTuning.Policy.WADE
		"ramp":
			tuning.policy = DeadContactTuning.Policy.RAMP
			tuning.hold_seconds = 0.3
	if not tuning.enabled:
		_night.player().dead = null


func _send() -> void:
	var command := NightCommand.new()
	command.player_id = Night.PLAYER_ID
	var rig := _night.player().camera_rig
	command.motion.yaw = rig.yaw
	command.motion.pitch = rig.pitch
	var aim := rig.aim_transform()
	command.origin = aim.origin
	command.dir = -aim.basis.z
	if _pushing:
		command.motion.move = Vector2(0.0, -1.0)
		command.motion.sprint = true
	_night.link.send(command.to_dict())


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _ticks(int(seconds * 60.0))


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
