extends Node3D
## The small-map kit's walls, openings and floors (tools/blender/build_smallmap_walls.py) in Godot
## under the lot's night (its Environment and moon, taken from the greybox): a room corner built
## from the fixtures and the shell's CSG materials, seen from the shoulder camera's height and from
## above, and the whole kit in a row beside the Soldier and a zombie.
## Not part of the game. Run with a window (not headless), through the quiet launcher:
## `gds godot -- --path game res://tests/captures/smallmap_walls_tour.tscn --resolution 1600x900
## -- --out=<folder>`.

const FIXTURES := "res://world/smallmap/fixtures/%s.tscn"
const MATERIALS := "res://assets/lot/materials/%s.tres"
const GREYBOX := "res://world/drive_in_greybox.tscn"
const SOLDIER := "res://assets/characters/soldier/soldier.glb"
const ZOMBIE := "res://assets/characters/zombies/zombie_farmhand.glb"
## The room: 8 x 6 m inside, the back wall on z = -3, the floor at y = 0, the ceiling at 2.8 m.
const HALF_W := 4.0
const HALF_D := 3.0
const CLEAR := 2.8
const WALL_T := 0.3
const LINEUP := [
	"wall_door_narrow",
	"door_purchase",
	"wall_opening_wide",
	"wall_arch",
	"wall_window_zombie",
	"wall_window_glazed",
	"wall_barred",
	"wall_broken",
	"pillar",
	"beam_2",
	"trim_corner",
	"trim_end",
	"floor_edge_broken",
	"wall_door_narrow_upper",
	"wall_window_zombie_upper",
	"wall_window_glazed_upper",
	"wall_broken_upper",
]
const SETTLE_FRAMES := 6

var _out := "user://smallmap_walls"
var _ceiling: CSGBox3D
var _camera: Camera3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_night()
	_room()
	_lineup(Vector3(-14.0, 0.0, 14.0))
	_camera = Camera3D.new()
	_camera.fov = 70.0
	add_child(_camera)
	_camera.make_current()
	# The shoulder camera: pivot 1.6 m over the feet, 0.6 m right, 2.3 m back (PlayerTuning).
	await _shot("room_shoulder", Vector3(1.4, 1.85, 2.9), Vector3(0.4, 1.3, -3.0))
	await _shot("room_window", Vector3(-1.2, 1.7, 0.2), Vector3(-3.4, 1.4, -3.0))
	_ceiling.visible = false
	_camera.fov = 55.0
	await _shot("room_above", Vector3(0.0, 9.0, 8.0), Vector3(0.0, 0.5, -0.6))
	await _shot("lineup_a", Vector3(-8.5, 3.0, 25.5), Vector3(-8.5, 1.3, 14.0))
	await _shot("lineup_b", Vector3(9.0, 3.0, 25.5), Vector3(9.0, 1.3, 14.0))
	get_tree().quit()


func _shot(shot: String, from: Vector3, at: Vector3) -> void:
	_camera.look_at_from_position(from, at)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot])
	print("shot ", shot)


## The lot's night: the greybox's own Environment and moon.
func _night() -> void:
	var greybox := (load(GREYBOX) as PackedScene).instantiate()
	var env := greybox.get_node(^"Lighting/WorldEnvironment") as WorldEnvironment
	var moon := greybox.get_node(^"Lighting/Moon") as DirectionalLight3D
	var world := WorldEnvironment.new()
	world.environment = env.environment
	add_child(world)
	var light := moon.duplicate() as DirectionalLight3D
	add_child(light)
	greybox.free()


func _fixture(piece: String, at: Vector3, yaw: float = 0.0, parent: Node = self) -> Node3D:
	var node := (load(FIXTURES % piece) as PackedScene).instantiate() as Node3D
	node.position = at
	node.rotation.y = deg_to_rad(yaw)
	parent.add_child(node)
	return node


func _box(size: Vector3, at: Vector3, material: String) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.size = size
	box.position = at
	box.material = load(MATERIALS % material)
	add_child(box)
	return box


