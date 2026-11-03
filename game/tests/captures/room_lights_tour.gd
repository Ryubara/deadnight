extends Node
## Rooms lit by their own lamps and not by the next room's (issue #841;
## docs/research/room-lights.md): each map from inside a room and from the room behind a wall, with
## every circuit on, one PNG a shot. `--map=lot` (the drive-in) or `--map=small` (the second map);
## `--out=<folder>`; `--flat` puts every box back on the default render layer and every light on
## every layer, which is how the maps were lit before the room layers (the "before" frames;
## `--flat-boxes` and `--flat-lights` do one half each);
## `--spot` makes the booth's lower lamp a downward spot (the idea that was not taken); `--bench`
## times 150 frames in each pose with vertical sync and the frame limit off. Not part of the game.
## Run with a window through the quiet launcher:
## `gds godot -- --path game res://tests/captures/room_lights_tour.tscn --resolution 1280x720
## -- --map=small --out=<folder>`.

const SMALL := "res://world/smallmap/smallmap_greybox.tscn"
## Name: [camera position, the point it looks at].
const LOT_SHOTS := {
	"lot_1_stand_floor": [Vector3(0.0, 1.7, 6.5), Vector3(-1.0, 0.0, -2.0)],
	"lot_2_stand_roof": [Vector3(0.0, 1.7, 5.0), Vector3(0.0, 4.0, -3.0)],
	"lot_3_stand_north_wall": [Vector3(-6.0, 1.7, 5.0), Vector3(4.0, 1.0, -4.0)],
	"lot_4_alley_east": [Vector3(13.0, 1.8, 7.0), Vector3(13.0, 0.3, -3.0)],
	"lot_5_booth_below": [Vector3(0.0, 1.7, 24.5), Vector3(0.0, 3.4, 30.5)],
	"lot_6_booth_above_wall": [Vector3(1.0, 5.2, 29.5), Vector3(0.0, 4.4, 22.2)],
	"lot_7_booth_roof": [Vector3(0.0, 5.3, 30.5), Vector3(0.0, 7.4, 24.0)],
	"lot_8_field_stand_wall": [Vector3(0.0, 1.8, -14.0), Vector3(0.0, 1.5, -4.0)],
	"lot_9_stand_door_outside": [Vector3(0.0, 1.7, 15.0), Vector3(0.0, 1.0, 8.0)],
}
const SMALL_SHOTS := {
	"small_1_start_hall": [Vector3(8.0, 1.7, 13.5), Vector3(8.0, 0.8, 2.5)],
	"small_2_start_west": [Vector3(14.5, 1.7, 13.0), Vector3(2.0, 1.0, 5.0)],
	"small_3_upper_a_south_base": [Vector3(8.0, 5.1, 0.8), Vector3(8.0, 3.7, 4.5)],
	"small_4_upper_a_floor": [Vector3(3.0, 5.1, 4.0), Vector3(12.0, 3.4, 1.0)],
	"small_5_side_room": [Vector3(14.5, 1.7, -7.0), Vector3(3.0, 1.0, -2.0)],
	"small_6_upper_b_south_base": [Vector3(8.0, 5.1, -6.0), Vector3(8.0, 3.7, -0.3)],
	"small_7_side_roof": [Vector3(8.0, 1.7, -5.5), Vector3(8.0, 3.3, -1.5)],
	"small_8_start_roof": [Vector3(8.0, 1.7, 11.0), Vector3(8.0, 3.1, 3.0)],
	"small_9_stair_a_top": [Vector3(12.0, 5.0, 3.6), Vector3(5.0, 3.6, 1.0)],
	"small_10_upper_b_opening": [Vector3(12.0, 5.0, -5.5), Vector3(12.0, 4.0, 1.0)],
}

const BENCH_FRAMES := 150

var _night: Night
var _camera: Camera3D
var _out := "user://room_lights"
var _map := "lot"
var _flat_boxes := false
var _flat_lights := false
var _spot := false
var _bench := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		if arg.begins_with("--map="):
			_map = arg.trim_prefix("--map=")
		if arg == "--flat" or arg == "--flat-boxes":
			_flat_boxes = true
		if arg == "--flat" or arg == "--flat-lights":
			_flat_lights = true
		if arg == "--spot":
			_spot = true
		if arg == "--bench":
			_bench = true
	DirAccess.make_dir_recursive_absolute(_out)
	_night = Night.new()
	if _map == "small":
		_night.scene = load(SMALL) as PackedScene
	add_child(_night)
	await _night.start(Night.Mode.MANUAL)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.make_current()
	var rules := _night.server.rules
	for circuit_id: StringName in rules.tuning.fuel.circuit_drain:
		_night.state.apply_events(rules.apply(RulesAction.set_circuit(circuit_id, true)))
	for _i in 6:
		_night.tick()
	if _flat_boxes:
		for box: Node in _night.find_children("*", "CSGBox3D", true, false):
			(box as CSGBox3D).layers = 1
	if _flat_lights:
		for light: Node in _night.find_children("*", "Light3D", true, false):
			(light as Light3D).light_cull_mask = 0xFFFFFFFF
	if _spot:
		_lower_as_a_spot()
	if _bench:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var shots := SMALL_SHOTS if _map == "small" else LOT_SHOTS
	for shot: String in shots:
		_camera.look_at_from_position(shots[shot][0], shots[shot][1])
		for _i in 4:
			await get_tree().process_frame
		if _bench:
			print("bench ", shot, " median_ms=", await _median_frame_ms())
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot])
		print(
			"shot ",
			shot,
			" draw_calls=",
			RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
			),
			" objects=",
			RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
			),
			" primitives=",
			RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
			),
		)
	get_tree().quit()


## The experiment of the issue's second idea: the booth's lower ceiling lamp as a spot facing down,
## whose cone lights nothing above its own height (`--spot`).
func _lower_as_a_spot() -> void:
	var omni := _night.find_child("Lower", true, false) as OmniLight3D
	var spot := SpotLight3D.new()
	spot.light_color = omni.light_color
	spot.light_energy = omni.light_energy * 1.6
	spot.spot_range = omni.omni_range
	spot.spot_angle = 85.0
	spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	omni.get_parent().add_child(spot)
	spot.global_position = omni.global_position
	omni.visible = false


## The median time of a frame over `BENCH_FRAMES` frames, in milliseconds.
func _median_frame_ms() -> float:
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for _i in BENCH_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	times.sort()
	return times[times.size() / 2]
