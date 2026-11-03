extends SceneTree
## The lot drawn with and without `LotBatcher` from the same places, and how far the two pictures
## are apart
## (#728): "the look unchanged". Run in a window (`gds godot --`), it writes
## `<out>/view_N_plain.png`,
## `view_N_batched.png` and `view_N_diff.png` (the difference, times 8) and prints each view's mean
## and
## largest difference and the share of pixels that differ by more than 4 of 255.
##
## gds godot -- --path game -s res://tools/lot/batch_capture.gd -- --out=<folder> [--small=0]

const GREYBOX := preload("res://world/drive_in_greybox.tscn")
const SIZE := Vector2i(1280, 720)
## Eye height of a standing player, and of a camera over the shoulder.
const EYE := 1.7
const OVERHEAD := 22.0
## [where the camera stands, where it looks], metres.
const VIEWS: Array[Array] = [
	[Vector3(0, EYE, -6), Vector3(0, 1.5, -40)],
	[Vector3(-30, EYE, -10), Vector3(-30, 1.5, -45)],
	[Vector3(25, EYE, -8), Vector3(40, 1.5, 10)],
	[Vector3(0, EYE, 6), Vector3(0, 1.5, 30)],
	[Vector3(-40, EYE, 20), Vector3(-20, 1.5, 20)],
	[Vector3(30, EYE, 30), Vector3(30, 1.5, 5)],
	[Vector3(0, EYE, 50), Vector3(0, 1.5, 20)],
	[Vector3(0, OVERHEAD, -4), Vector3(0, 0, -30)],
	[Vector3(-40, OVERHEAD, 20), Vector3(-30, 0, 10)],
	[Vector3(35, OVERHEAD, 20), Vector3(35, 0, 15)],
	# The machines, from the front.
	[Vector3(-10.5, EYE, 11), Vector3(-15.2, 1.6, 11)],
	[Vector3(24, EYE, 32), Vector3(24, 1.6, 37.2)],
	[Vector3(3.5, EYE, 23), Vector3(3.5, 1.6, 28.2)],
	[Vector3(8.2, EYE, 0), Vector3(8.2, 1.5, 4.9)],
]

var _out := ""
var _small := 0.0
var _cell := MeshBatch.DEFAULT_CELL
var _circuits: Array = []
var _calls: Array[int] = []
var _survey_views: Array[int] = [0, 4]
var _primitives: Array[int] = []


func _init() -> void:
	var args := NetArgs.new()
	_out = args.get_string("out", "user://batch")
	_small = args.get_float("small", 0.0)
	for id in args.get_string("circuits").split(",", false):
		_circuits.append(StringName(id))
	_cell = args.get_float("cell", MeshBatch.DEFAULT_CELL)
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = SIZE
	var plain := await _shoot(false)
	if args.has("repeat"):
		var again := await _shoot(false)
		for i in VIEWS.size():
			print("repeat view %d: %s" % [i, _difference(plain[i], again[i])])
	var batched := await _shoot(true)
	for i in VIEWS.size():
		_compare(i, plain[i], batched[i])
	quit()


func _shoot(batch: bool) -> Array[Image]:
	_calls = []
	_primitives = []
	var port := SubViewport.new()
	port.size = SIZE
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(port)
	var lot := GREYBOX.instantiate()
	port.add_child(lot)
	for _i in 6:
		await physics_frame
	# A night batches the map as the scene is written, every lamp lit, and only then switches the
	# circuits.
	if batch:
		print("batched: ", LotBatcher.batch(lot, _cell, _small))
	_power(lot)
	var camera := Camera3D.new()
	camera.fov = 70.0
	camera.far = 400.0
	# The project interpolates physics: a camera that jumps would slide to each place over the next
	# ticks.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	port.add_child(camera)
	camera.current = true
	var images: Array[Image] = []
	for view in VIEWS:
		camera.global_position = view[0]
		camera.look_at(view[1])
		for _i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		images.append(port.get_texture().get_image())
		var drawn := int(
			port.get_render_info(
				Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME
			)
		)
		var shapes := int(
			port.get_render_info(
				Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME
			)
		)
		if _survey_views.has(_calls.size()):
			print("view %d, in the frustum: %s" % [_calls.size(), _survey(camera, lot)])
		_calls.append(drawn)
		_primitives.append(shapes)
	print(
		(
			"%s: draw calls per view %s, triangles %s"
			% ["batched" if batch else "plain", _calls, _primitives]
		)
	)
	port.queue_free()
	await process_frame
	await process_frame
	return images


