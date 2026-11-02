extends Node
## A teammate marks a door and a place with pings, goes down, and the player raises them: the
## prompt, the held use button, the progress on the prompt, the mark's diamond over the view and
## the feed lines. The player's own shoulder camera, driven through commands like a person's
## controls (and the real server rules). Not part of the game. Run with Movie Maker, through the
## kit's `gds godot` so no window takes the person's keyboard:
## `gds godot -- --path game res://tests/captures/revive_and_ping.tscn --fixed-fps 10
## --write-movie out.png --quit-after 260`.

const DOOR_INDEX := 0
## Where the downed teammate lies, ahead of the player, and where the place ping goes.
const MATE_AHEAD := 1.6
const PING_AHEAD := 14.0
const TEAMMATE_NAME := "Moe"
const LEAD_IN := 1.5
const PINGED := 2.5
const HOLD_FOR := 7.0
const TAIL := 2.5

var _night: Night
var _hold := false


func _ready() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	var tuning := (load("res://gameplay/rules/default_tuning.tres") as RulesTuning).duplicate(true)
	tuning.rounds.first_spawn_delay = 600.0
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	_night.ticked.connect(_send)
	var player := _night.player()
	player.capture_mouse = false
	player.local_input = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_night.link.send({"type": NightServer.JOIN, "player_id": 2, "local": false})
	await _ticks(2)
	player.camera_rig.camera().make_current()
	hud.state.set_player_name(2, TEAMMATE_NAME)
	hud.state.set_player_name(1, "You")
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	# The player stands facing the concession stand's door, the teammate a few steps ahead.
	var door: Vector3 = _night.world.door_points(_night.world.door_ids()[DOOR_INDEX])[0]
	var start := Vector3(door.x, 0.1, door.z - 18.0)
	player.teleport(start)
	var yaw := 0.0
	player.camera_rig.yaw = yaw
	player.camera_rig.pitch = -0.12
	_night.server.body_of(2).teleport(start + Vector3(0.0, 0.0, -MATE_AHEAD))
	await _seconds(LEAD_IN)
	# The teammate marks the door and then the open ground; the player sees both.
	print("door ping: ", _night.server.ping(2, _ask(PingBoard.DOOR, door, DOOR_INDEX)))
	await _seconds(PINGED)
	print(
		"place ping: ",
		_night.server.ping(2, _ask(PingBoard.HERE, start + Vector3(5.0, 0.0, -PING_AHEAD)))
	)
	await _seconds(PINGED)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.blow(2, 500.0)))
	await _seconds(1.0)
	_hold = true
	await _seconds(HOLD_FOR)
	print(
		"revived: ",
		not _night.server.rules.players[2].downed,
		" health ",
		_night.server.rules.health_of(2)
	)
	_hold = false
	await _seconds(TAIL)
	get_tree().quit()


func _ask(kind: StringName, at: Vector3, subject: int = 0) -> Dictionary:
	return {"type": NightServer.PING, "kind": kind, "pos": at, "subject": subject}


func _send() -> void:
	var command := NightCommand.new()
	command.player_id = Night.PLAYER_ID
	var rig := _night.player().camera_rig
	command.motion.yaw = rig.yaw
	command.motion.pitch = rig.pitch
	command.use_held = _hold
	var aim := rig.aim_transform()
	command.origin = aim.origin
	command.dir = -aim.basis.z
	_night.link.send(command.to_dict())


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _ticks(int(seconds * 60.0))
