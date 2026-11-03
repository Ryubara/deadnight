extends Node
## The small-map kit's stairs, rails and debris blocker (issue #634) in a room under the lot's night
## (its `Lighting`: the sky, ambient, fog and moon), for captures; not a test. First three stills
## (the room from two corners, the blocker close), then the player walks up the straight stair and
## back down through the real controller, filmed by the player's own camera:
##
##   godot --path game --write-movie <dir>/stairs.png --fixed-fps 30 \
##     res://tests/captures/smallmap_stairs.tscn
##
## Prints `STAIRS t=... y=... z=... stepped=... floor=...` every tenth of a second. The player
## is fed commands, never real input.

const FIXTURES := "res://world/smallmap/fixtures/"
const OVERVIEW_SECONDS := 3.0
const WAIT := 0.4
## The walk: up to the upper floor (z), turn round, back down to the start.
const START := Vector3(0.0, 0.05, 5.0)
const TOP_Z := -3.8
## How far the view looks down the stair on the way back (radians).
const DOWN := 0.4

var _player: Player
var _overview: Camera3D
var _ticks := 0
var _phase := 0
var _turn := 0.0
var _look := 0.0


func _ready() -> void:
	var lot: Node = load("res://world/drive_in_greybox.tscn").instantiate()
	var lighting := lot.get_node("Lighting")
	lot.remove_child(lighting)
	lot.free()
	add_child(lighting)
	_build_room()
	_player = (load("res://gameplay/player/player.tscn") as PackedScene).instantiate() as Player
	_player.capture_mouse = false
	_player.local_input = false
	add_child(_player)
	_player.teleport(START)
	_player.camera_rig.yaw = 0.0
	_player.camera_rig.snap_to(_player.global_position)
	_overview = Camera3D.new()
	_overview.fov = 62.0
	add_child(_overview)
	_overview.look_at_from_position(Vector3(7.0, 4.6, 6.5), Vector3(0.5, 1.2, -1.0))
	_overview.make_current()


func _box(size: Vector3, at: Vector3, colour: Color) -> void:
	var box := CSGBox3D.new()
	box.size = size
	box.use_collision = true
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	box.material = material
	add_child(box)
	box.position = at


func _fixture(scene: String, at: Vector3, yaw_degrees := 0.0) -> Node3D:
	var fixture := (load(FIXTURES + scene + ".tscn") as PackedScene).instantiate() as Node3D
	add_child(fixture)
	fixture.position = at
	fixture.rotation_degrees.y = yaw_degrees
	return fixture


## A room 12 x 11 m: the straight stair against the east wall of a stairwell, an upper floor
## with its edge railed, the L stair in the north-east corner, and a doorway in the west wall
## closed by the debris blocker with a warm room behind it.
func _build_room() -> void:
	var concrete := Color("9a968c")
	var plaster := Color("b3a588")
	var floor_tint := Color("8f8c84")
	_box(Vector3(16.0, 0.2, 14.0), Vector3(2.0, -0.1, 1.0), floor_tint)
	# The straight stair, climbing north, its open side west; a wall on its east side.
	_fixture("stair_straight", Vector3(0.0, 0.0, 0.0))
	_box(Vector3(0.3, 2.8, 4.5), Vector3(0.85 + 0.15, 1.4, 0.0), concrete)
	# The upper floor over the north of the room, its edge railed west of the stair.
	_box(Vector3(9.0, 0.2, 3.3), Vector3(0.0, 2.9, -3.9), Color("7d6446"))
	_fixture("landing_edge", Vector3(-1.75, 3.0, -2.4), 180.0)
	_fixture("landing_edge", Vector3(-3.75, 3.0, -2.4), 180.0)
	# The L stair in the north-east corner, turning left (west) onto the upper floor.
	_fixture("stair_l_left", Vector3(6.25, 0.0, -0.8))
	_box(Vector3(0.3, 5.8, 8.0), Vector3(8.15, 2.9, -1.5), plaster)
	_box(Vector3(12.0, 5.8, 0.3), Vector3(2.0, 2.9, -5.7), plaster)
	_box(Vector3(3.2, 0.2, 1.4), Vector3(2.9, 2.9, -1.85), Color("7d6446"))
	# The west wall with a 1.4 x 2.4 m doorway, and the debris blocker filling it.
	_box(Vector3(0.3, 2.8, 5.65), Vector3(-4.65, 1.4, -2.875), concrete)
	_box(Vector3(0.3, 2.8, 6.65), Vector3(-4.65, 1.4, 5.025), concrete)
	_box(Vector3(0.3, 0.4, 1.4), Vector3(-4.65, 2.6, 1.0), concrete)
	_fixture("debris_blocker", Vector3(-4.65, 0.0, 1.0), 90.0)
	# The lights: a warm pool over the stair's foot, and the unopened room's light behind the blocker.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("ffb866")
	lamp.light_energy = 2.2
	lamp.omni_range = 7.0
	add_child(lamp)
	lamp.position = Vector3(-1.6, 2.5, 2.6)
	var spill := OmniLight3D.new()
	spill.light_color = Color("ffb866")
	spill.light_energy = 3.0
	spill.omni_range = 4.0
	add_child(spill)
	spill.position = Vector3(-6.2, 1.8, 1.0)


func _physics_process(_delta: float) -> void:
	_ticks += 1
	var seconds := _ticks / 60.0
	if seconds < OVERVIEW_SECONDS:
		if seconds > OVERVIEW_SECONDS * 2.0 / 3.0:  # the third still: the debris blocker, close
			_overview.look_at_from_position(Vector3(-1.6, 1.6, 3.2), Vector3(-4.6, 1.1, 1.0))
		elif seconds > OVERVIEW_SECONDS / 3.0:  # the second: from the south-west, the stair's open side
			_overview.look_at_from_position(Vector3(-3.8, 3.6, 7.2), Vector3(0.0, 1.4, -1.0))
		_player.submit_command(PlayerCommand.new())
		return
	if _phase == 0:
		_phase = 1
		(
			(_player.camera_rig.find_children("*", "Camera3D", true, false)[0] as Camera3D)
			. make_current()
		)
	var command := PlayerCommand.new()
	var here := _player.state.position
	if _phase == 1:
		command.move = Vector2(0.0, -1.0) if seconds > OVERVIEW_SECONDS + WAIT else Vector2.ZERO
		if here.z < TOP_Z:
			_phase = 2
	elif _phase == 2:
		# Turn the view round on the upper floor, then walk back down facing the room.
		_turn = minf(_turn + PI / 45.0, PI)
		_look = maxf(_look - DOWN / 45.0, -DOWN)
		if is_equal_approx(_turn, PI):
			_phase = 3
	elif _phase == 3:
		command.move = Vector2(0.0, -1.0)
		if here.z > START.z:
			get_tree().quit()
	_player.camera_rig.yaw = _turn
	_player.camera_rig.pitch = _look
	command.yaw = _turn
	command.pitch = _look
	_player.submit_command(command)
	if _ticks % 6 == 0:
		print(
			(
				"STAIRS t=%.1f y=%.3f z=%.2f stepped=%.3f floor=%s"
				% [seconds, here.y, here.z, _player.state.stepped_up, _player.state.on_floor]
			)
		)