## The lot as a night opens it: the circuits the rules start with are on, the rest are dark (with
## every lamp on, the lot has more lights than the renderer draws at once, and which it drops
## follows the order of the meshes).
func _power(lot: Node3D) -> void:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH)
	var lamps := LotLamps.new(lot)
	lamps.configure(tuning.fuel)
	lamps.refresh(0)
	var on: Array = _circuits if _circuits != [] else tuning.fuel.start_circuits
	for circuit_id: StringName in tuning.fuel.circuit_drain:
		lamps.apply_event(
			{"type": &"circuit_changed", "circuit_id": circuit_id, "on": on.has(circuit_id)}
		)
	for follower: LightFollower in lot.find_children("*", "LightFollower", true, false):
		follower.advance(0.0)


## The surfaces whose box is in the camera's frustum, by the scene they belong to (a rough count of
## what is asked).
func _survey(camera: Camera3D, lot: Node3D) -> Dictionary:
	var planes := camera.get_frustum()
	var found := {}
	for node in lot.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if not geometry.is_visible_in_tree():
			continue
		var box := geometry.global_transform * geometry.get_aabb()
		var inside := true
		for plane in planes:
			var corner := Vector3(
				box.end.x if plane.normal.x > 0 else box.position.x,
				box.end.y if plane.normal.y > 0 else box.position.y,
				box.end.z if plane.normal.z > 0 else box.position.z
			)
			if plane.distance_to(corner) > 0:
				inside = false
				break
		if not inside:
			continue
		var surfaces := 1
		if geometry is MeshInstance3D and (geometry as MeshInstance3D).mesh != null:
			surfaces = (geometry as MeshInstance3D).mesh.get_surface_count()
		var key := _scene_of(geometry, lot)
		if geometry.get_parent() != null and geometry.get_parent().name == LotBatcher.BATCH_NODE:
			key = "(batch)"
		elif geometry is CSGShape3D and geometry.get_parent() is CSGShape3D:
			continue
		found[key] = int(found.get(key, 0)) + surfaces
	return found


func _scene_of(node: Node, lot: Node) -> String:
	var at := node
	while at != null and at != lot:
		if at.scene_file_path.get_extension() == "tscn":
			return at.scene_file_path.get_file().get_basename()
		at = at.get_parent()
	return "(lot)" + (" csg" if node is CSGShape3D else "")


func _compare(index: int, a: Image, b: Image) -> void:
	a.save_png("%s/view_%d_plain.png" % [_out, index])
	b.save_png("%s/view_%d_batched.png" % [_out, index])
	print("view %d: %s" % [index, _difference(a, b)])
	var diff := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
	for y in a.get_height():
		for x in a.get_width():
			var d := _pixel_difference(a.get_pixel(x, y), b.get_pixel(x, y))
			diff.set_pixel(x, y, Color(minf(d * 8.0, 1.0), minf(d * 8.0, 1.0), minf(d * 8.0, 1.0)))
	diff.save_png("%s/view_%d_diff.png" % [_out, index])


func _pixel_difference(ca: Color, cb: Color) -> float:
	return maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))


## The mean and largest difference of two images and the share of pixels that differ by more than
## 4/255.
func _difference(a: Image, b: Image) -> String:
	var total := 0.0
	var worst := 0.0
	var differing := 0
	for y in a.get_height():
		for x in a.get_width():
			var d := _pixel_difference(a.get_pixel(x, y), b.get_pixel(x, y))
			total += d
			worst = maxf(worst, d)
			if d > 4.0 / 255.0:
				differing += 1
	var pixels := float(a.get_width() * a.get_height())
	return (
		"mean %.5f, largest %.3f, differing: %.3f%%"
		% [total / pixels, worst, 100.0 * differing / pixels]
	)
