extends Node
## The HUD's world markers over a night the player walks (the player's own shoulder camera): a
## teammate's name over their head and the next door's diamond with its distance, while the player
## faces away from the door (the diamond pins to the edge with an arrow), turns toward it, walks
## to it, turns on the spot, and walks round the teammate. Not part of the game. Run with Movie
## Maker, through the kit's `gds godot` so no window takes the person's keyboard:
## `gds godot -- --path game res://tests/captures/hud_world_markers.tscn --fixed-fps 10
## --write-movie out.png --quit-after 700`. Arguments after `--`: `--hits` (shoot a zombie that
## stands in front instead, to see where damage numbers show).

const DOOR := &"door_concession"
## Seconds of the walk, by step.
const FACE_AWAY := 2.0
const TURN_TO_DOOR := 3.0
const WALK_TO_DOOR := 5.0
const SPIN := 6.0
const ORBIT := 7.0
const TURN_SPEED := 0.9
## Metres of the ring the player walks round the teammate.
const ORBIT_RADIUS := 6.0
const TEAMMATE_NAME := "Moe"

var _night: Night
var _yaw := 0.0
var _move := Vector2.ZERO
var _fire := false
var _hits := false


func _ready() -> void:
	_hits = OS.get_cmdline_user_args().has("--hits")
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL)
	_night.ticked.connect(_send)
	var player := _night.player()
	player.capture_mouse = false
	player.local_input = false
	_night.link.send({"type": NightServer.JOIN, "player_id": 2, "local": false})
	await _hold(2)
	# The teammate's body made its own camera the current one: look through the player's.
	player.camera_rig.camera().make_current()
	hud.state.set_player_name(2, TEAMMATE_NAME)
	hud.state.set_player_name(1, "You")
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	if _hits:
		await _shoot_a_zombie()
	else:
		await _walk(hud)
	get_tree().quit()


func _walk(hud: Hud) -> void:
	var door: Vector3 = _night.world.door_points(DOOR)[0]
	var start := Vector3(door.x, 0.1, door.z - 30.0)
	var player := _night.player()
	player.teleport(start)
	# The teammate stands beside the way to the door, a few metres off its line.
	var mate := _night.server.body_of(2)
	var mate_at := Vector3(door.x - 6.0, 0.1, door.z - 16.0)
	mate.teleport(mate_at)
	print("door ", door, " player ", start, " teammate ", mate_at)
	# Facing away from the door: its diamond pins to the bottom edge with an arrow.
	_yaw = 0.0
	player.camera_rig.yaw = _yaw
	await _hold_seconds(FACE_AWAY)
	print("facing away; pinned: ", hud.markers.placed)
	# Turn round to the door.
	var toward := atan2(-(door.x - start.x), -(door.z - start.z))
	await _turn_to(toward, TURN_TO_DOOR)
	_move = Vector2(0.0, -1.0)
	await _hold_seconds(WALK_TO_DOOR)
	_move = Vector2.ZERO
	# A full turn on the spot: the diamond swings round the edge, the name comes and goes.
	var around := SPIN * TURN_SPEED
	var steps := int(SPIN * 60.0)
	for i in steps:
		_yaw = toward + TAU * float(i) / float(steps)
		player.camera_rig.yaw = _yaw
		await get_tree().physics_frame
	# Round the teammate: strafe on a ring, looking at them.
	var centre := mate.global_position
	var ring := centre + Vector3(0.0, 0.0, ORBIT_RADIUS)
	player.teleport(Vector3(ring.x, 0.1, ring.z))
	var ticks := int(ORBIT * 60.0)
	for i in ticks:
		var angle := TAU * 0.75 * float(i) / float(ticks)
		var at := centre + Vector3(sin(angle), 0.0, cos(angle)) * ORBIT_RADIUS
		_yaw = atan2(-(centre.x - at.x), -(centre.z - at.z))
		player.camera_rig.yaw = _yaw
		_move = Vector2(1.0, 0.0)
		await get_tree().physics_frame
	_move = Vector2.ZERO
	print("done ", around)


func _turn_to(target: float, seconds: float) -> void:
	var start := _yaw
	var steps := int(seconds * 60.0)
	for i in steps:
		_yaw = lerp_angle(start, target, smoothstep(0.0, 1.0, float(i + 1) / float(steps)))
		_night.player().camera_rig.yaw = _yaw
		await get_tree().physics_frame


## A zombie stands six metres ahead of the lens in the line of fire; the player shoots it.
func _shoot_a_zombie() -> void:
	var player := _night.player()
	player.teleport(_night.world.player_spawn(0))
	_yaw = 0.0
	player.camera_rig.yaw = _yaw
	var zombie_id := -1
	while zombie_id == -1:
		await get_tree().physics_frame
		if not _night.server.sim.zombies.is_empty():
			zombie_id = _night.server.sim.zombies.keys()[0]
	for i in 240:
		var body: ZombieBody = _night.server.sim.zombies.get(zombie_id)
		if body != null:
			var aim := player.camera_rig.aim_transform()
			var at := aim.origin - aim.basis.z * 7.0
			body.position = Vector3(at.x, player.global_position.y, at.z)
		_fire = i % 30 < 8
		await get_tree().physics_frame
	_fire = false


## The command of this tick, sent as a player's controls would be.
func _send() -> void:
	var command := NightCommand.new()
	command.player_id = Night.PLAYER_ID
	command.motion.yaw = _yaw
	command.motion.move = _move
	command.fire = _fire
	var aim := _night.player().camera_rig.aim_transform()
	command.origin = aim.origin
	command.dir = -aim.basis.z
	_night.link.send(command.to_dict())


func _hold(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame


func _hold_seconds(seconds: float) -> void:
	await _hold(int(seconds * 60.0))
