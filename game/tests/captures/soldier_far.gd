extends Node3D
## Capture of the modular Soldier's far level of detail (#139): the eight presets in a row on a
## night lot, the camera pulling back from 12 m to 26 m, so the swap to the far meshes at
## `SoldierLook.FAR_FROM` (18 m) happens in shot. `-- near` keeps the near meshes all the way (the
## far ones hidden) for a frame-by-frame comparison. Prints DIST <metres> <frame> each metre.
##
##     godot --path game --write-movie <abs>/far.png --fixed-fps 10 --quit-after 75 \
##         res://tests/captures/soldier_far.tscn [-- near]

const FROM := 12.0
const TO := 26.0
const SECONDS := 7.0

var _camera: Camera3D
var _t := 0.0
var _last := -1


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.8)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 60)
	ground.mesh = plane
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.22, 0.23, 0.26)
	ground.material_override = paint
	add_child(ground)
	var near_only := OS.get_cmdline_user_args().has("near")
	var presets := SoldierLook.presets()
	for i in presets.size():
		var model := SoldierLook.instantiate()
		add_child(model)
		SoldierLook.apply(model, presets[i])
		model.scale = Vector3.ONE * 0.8
		model.position = Vector3((i - (presets.size() - 1) / 2.0) * 1.1, 0.0, 0.0)
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		player.get_animation(&"Idle").loop_mode = Animation.LOOP_LINEAR
		player.play(&"Idle")
		if near_only:
			for mi: MeshInstance3D in SoldierLook.part_meshes(model).values():
				mi.visibility_range_end = 0.0
			for fi: MeshInstance3D in SoldierLook.far_meshes(model).values():
				fi.visible = false
	_camera = Camera3D.new()
	_camera.fov = 30.0
	add_child(_camera)
	_camera.make_current()
	_place()


func _place() -> void:
	var distance := lerpf(FROM, TO, clampf(_t / SECONDS, 0.0, 1.0))
	_camera.position = Vector3(0.0, 1.6, distance)
	_camera.look_at(Vector3(0.0, 0.85, 0.0))
	if int(distance) != _last:
		_last = int(distance)
		print("DIST %d %d" % [_last, Engine.get_frames_drawn()])


func _process(delta: float) -> void:
	_t += delta
	_place()
