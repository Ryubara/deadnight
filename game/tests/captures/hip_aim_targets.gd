extends Node
## The barrel at the hip, with the crosshair on a close and on a far target (Deadnight #285): the
## Soldier stands with the view along his body, a red ball sits on the crosshair's ray, and a yellow
## line runs from the muzzle along the barrel, seen from the shoulder camera and from above. Before
## the change the line ran parallel to the body; now it crosses the ray, at the point 12 m ahead of
## the camera. Not part of the game. Movie Maker, one view per SHOT_FRAMES; prints
## `SHOT <target> <view> <frame>` for the last frame of each view and `AIM <target> ...` with the
## numbers (degrees between the barrel and the body, and between the barrel and the crosshair's
## point):
##
##     gds godot -- --path game res://tests/captures/hip_aim_targets.tscn \
##         --write-movie <abs>/hip.png --fixed-fps 10 --resolution 960x540 --quit-after 70

const SHOT_FRAMES := 8
const TARGETS := {"close": 4.0, "far": 24.0}
const VIEWS := ["shoulder", "top"]
const WEAPON := &"rifle"
const LINE_LENGTH := 40.0
const BALL_RADIUS := 0.12
const FIRST_FRAME := 6

var _player: Player
var _animation: PlayerAnimation
var _top: Camera3D
var _ball: MeshInstance3D
var _line: MeshInstance3D
var _steps: Array = []
var _frame := 0


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_player.teleport(Vector3(0.0, 0.05, 6.0))
	_animation.equip(WEAPON)
	_top = Camera3D.new()
	_top.fov = 40.0
	add_child(_top)
	_ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	sphere.material = _unshaded(Color(0.9, 0.1, 0.1))
	_ball.mesh = sphere
	add_child(_ball)
	_line = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.02, LINE_LENGTH)
	box.material = _unshaded(Color(1.0, 0.85, 0.1))
	_line.mesh = box
	add_child(_line)
	for target in TARGETS:
		for view in VIEWS:
			_steps.append([target, view])
	print("FRAMES ", _steps.size() * SHOT_FRAMES + FIRST_FRAME + 4)


func _unshaded(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	return material


func _process(_delta: float) -> void:
	if _frame < FIRST_FRAME:
		_frame += 1
		return
	var index := (_frame - FIRST_FRAME) / SHOT_FRAMES
	var within := (_frame - FIRST_FRAME) % SHOT_FRAMES
	_frame += 1
	if index >= _steps.size():
		get_tree().quit()
		return
	var step: Array = _steps[index]
	var camera := _player.camera_rig.get_node("Camera3D") as Camera3D
	var ray := -camera.global_basis.z
	_ball.global_position = camera.global_position + ray * TARGETS[step[0]]
	var weapon := _animation.weapon()
	var muzzle := weapon.to_global(_animation.weapon_hold().muzzle)
	var barrel := (weapon.global_basis * Vector3.LEFT).normalized()
	_line.global_transform = Transform3D(
		Basis.looking_at(barrel, Vector3.UP), muzzle + barrel * LINE_LENGTH * 0.5
	)
	var centre := _player.global_position + Vector3(0.0, 1.2, 0.0)
	_top.global_position = centre + Vector3(0.0, 10.0, 2.5)
	_top.look_at(centre - _player.global_basis.z * 2.0, Vector3.FORWARD)
	if step[1] == "top":
		_top.make_current()
	else:
		camera.make_current()
	if within == SHOT_FRAMES - 1:
		print("SHOT %s %s %d" % [step[0], step[1], _frame - 1])
		if step[1] == "shoulder":
			var point := camera.global_position + ray * WeaponHandsIK.CONVERGE_DISTANCE
			print(
				(
					"AIM %s body=%.2f deg crosshair_point=%.2f deg"
					% [
						step[0],
						rad_to_deg(barrel.angle_to(-_player.global_basis.z)),
						rad_to_deg(barrel.angle_to((point - muzzle).normalized())),
					]
				)
			)
