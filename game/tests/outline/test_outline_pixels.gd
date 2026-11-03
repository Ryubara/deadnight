extends GdUnitTestSuite
## The outline is drawn on the hidden parts of a body only, as a line with no glow: the three cases
## of issue #617 rendered and read back pixel by pixel. A box stands in front of a backdrop, an
## occluder stands between it and the camera, and the pixels the outline's colour touches are
## counted above and below the occluder's edge and measured against the box's silhouette.
## Needs a real renderer (the tests of a headless run skip): `gds godot -- --path game -s
## res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/outline/test_outline_pixels.gd -c
## --ignoreHeadlessMode`. Set `OUTLINE_SHOTS` to a folder to keep the three pictures.

const SIZE := Vector2i(960, 540)
const FOV := 50.0
## The body: a box this wide and tall, its middle at `BODY_AT`; the occluder in front of it.
const BODY_SIZE := Vector3(0.8, 1.8, 0.4)
const BODY_AT := Vector3(0.0, 0.9, -7.0)
const OCCLUDER_Z := -3.5
const OCCLUDER_DEPTH := 0.2
const CAMERA_AT := Vector3(0.0, 0.9, 0.0)
## The line, in pixels of this picture: the style's thickness is in pixels of a 1080-high screen.
const LINE_PX := 3.0
const BACKDROP := Color(0.45, 0.45, 0.45)
const BODY_COLOR := Color(0.2, 0.6, 0.25)
const OCCLUDER_COLOR := Color(0.2, 0.3, 0.8)
## A pixel is tinted by the line when its red leads the other two this much: the backdrop, the body
## and the occluder are grey, green and blue, so only the line (or a halo of it) is reddish.
const TINT := 0.03

const SKIP_HEADLESS := 'DisplayServer.get_name() == "headless"'
const SKIP_WHY := "reads pixels: needs a renderer, not the headless dummy"

var _style: OutlineStyle


func before_test() -> void:
	_style = OutlineStyle.new()
	_style.thickness = LINE_PX * 1080.0 / SIZE.y


## The picture of the scene with an occluder from `bottom` to `top` (heights, metres; equal means
## none) in front of the body, and the camera that took it.
func _shoot(bottom: float, top: float, name: String) -> Dictionary:
	var port := SubViewport.new()
	port.size = SIZE
	port.own_world_3d = true
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(auto_free(port))
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	var world := WorldEnvironment.new()
	world.environment = environment
	port.add_child(world)
	var camera := Camera3D.new()
	camera.fov = FOV
	camera.position = CAMERA_AT
	port.add_child(camera)
	var backdrop := _box(Vector3(60.0, 30.0, 0.1), Vector3(0.0, 0.0, -14.0), BACKDROP)
	port.add_child(backdrop)
	var body := _box(BODY_SIZE, BODY_AT, BODY_COLOR)
	port.add_child(body)
	var outline := Outline.new()
	outline.style = _style
	body.add_child(outline)
	outline.enabled = true
	if top > bottom:
		var size := Vector3(6.0, top - bottom, OCCLUDER_DEPTH)
		port.add_child(_box(size, Vector3(0.0, 0.5 * (top + bottom), OCCLUDER_Z), OCCLUDER_COLOR))
	# A suite run from the command line can leave the window minimized, and a minimized window draws
	# nothing by itself: draw the frames by hand (the first builds the shaders, the second shows them).
	await get_tree().process_frame
	for i in 3:
		RenderingServer.force_draw(false)
	var image := port.get_texture().get_image()
	var folder := OS.get_environment("OUTLINE_SHOTS")
	if not folder.is_empty():
		image.save_png("%s/%s.png" % [folder, name])
	return {"image": image, "camera": camera}


func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material_override = material
	return mesh


