extends Node3D
## The small map's cover and clutter props (issue #635) in a 8 x 6 m room, under the lot's own night
## (its `Environment` and moon, read from the greybox without building the lot) and one warm lamp:
## clutter at the edges, the middle open, the Soldier and a zombie for scale. Not part of the game.
## Run it with Movie Maker (through `gds godot`): `godot --path game
## res://tests/captures/smallmap_props.tscn --fixed-fps 10 --write-movie out.png --quit-after 12
## -- [--view=shoulder|over]`.

const LOT := "res://world/drive_in_greybox.tscn"
const FIXTURES := "res://world/smallmap/fixtures/%s.tscn"
const WALL := preload("res://assets/lot/materials/booth_wall.tres")
const FLOOR := preload("res://assets/lot/materials/booth_ground.tres")
const PLAQUE := preload("res://assets/lot/materials/plaque.tres")
const SOLDIER := "res://assets/characters/soldier/soldier.glb"
const ZOMBIE := "res://assets/characters/zombies/zombie_farmhand.glb"
const HALF_W := 4.0
const HALF_D := 3.0
const CEILING := 2.8
## [fixture, position on the floor, yaw in degrees (0: its room side faces +Z)], against the walls.
const PLACES := [
	["shelf_rack", Vector3(-3.0, 0, -2.75), 0.0],
	["tall_cabinet", Vector3(-1.55, 0, -2.72), 0.0],
	["filing_cabinet", Vector3(1.15, 0, -2.69), 0.0],
	["radio", Vector3(1.15, 1.3, -2.72), 0.0],
	["rubble_cone", Vector3(3.1, 0, -2.2), 0.0],
	["rubble_d", Vector3(2.25, 0, -2.5), 30.0],
	["rubble_c", Vector3(3.5, 0, -1.1), -20.0],
	["rubble_b", Vector3(2.3, 0, -1.6), 60.0],
	["rubble_a", Vector3(1.75, 0, -1.9), 10.0],
	["table", Vector3(-3.55, 0, -0.4), 90.0],
	["chair", Vector3(-2.85, 0, -0.1), -90.0],
	["lantern", Vector3(-3.6, 0.78, -0.75), 0.0],
	["helmet", Vector3(-3.0, 0, 1.0), 40.0],
	["table_tipped", Vector3(3.55, 0, 0.6), -90.0],
	["sandbags_2m", Vector3(1.9, 0, 2.2), 0.0],
	["sandbags_1m", Vector3(3.45, 0, 2.2), 0.0],
]
const VIEWS := {
	"shoulder": [Vector3(0.6, 1.85, 4.2), Vector3(0.0, 0.9, -1.8), 70.0],
	"over": [Vector3(0.0, 7.5, 6.5), Vector3(0.0, 0.0, -0.4), 55.0],
}


func _ready() -> void:
	var view := "shoulder"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			view = arg.trim_prefix("--view=")
	_night()
	_room(view != "over")
	for place in PLACES:
		var piece := (load(FIXTURES % place[0]) as PackedScene).instantiate() as Node3D
		piece.position = place[1]
		piece.rotation.y = deg_to_rad(place[2])
		add_child(piece)
		if place[0] == "tall_cabinet":
			_plaque(piece.get_node("PlaqueSlot") as Node3D)
	_character(SOLDIER, Vector3(0.4, 0, 1.4), 180.0, "Idle")
	_character(ZOMBIE, Vector3(1.0, 0, -1.2), 20.0, "Idle")
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = VIEWS[view][2]
	camera.look_at_from_position(VIEWS[view][0], VIEWS[view][1])
	camera.make_current()


## The lot's night: its WorldEnvironment's Environment and its moon, read from the scene's state.
func _night() -> void:
	var state := (load(LOT) as PackedScene).get_state()
	for i in state.get_node_count():
		var props := {}
		for p in state.get_node_property_count(i):
			props[state.get_node_property_name(i, p)] = state.get_node_property_value(i, p)
		if state.get_node_name(i) == "WorldEnvironment":
			var world := WorldEnvironment.new()
			world.environment = props["environment"]
			add_child(world)
		elif state.get_node_name(i) == "Moon":
			var moon := DirectionalLight3D.new()
			moon.transform = props["transform"]
			moon.light_color = props["light_color"]
			moon.light_energy = props["light_energy"]
			add_child(moon)
	# One pendant lamp's warm pool over the middle of the room (the lot's interior lamp numbers).
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, 2.3, 0.0)
	lamp.light_color = Color(1.0, 0.722, 0.4)
	lamp.light_energy = 1.6
	lamp.omni_range = 7.0
	add_child(lamp)


func _room(ceiling: bool) -> void:
	_box(Vector3(HALF_W * 2 + 0.6, 0.2, HALF_D * 2 + 0.6), Vector3(0, -0.1, 0), FLOOR)
	_box(Vector3(HALF_W * 2 + 0.6, CEILING, 0.3), Vector3(0, CEILING / 2, -HALF_D - 0.15), WALL)
	for s in [-1.0, 1.0]:
		_box(
			Vector3(0.3, CEILING, HALF_D * 2 + 0.6),
			Vector3(s * (HALF_W + 0.15), CEILING / 2, 0),
			WALL
		)
	if ceiling:
		_box(Vector3(HALF_W * 2 + 0.6, 0.2, HALF_D * 2 + 0.6), Vector3(0, CEILING + 0.1, 0), FLOOR)


func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var box := CSGBox3D.new()
	box.size = size
	box.position = at
	box.material = material
	add_child(box)


## The lot's wall-buy plaque (1.7 x 0.9 m), on end in the cabinet's recess, its name upright.
func _plaque(slot: Node3D) -> void:
	var plaque := CSGBox3D.new()
	plaque.size = Vector3(1.7, 0.9, 0.12)
	plaque.material = PLAQUE
	slot.add_child(plaque)
	var sign := Label3D.new()
	sign.text = "RIFLE"
	sign.pixel_size = 0.006
	sign.font_size = 44
	sign.outline_size = 18
	sign.modulate = Color(0.1, 0.07, 0.02)
	sign.outline_modulate = Color(1, 0.9, 0.6)
	sign.position = Vector3(0, 0, 0.07)
	sign.rotation.z = -PI / 2
	slot.add_child(sign)


func _character(path: String, at: Vector3, yaw: float, clip: String) -> void:
	var body := (load(path) as PackedScene).instantiate() as Node3D
	body.position = at
	body.rotation.y = deg_to_rad(yaw)
	add_child(body)
	var anim := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim != null and anim.has_animation(clip):
		anim.play(clip)