func _lamp(at: Vector3, energy: float, reach: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = at
	lamp.light_color = Color(1.0, 0.722, 0.4)  # the lot's sodium, #ffb866
	lamp.light_energy = energy
	lamp.omni_range = reach
	add_child(lamp)


## The game's characters at the game's own scales
## (PlayerTuning.model_scale, ZombieModels.GAME_SCALE).
func _character(path: String, at: Vector3, yaw: float) -> void:
	var body := (load(path) as PackedScene).instantiate() as Node3D
	var game_scale := ZombieModels.GAME_SCALE if path == ZOMBIE else PlayerTuning.new().model_scale
	body.scale = Vector3.ONE * game_scale
	body.position = at
	body.rotation.y = deg_to_rad(yaw)
	add_child(body)
	var clips := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if clips:
		for clip in clips.get_animation_list():
			if clip.ends_with("Idle"):
				clips.play(clip)
				break


func _room() -> void:
	var back := -HALF_D - WALL_T / 2.0
	var side := HALF_W + WALL_T / 2.0
	_box(
		Vector3(2 * side + 0.3, 0.2, 2 * HALF_D + 1.0), Vector3(0, -0.1, 0), "smallmap_floor_ground"
	)
	_ceiling = _box(
		Vector3(2 * side + 0.3, 0.2, 2 * HALF_D + 1.0),
		Vector3(0, CLEAR + 0.1, 0),
		"smallmap_ceiling"
	)
	# The back wall: the zombie window (boarded at its markers), the purchase door, an arch, a broken
	# module; block corners at both ends.
	var window := _fixture("wall_window_zombie", Vector3(-3, 0, back))
	for slot in window.find_children("BoardSlot*", "Marker3D", false, false):
		var board := (load(FIXTURES % "window_board") as PackedScene).instantiate() as Node3D
		board.transform = (slot as Marker3D).transform
		window.add_child(board)
	_fixture("wall_door_narrow", Vector3(-1, 0, back))
	_fixture("door_purchase", Vector3(-1, 0.02, back))
	_fixture("wall_arch", Vector3(1, 0, back))
	_fixture("wall_broken", Vector3(3, 0, back))
	for x: float in [-side, side]:
		_fixture("trim_corner", Vector3(x, 0, back))
	# The west wall (its room side faces +X): a glazed window, a plain block wall, bars
	# between pillars.
	_fixture("wall_window_glazed", Vector3(-side, 0, -2.0), 90.0)
	_box(Vector3(WALL_T, CLEAR, 2.0), Vector3(-side, CLEAR / 2.0, 0.0), "smallmap_wall_ground")
	_fixture("wall_barred", Vector3(-side, 0, 2.0), 90.0)
	# The east wall: the wide opening and a plain block wall, an end trim where it stops.
	_fixture("wall_opening_wide", Vector3(side, 0, -1.5), -90.0)
	_box(Vector3(WALL_T, CLEAR, 3.0), Vector3(side, CLEAR / 2.0, 1.5), "smallmap_wall_ground")
	# A pillar in the middle carrying two beams to the side walls.
	_fixture("pillar", Vector3(0, 0, 0))
	_fixture("beam_4", Vector3(-2.0, 0, 0))
	_fixture("beam_4", Vector3(2.0, 0, 0))
	_character(SOLDIER, Vector3(0.8, 0, 1.4), 180.0)
	_character(ZOMBIE, Vector3(-3.0, 0, -2.2), 0.0)
	_lamp(Vector3(-1.4, 2.3, -1.2), 1.6, 7.0)  # where a pendant lamp hangs over the door


func _lineup(origin: Vector3) -> void:
	_box(Vector3(34.0, 0.2, 5.0), origin + Vector3(14.0, -0.1, 0.0), "smallmap_floor_ground")
	_character(SOLDIER, origin + Vector3(-1.6, 0, 0), 0.0)
	_character(ZOMBIE, origin + Vector3(-0.6, 0, 0), 0.0)
	var x := 0.6
	for piece: String in LINEUP:
		var node := _fixture(piece, origin)
		var box := _bounds(node)
		var lift := 3.0 if piece == "floor_edge_broken" else 0.0
		node.position = origin + Vector3(x - box.position.x, lift, 0.0)
		x += box.size.x + 0.5
	for i in 4:
		_lamp(origin + Vector3(-1.0 + i * 9.0, 4.0, 3.0), 2.0, 10.0)


func _bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var inst := mesh as MeshInstance3D
		var box := inst.get_aabb()
		var local := Transform3D.IDENTITY
		var at: Node = inst
		while at != node:
			local = (at as Node3D).transform * local
			at = at.get_parent()
		box = local * box
		out = box if first else out.merge(box)
		first = false
	return out