## The body's silhouette on the screen: its front face's rectangle (it faces the camera square on).
func _silhouette(camera: Camera3D) -> Rect2:
	var front := BODY_AT.z + 0.5 * BODY_SIZE.z
	var low := camera.unproject_position(Vector3(-0.5 * BODY_SIZE.x, 0.0, front))
	var high := camera.unproject_position(Vector3(0.5 * BODY_SIZE.x, BODY_SIZE.y, front))
	return Rect2(low.x, high.y, high.x - low.x, low.y - high.y)


func _tinted(image: Image, area: Rect2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var color := image.get_pixel(x, y)
			if color.r - maxf(color.g, color.b) > TINT:
				found.append(Vector2i(x, y))
	return found


## The region of the picture around the body, wide enough for any halo to show.
func _around(silhouette: Rect2) -> Rect2i:
	return Rect2i(silhouette.grow(40.0)).intersection(Rect2i(Vector2i.ZERO, SIZE))


func _distance_to(rect: Rect2, point: Vector2i) -> float:
	var dx := maxf(maxf(rect.position.x - point.x, 0.0), point.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - point.y, 0.0), point.y - rect.end.y)
	return Vector2(dx, dy).length()


func _reach() -> float:
	return LINE_PX / cos(PI / OutlineStyle.DIRECTIONS)


func _assert_a_line_with_no_aura(found: Array[Vector2i], silhouette: Rect2) -> void:
	var farthest := 0.0
	for point in found:
		farthest = maxf(farthest, _distance_to(silhouette, point))
	# One pixel for the pixel centre and the edge's rounding; a halo reaches 3.5 times further.
	assert_float(farthest).is_less(_reach() + 1.0)


func test_a_body_in_the_open_has_no_outline_and_no_glow(
	_do_skip := DisplayServer.get_name() == "headless", _skip_reason := SKIP_WHY
) -> void:
	var shot := await _shoot(0.0, 0.0, "open")
	var silhouette := _silhouette(shot["camera"])
	assert_int(_tinted(shot["image"], _around(silhouette)).size()).is_equal(0)


func test_a_body_half_behind_a_counter_is_outlined_below_its_edge_only(
	_do_skip := DisplayServer.get_name() == "headless", _skip_reason := SKIP_WHY
) -> void:
	# The occluder covers the body's lower half and more: its top edge is at the body's middle.
	var shot := await _shoot(-1.0, 0.9, "half")
	var camera: Camera3D = shot["camera"]
	var edge := camera.unproject_position(Vector3(0.0, 0.9, OCCLUDER_Z + 0.5 * OCCLUDER_DEPTH)).y
	var silhouette := _silhouette(camera)
	var found := _tinted(shot["image"], _around(silhouette))
	var above := 0
	var below := 0
	for point in found:
		if point.y < floorf(edge):
			above += 1
		elif point.y > ceilf(edge):
			below += 1
	assert_int(above).is_equal(0)
	# Both sides of the hidden half and its feet carry the line.
	assert_int(below).is_greater(int(2.0 * (silhouette.end.y - edge)))
	_assert_a_line_with_no_aura(found, silhouette)


func test_a_body_behind_a_wall_is_outlined_all_round(
	_do_skip := DisplayServer.get_name() == "headless", _skip_reason := SKIP_WHY
) -> void:
	var shot := await _shoot(-1.0, 2.5, "wall")
	var silhouette := _silhouette(shot["camera"])
	var found := _tinted(shot["image"], _around(silhouette))
	_assert_a_line_with_no_aura(found, silhouette)
	var has_top := false
	var has_bottom := false
	var has_left := false
	var has_right := false
	for point in found:
		has_top = has_top or point.y < silhouette.position.y
		has_bottom = has_bottom or point.y > silhouette.end.y
		has_left = has_left or point.x < silhouette.position.x
		has_right = has_right or point.x > silhouette.end.x
	assert_bool(has_top and has_bottom and has_left and has_right).is_true()
	# The inside of the body is not filled (a pixel of margin for the edge's rounding).
	var inside := 0
	for point in found:
		if silhouette.grow(-1.0).has_point(Vector2(point)):
			inside += 1
	assert_int(inside).is_equal(0)
