extends Node
## Measures how smoothly the soldier is drawn from the side: strafes the player across the test
## room and, after every drawn frame, finds two marker balls (one on the body, one on the weapon
## mount) in the rendered image. Prints the frame-to-frame unevenness of their screen positions
## (`FrameJudder`) and writes every position to a CSV. Not a test: it needs a window and a renderer.
##
##     godot --path game res://tests/captures/side_on_smoothness.tscn --fixed-fps 144 \
##         --resolution 1280x720 -- --out=<abs>/track.csv
##
## `--fixed-fps` gives every frame the same delta, so 144 frames fall over 60 physics ticks the same
## way on any machine. `--seconds=N` shortens the run, `--markers=0` leaves the balls out (a clean
## look for a film), `--yaw=D` turns the view D degrees (the soldier moves across it at 0).
## `--zombie=1` measures a zombie's view walking across a still camera instead of the soldier.

const ROOM := "res://world/test_room.tscn"
const START := Vector3(-13.0, 0.05, 10.0)
const TICKS_PER_SECOND := 60.0
## Seconds standing, then strafing right.
const STAND_SECONDS := 0.5
const BODY_COLOUR := Color(1.0, 0.0, 1.0)
const HAND_COLOUR := Color(0.0, 1.0, 1.0)
## Search window around where a marker is expected, in pixels.
const WINDOW := 90
## Skip this many seconds after the strafe starts (the soldier is still speeding up).
const SETTLE_SECONDS := 0.8
const ZOMBIE_START := -9.0
const ZOMBIE_SPEED := 2.5

var _player: Player
var _ticks := 0
var _seconds := 3.2
var _out := ""
var _yaw := 0.0
var _markers := true
var _zombie: ZombieView
var _zombie_x := ZOMBIE_START
var _body_marker: MeshInstance3D
var _hand_marker: MeshInstance3D
var _frames: Array[Dictionary] = []


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--seconds="):
			_seconds = float(argument.trim_prefix("--seconds="))
		elif argument.begins_with("--yaw="):
			_yaw = deg_to_rad(float(argument.trim_prefix("--yaw=")))
		elif argument == "--markers=0":
			_markers = false
		elif argument == "--zombie=1":
			_zombie = ZombieView.new()
	var room: Node = load(ROOM).instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_player.teleport(START)
	_player.camera_rig.yaw = _yaw
	if _zombie != null:
		room.add_child(_zombie)
		_zombie.setup(ZombieModels.scene(), 1, 0.0, 0.7)
		_player.teleport(Vector3(0.0, 0.05, 12.0))
		_body_marker = _marker(_zombie, Vector3(0.0, 1.0, 0.0), 0.12, BODY_COLOUR)
		_hand_marker = _marker(_zombie, Vector3(0.0, 1.0, 0.0), 0.0001, HAND_COLOUR)
	elif _markers:
		_body_marker = _marker(_player.get_node("Model"), Vector3(0.0, 1.0, 0.0), 0.12, BODY_COLOUR)
		var mount := (_player.get_node("AnimationTree") as PlayerAnimation).weapon_mount()
		_hand_marker = _marker(mount, Vector3.ZERO, 0.07, HAND_COLOUR)
	_record()


func _physics_process(_delta: float) -> void:
	var command := PlayerCommand.new()
	command.yaw = _yaw
	if _ticks / TICKS_PER_SECOND >= STAND_SECONDS:
		command.move = Vector2(1.0, 0.0)
	if _zombie != null:
		command.move = Vector2.ZERO
		_zombie_x += ZOMBIE_SPEED / TICKS_PER_SECOND
		var entry := {
			"position": Vector3(_zombie_x, 0.05, 8.0),
			"yaw": -PI / 2.0,
			"mode": ZombieBody.Mode.CHASE,
			"tearing": false,
			"episode": 0,
			"speed": 1.0,
			"look": ZombieModels.DEFAULT,
		}
		_zombie.apply(entry, 1.0 / TICKS_PER_SECOND)
	_player.submit_command(command)
	_ticks += 1


## A ball that lights the same in any light, in `colour`, under `parent` at `offset`.
func _marker(parent: Node3D, offset: Vector3, radius: float, colour: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.no_depth_test = true
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = offset
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


## After each drawn frame: read the image and find the markers.
func _record() -> void:
	var camera := _player.camera_rig.camera()
	var viewport := get_viewport()
	while _ticks / TICKS_PER_SECOND < STAND_SECONDS + _seconds:
		await RenderingServer.frame_post_draw
		if not _markers:
			continue
		var image := viewport.get_texture().get_image()
		var row := {
			&"frame": Engine.get_frames_drawn(),
			&"tick": Engine.get_physics_frames(),
			&"fraction": Engine.get_physics_interpolation_fraction(),
			&"time": _ticks / TICKS_PER_SECOND,
		}
		row[&"body"] = _find(image, camera, _body_marker, BODY_COLOUR)
		row[&"hand"] = _find(image, camera, _hand_marker, HAND_COLOUR)
		_frames.append(row)
	_finish()


## The centre of the pixels in `colour` near where `node` should be, or Vector2(NAN, NAN).
func _find(image: Image, camera: Camera3D, node: Node3D, colour: Color) -> Vector2:
	var scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var expected := camera.unproject_position(node.global_position) * scale
	var low := Vector2i(expected) - Vector2i(WINDOW, WINDOW)
	var high := Vector2i(expected) + Vector2i(WINDOW, WINDOW)
	low = low.clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
	high = high.clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
	var total := Vector2.ZERO
	var count := 0
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var pixel := image.get_pixel(x, y)
			if (
				absf(pixel.r - colour.r) < 0.12
				and absf(pixel.g - colour.g) < 0.12
				and absf(pixel.b - colour.b) < 0.12
			):
				total += Vector2(x, y)
				count += 1
	if count < 4:
		return Vector2(NAN, NAN)
	return total / float(count)


func _finish() -> void:
	var from := 0
	for i in _frames.size():
		if _frames[i][&"time"] >= STAND_SECONDS + SETTLE_SECONDS:
			from = i
			break
	var lines := PackedStringArray(["frame,tick,fraction,body_x,body_y,hand_x,hand_y"])
	for row in _frames:
		(
			lines
			. append(
				(
					"%d,%d,%.4f,%.3f,%.3f,%.3f,%.3f"
					% [
						row[&"frame"],
						row[&"tick"],
						row[&"fraction"],
						row[&"body"].x,
						row[&"body"].y,
						row[&"hand"].x,
						row[&"hand"].y,
					]
				)
			)
		)
	if _out != "":
		var file := FileAccess.open(_out, FileAccess.WRITE)
		if file != null:
			file.store_string("\n".join(lines) + "\n")
	for key: StringName in [&"body", &"hand"]:
		var xs := PackedFloat64Array()
		for i in range(from, _frames.size()):
			var at: Vector2 = _frames[i][key]
			if not is_nan(at.x):
				xs.append(at.x)
		var summary := FrameJudder.summary(xs)
		print(
			(
				"JUDDER %s frames=%d move=%.3f px/frame, second difference peak=%.3f rms=%.3f px"
				% [key, xs.size(), summary[&"mean_move"], summary[&"peak"], summary[&"rms"]]
			)
		)
	get_tree().quit()
