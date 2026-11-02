extends Node3D
## Capture for #36: a lit 3D scene drawn at each resolution scale the setting offers, through the
## real `Settings` service, in the Compatibility renderer. One PNG per scale at the window's real
## pixels, plus how far each differs from the full-size picture and the size the 3D view is drawn
## at. Run it through the no-focus launcher, not headless:
## `godot --path game res://tests/captures/resolution_scale.tscn --windowed --resolution 1280x720 --
## --out=<folder> [--scales=100,75,50] [--settle=6] [--mode=fsr]`. Input is never sent and the
## mouse is never captured.

const FILE := "user://resolution_scale_capture.cfg"
const SCALES := [100, 75, 50]
const SETTLE_FRAMES := 6
const CHECKER_CELLS := 64
## A lower scale must move at least this share of the picture (mean absolute difference, 0 to 1).
const MIN_DIFFERENCE := 0.01

var _out := "user://resolution_scale"
var _mode := Viewport.SCALING_3D_MODE_BILINEAR
var _scales: Array = SCALES
var _settle := SETTLE_FRAMES


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--scales="):
			_scales = Array(arg.get_slice("=", 1).split(",")).map(
				func(text: String) -> int: return int(text)
			)
		elif arg.begins_with("--settle="):
			_settle = int(arg.get_slice("=", 1))
		elif arg == "--mode=fsr":
			_mode = Viewport.SCALING_3D_MODE_FSR
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = FILE
	Settings.reset_defaults()
	get_tree().root.scaling_3d_mode = _mode
	_build_scene()
	var base: Image
	var sharpest := -1.0
	var failures: Array[String] = []
	for scale_percent: int in _scales:
		Settings.set_value(SettingsService.RESOLUTION_SCALE, scale_percent)
		for _i in _settle:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s/scale_%03d.png" % [_out, scale_percent])
		if base == null:
			base = image
		var difference := _difference(base, image)
		var sharpness := _sharpness(image)
		print(
			(
				"[resolution-scale] %d%% scale=%.2f mode=%d view=%s diff=%.4f sharpness=%.4f"
				% [
					scale_percent,
					get_tree().root.scaling_3d_scale,
					get_tree().root.scaling_3d_mode,
					image.get_size(),
					difference,
					sharpness
				]
			)
		)
		if sharpest < 0.0:
			sharpest = sharpness
		elif difference < MIN_DIFFERENCE or sharpness >= sharpest:
			failures.append(
				(
					"%d%%: the picture did not change (diff %.4f, sharpness %.4f)"
					% [scale_percent, difference, sharpness]
				)
			)
		else:
			sharpest = sharpness
	Settings.reset_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	for failure in failures:
		push_error("[resolution-scale] FAIL " + failure)
	print("[resolution-scale] %s" % ("FAIL" if failures else "PASS"))
	get_tree().quit(1 if failures else 0)


## The mean absolute difference between two pictures, 0 to 1.
func _difference(a: Image, b: Image) -> float:
	if a.get_size() != b.get_size():
		return -1.0
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			total += (absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)) / 3.0
			count += 1
	return total / float(maxi(count, 1))


## How much the picture changes from one pixel to the next along a row of the floor, 0 to 1: a
## picture drawn at a lower resolution and stretched back has less of it.
func _sharpness(image: Image) -> float:
	var total := 0.0
	var count := 0
	var top := int(image.get_height() * 0.7)
	for y in range(top, image.get_height(), 2):
		for x in range(1, image.get_width()):
			total += absf(
				image.get_pixel(x, y).get_luminance() - image.get_pixel(x - 1, y).get_luminance()
			)
			count += 1
	return total / float(maxi(count, 1))


func _build_scene() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.2, 5.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.6, 0.0))
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_mesh.mesh = plane
	floor_mesh.material_override = _checker()
	add_child(floor_mesh)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.position = Vector3(-1.2, 0.5, 0.0)
	box.rotation_degrees = Vector3(0.0, 25.0, 0.0)
	box.material_override = _paint(Color(0.9, 0.3, 0.2))
	add_child(box)
	var ball := MeshInstance3D.new()
	ball.mesh = SphereMesh.new()
	ball.position = Vector3(1.2, 0.5, 0.0)
	ball.material_override = _paint(Color(0.3, 0.6, 0.9))
	add_child(ball)


func _paint(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	return material


## A fine black and white checker: the detail a lower resolution scale visibly softens.
func _checker() -> StandardMaterial3D:
	var image := Image.create(CHECKER_CELLS * 2, CHECKER_CELLS * 2, false, Image.FORMAT_RGB8)
	for y in image.get_height():
		for x in image.get_width():
			var light := ((x / 2) + (y / 2)) % 2 == 0
			image.set_pixel(x, y, Color.WHITE if light else Color(0.1, 0.1, 0.1))
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.uv1_scale = Vector3(6.0, 6.0, 1.0)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material
