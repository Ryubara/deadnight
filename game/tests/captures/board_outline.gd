extends Node
## The ghost of a missing board (`BoardOutline`) from the player's shoulder camera, on both maps,
## and what it costs. Not part of the game. Run it windowed through the quiet launcher:
##
##   gds godot -- --path game res://tests/captures/board_outline.tscn --resolution 1600x900 --
##     --map=small|lot --out=<folder> [--ids=start_1,start_2] [--boards=0] [--without] [--all]
##
## For each id, the entry is torn to `--boards` (default 0) with the others whole, the camera is
## where a player repairing it stands (`--stand` m inside, default 3), and a PNG is written.
## `--without` hides the outlines (the look before them: the moon shafts and the board models
## only). `--all` also tears every other entry and prints the draws of the whole map torn. Each
## shot prints a `SHOT` line: draw calls and primitives of the frame, and the screen area the
## outlines cover (pixels, and a share of the frame), counted from the projected quads.

const STAND_DEFAULT := 3.0
const PITCH := -0.12
const SETTLE := 6
const WEB_QUERY := "location.search.replace(/^\\?/, '')"
const SCENES := {
	"small": "res://world/smallmap/smallmap_greybox.tscn",
	"lot": "res://world/drive_in_greybox.tscn",
}

var _args := {}
var _night: Night
var _camera: Camera3D


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	if OS.has_feature("web"):  # the page's query: `?map=small&ids=start_2&boards=0&without`
		arguments = PackedStringArray(str(JavaScriptBridge.eval(WEB_QUERY, true)).split("&", false))
	for argument in arguments:
		var parts := argument.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	var out := String(_args.get("out", "user://board_outline"))
	DirAccess.make_dir_recursive_absolute(out)
	_night = Night.new()
	_night.scene = load(SCENES[String(_args.get("map", "small"))]) as PackedScene
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7)
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = PlayerTuning.new().fov
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(_camera)
	_camera.make_current()
	for _i in 4:
		await get_tree().physics_frame
	var ids: Array[StringName] = []
	if _args.has("ids"):
		for id in String(_args["ids"]).split(","):
			ids.append(StringName(id))
	else:
		ids.assign(_night.world.barricade_ids())
	var count := int(_args.get("boards", "0"))
	for id in ids:
		await _shot(out, id, count)
	if _args.has("all"):
		await _torn_map(out)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__done = true;")  # the page is read by the browser probe
		return
	get_tree().quit()


func _set_all(count: int) -> void:
	for id in _night.world.barricade_ids():
		_night.world.barricade(id).set_boards(count, false)


func _shot(out: String, id: StringName, count: int) -> void:
	_set_all(5)
	_night.world.barricade(id).set_boards(count, false)
	_look_at(id)
	await _settle()
	var name := (
		"%s_%s_%d_%s"
		% [_args.get("map", "small"), id, count, "without" if _args.has("without") else "with"]
	)
	_report("SHOT " + name)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _torn_map(out: String) -> void:
	_set_all(0)
	_look_at(_night.world.barricade_ids()[0])
	await _settle()
	_report("TORN_MAP")
	get_viewport().get_texture().get_image().save_png(
		"%s/%s_torn_map.png" % [out, _args.get("map", "small")]
	)


## The camera where a player mending `id` stands, looking at the boards.
func _look_at(id: StringName) -> void:
	var barricade := _night.world.barricade(id)
	var inward := barricade.inward()
	var stand := float(_args.get("stand", STAND_DEFAULT))
	var feet := barricade.standing_point(stand)
	feet.y = barricade.global_position.y
	var yaw := atan2(inward.x, inward.z)
	var rig := CameraProbe.rig(_camera.get_world_3d().direct_space_state, feet, yaw, 1.0, PITCH)
	_camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(PITCH, yaw, 0.0)), rig["camera"]
	)


func _settle() -> void:
	for _i in SETTLE:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for barricade_id in _night.world.barricade_ids():
		var outline := _night.world.barricade(barricade_id).outline()
		if _args.has("without"):
			outline.visible = false
	await RenderingServer.frame_post_draw


func _report(label: String) -> void:
	var viewport := get_viewport()
	var size := viewport.get_visible_rect().size
	var covered := 0.0
	var quads := 0
	for barricade_id in _night.world.barricade_ids():
		var outline := _night.world.barricade(barricade_id).outline()
		if not outline.visible or outline.mesh == null:
			continue
		var vertices := outline.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for quad in vertices.size() / 4:
			var corners: Array[Vector2] = []
			var seen := true
			for k in 4:
				var world := outline.global_transform * vertices[quad * 4 + k]
				if _camera.is_position_behind(world):
					seen = false
					break
				corners.append(_camera.unproject_position(world))
			if seen:
				quads += 1
				covered += _area(corners, size)
	print(
		(
			"%s draws=%d primitives=%d objects=%d outline_quads=%d outline_px=%d share=%.4f"
			% [
				label,
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
				),
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
				),
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
				),
				quads,
				covered,
				covered / (size.x * size.y)
			]
		)
	)


## A quad's area on the screen (shoelace); a part outside the frame is only roughly clamped.
func _area(corners: Array[Vector2], size: Vector2) -> float:
	var total := 0.0
	for k in 4:
		var a := corners[k].clamp(Vector2.ZERO, size)
		var b := corners[(k + 1) % 4].clamp(Vector2.ZERO, size)
		total += a.x * b.y - b.x * a.y
	return absf(total) * 0.5
