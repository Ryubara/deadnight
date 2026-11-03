extends Node3D
## Capture of a zombie's hit zones drawn over its body, from the side, from above and from the
## front, at several moments of one clip. Not part of the game. Arguments after `--`: `--look=NAME`
## (default crawler), `--clip=NAME` (default Crawl), `--set=ID` (the hit set, default the look's
## moving one), `--frames-per-state=N` (default 3).
## The shapes are `Hitbox`'s as the night's server places them for that look.

const VIEWS: Array[String] = ["side", "above", "front"]
const TIMES := 4
const ZONE_COLOURS := {
	&"head": Color(1.0, 0.15, 0.15, 0.45),
	&"body": Color(1.0, 0.6, 0.1, 0.45),
	&"limb": Color(0.95, 0.9, 0.2, 0.45),
	&"weak": Color(0.2, 0.9, 1.0, 0.45),
}

var _look: StringName = &"crawler"
var _clip: StringName = &"Crawl"
var _set: StringName = &""
var _hold := 3
var _frame := 0
var _model: Node3D
var _player: AnimationPlayer
var _shape_root: Node3D
var _camera: Camera3D
var _label: Label


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--look="):
			_look = StringName(arg.get_slice("=", 1))
		elif arg.begins_with("--clip="):
			_clip = StringName(arg.get_slice("=", 1))
		elif arg.begins_with("--set="):
			_set = StringName(arg.get_slice("=", 1))
		elif arg.begins_with("--frames-per-state="):
			_hold = int(arg.get_slice("=", 1))
	if _set == &"":
		_set = ZombiePose.hit_set(_look)
	_model = ZombieModels.scene(_look).instantiate() as Node3D
	_model.scale = Vector3.ONE * ZombieModels.GAME_SCALE
	add_child(_model)
	_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_shape_root = Node3D.new()
	add_child(_shape_root)
	_make_stage()


func _make_stage() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.22, 0.24, 0.27)
	floor_mesh.material_override = floor_material
	floor_mesh.position.y = -0.01
	add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.09, 0.12)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	add_child(environment)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	add_child(_camera)
	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(_label)
	add_child(layer)


func _process(_delta: float) -> void:
	var state := _frame / _hold
	var view := VIEWS[state % VIEWS.size()]
	var step := (state / VIEWS.size()) % TIMES
	var length := _player.get_animation(_clip).length
	var time := length * float(step) / float(TIMES)
	_player.play(_clip)
	_player.seek(time, true)
	_draw_shapes()
	_point_camera(view)
	_label.text = "%s  %s  t=%.2fs  view: %s" % [_look, _clip, time, view]
	_frame += 1


func _draw_shapes() -> void:
	for child in _shape_root.get_children():
		child.free()
	var profile_scale := _hit_scale()
	for shape in _shapes(profile_scale):
		_shape_root.add_child(_zone_node(shape))


## The zones the night's server shoots at for this look, standing at the origin facing +Z.
func _shapes(profile_scale: float) -> Array[Dictionary]:
	return Hitbox.shapes(Vector3.ZERO, 0.0, profile_scale, ZombieModels.is_boss(_look), _set)


func _hit_scale() -> float:
	return ZombieModels.height_of(_look)


func _zone_node(shape: Dictionary) -> MeshInstance3D:
	var a: Vector3 = shape["a"]
	var b: Vector3 = shape["b"]
	var radius: float = shape["r"]
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = a.distance_to(b) + radius * 2.0
	capsule.radial_segments = 24
	capsule.rings = 8
	var node := MeshInstance3D.new()
	node.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = ZONE_COLOURS.get(shape["zone"], Color.WHITE)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material
	var along := b - a
	var up := along.normalized() if along.length() > 0.0001 else Vector3.UP
	# A capsule stands along Y: turn Y onto `up`.
	var axis := Vector3.UP.cross(up)
	var basis := Basis.IDENTITY
	if axis.length() > 0.0001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(up))
	elif up.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	node.transform = Transform3D(basis, (a + b) * 0.5)
	return node


func _point_camera(view: String) -> void:
	var focus := Vector3(0, 0.45, 0.25) if ZombieModels.crawls(_look) else Vector3(0, 0.9, 0.1)
	var distance := 3.6 if ZombieModels.crawls(_look) else 5.0
	match view:
		"side":
			_camera.position = focus + Vector3(distance, 0.25, 0)
		"above":
			_camera.position = focus + Vector3(0.001, distance, 0.001)
		_:
			_camera.position = focus + Vector3(0.9, 0.9, distance)
	_camera.look_at(focus, Vector3.UP if view != "above" else Vector3.FORWARD)
