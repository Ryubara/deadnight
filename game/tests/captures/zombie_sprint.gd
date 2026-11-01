extends Node3D
## Capture of the fastest dead's gait (#278), on a dark lot with ground marks every metre. Two
## shots, picked by the first user argument after `--`:
##
## - `side`: three runners in lanes, seen from the side, at the Run's own speed (4.4 m/s on a
##   walker's scale, times the runner's height), 5.4 m/s, and a round 20 runner in the dark (the
##   rules' speed); each label says the blend position and the rate the rig picked.
## - `shoulder`: the player's shoulder camera (PlayerTuning's pivot, offset, arm and field of
##   view) behind the Soldier, and three round 20 runners sprinting at him out of the dark.
##
## Run with Movie Maker, an absolute path:
##
##     godot --path game res://tests/captures/zombie_sprint.tscn --write-movie <abs>/side.png \
##         --fixed-fps 30 --quit-after 60 -- side

const SOLDIER := "res://assets/characters/soldier/soldier.glb"
const LOOK := &"runner"
## The runner's type multiplier on the round's pace (docs/design/zombies.md).
const RUNNER_PACE := 1.4

var _views: Array[ZombieView] = []
var _speeds: Array[float] = []
var _starts: Array[Vector3] = []
var _directions: Array[Vector3] = []
var _labels: Array[Label3D] = []
var _t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var shot: String = args[0] if not args.is_empty() else "side"
	_lot()
	if shot == "shoulder":
		_shoulder()
	else:
		_side()


func _lot() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.035, 0.05)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.6, 0.75)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.8, 0.85, 1.0)
	moon.light_energy = 0.8
	moon.rotation_degrees = Vector3(-45, -30, 0)
	add_child(moon)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.2, 0.21, 0.24)
	ground.material_override = paint
	add_child(ground)


func _mark(at: Vector3, size: Vector3, colour: Color) -> void:
	var mark := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mark.mesh = box
	mark.position = at
	var paint := StandardMaterial3D.new()
	paint.albedo_color = colour
	mark.material_override = paint
	add_child(mark)


func _round_20_dark() -> float:
	var tuning := RoundTuning.new()
	var speed := minf(tuning.speed_for_round(20) * RUNNER_PACE, tuning.speed_cap)
	return tuning.speed_on_ground(speed, false)


func _side() -> void:
	var scale := ZombieRig.clip_scale(LOOK)
	var dark := _round_20_dark()
	var lanes := [ZombieRig.RUN_AT * scale, 5.4, dark]
	for lane in lanes.size():
		var z := -3.6 * lane
		for i in range(-1, 14):
			var colour := Color(0.9, 0.85, 0.3) if i % 5 == 0 else Color(0.75, 0.75, 0.8)
			_mark(Vector3(float(i), 0.005, z), Vector3(0.05, 0.01, 1.6), colour)
		_add(lanes[lane], Vector3(0.0, 0.0, z), Vector3.RIGHT)
		var label := Label3D.new()
		label.font_size = 36
		label.pixel_size = 0.006
		label.position = Vector3(0.2, 0.05, z - 1.1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.no_depth_test = true
		add_child(label)
		_labels.append(label)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.position = Vector3(5.5, 9.0, 8.0)
	cam.look_at(Vector3(5.5, 0.3, -3.8))
	cam.make_current()


func _shoulder() -> void:
	var tuning := PlayerTuning.new()
	var soldier := (load(SOLDIER) as PackedScene).instantiate() as Node3D
	soldier.scale = Vector3.ONE * 0.8
	soldier.rotation.y = PI  # the model faces +Z; the player looks down -Z
	add_child(soldier)
	var idle := soldier.find_child("AnimationPlayer", true, false) as AnimationPlayer
	idle.play(&"Idle")
	var dark := _round_20_dark()
	for i in 3:
		var start := Vector3(1.2 + 1.5 * i, 0.0, -15.0 - 2.5 * i)
		_add(dark, start, Vector3.BACK)
	for i in range(0, 26, 2):
		_mark(Vector3(-4.0, 0.005, -float(i)), Vector3(0.6, 0.01, 0.06), Color(0.85, 0.82, 0.7))
		_mark(Vector3(4.0, 0.005, -float(i)), Vector3(0.6, 0.01, 0.06), Color(0.85, 0.82, 0.7))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 4.0, -8.0)
	lamp.omni_range = 16.0
	lamp.light_energy = 1.5
	lamp.light_color = Color(1.0, 0.85, 0.6)
	add_child(lamp)
	var cam := Camera3D.new()
	cam.fov = tuning.fov
	add_child(cam)
	cam.position = Vector3(tuning.shoulder_offset, tuning.pivot_height, tuning.arm_length)
	cam.look_at(Vector3(tuning.shoulder_offset, tuning.pivot_height - 0.35, -10.0))
	cam.make_current()


func _add(speed: float, start: Vector3, direction: Vector3) -> void:
	var view := ZombieView.new()
	add_child(view)
	view.setup(ZombieModels.scene(LOOK), _views.size() + 1, 0.0, 0.7, LOOK)
	view.accumulated = 0.0
	_views.append(view)
	_speeds.append(speed)
	_starts.append(start)
	_directions.append(direction)
	_apply(_views.size() - 1, 0.0)


func _apply(i: int, delta: float) -> void:
	var travelled := fposmod(_speeds[i] * _t, 12.0)
	var entry := {
		"id": i + 1,
		"position": _starts[i] + _directions[i] * travelled,
		"yaw": atan2(_directions[i].x, _directions[i].z),
		"mode": ZombieBody.Mode.CHASE,
		"episode": 1,
		"speed": _speeds[i],
	}
	_views[i].apply(entry, delta)


func _process(delta: float) -> void:
	_t += delta
	for i in _views.size():
		_apply(i, delta)
		_views[i].accumulated += delta
		_views[i].advance_animation()
		if i < _labels.size():
			var tree := _views[i].tree
			_labels[i].text = (
				"%.2f m/s  blend %.2f  rate %.2f"
				% [
					_speeds[i],
					tree.get(ZombieRig.BLEND_PARAMETER),
					tree.get(ZombieRig.MOVE_RATE_PARAMETER)
				]
			)


func _exit_tree() -> void:
	ZombieRig.release()
