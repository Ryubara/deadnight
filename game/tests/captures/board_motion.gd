extends Node3D
## One breach's boards up close, for captures of how they move (docs/design/map.md, Breaches): the
## top board torn off and two more in quick succession, seen from outside; one torn seen from
## inside; then three mended one after the other.
## Not part of the game. Run with Movie Maker at a fixed rate, so the motions play frame by frame:
## `godot --path game res://tests/captures/board_motion.tscn --fixed-fps 30 --write-movie out.png`.
## Each stage prints its name and the movie frame it began on.

const BOARD_SCENE := "res://world/drive_in/board.tscn"
## Outside, where the dead stand (the boards fly toward the camera), then inside, where a player
## mends them.
const APRON_FROM := Vector3(2.6, 2.2, -5.4)
const FIELD_FROM := Vector3(-3.2, 2.4, 5.2)
const VIEW_AT := Vector3(0.0, 1.0, -0.4)

var _camera: Camera3D

var _barricade: Barricade


func _ready() -> void:
	_scenery()
	_barricade = Barricade.new()
	_barricade.set_meta(&"barricade_id", "nw")
	for i in 5:  # as tools/world/build_greybox.py builds a breach
		var board := (load(BOARD_SCENE) as PackedScene).instantiate() as Node3D
		board.position = Vector3(0.0, 0.3 + i * 0.6, 0.03 * (-1 if i % 2 else 1))
		_barricade.add_child(board)
	add_child(_barricade)
	_camera.look_at_from_position(APRON_FROM, VIEW_AT)
	await _hold(10)
	_stage("tear_top")
	_barricade.set_boards(4)
	await _hold(30)
	_stage("tear_two")
	_barricade.set_boards(3)
	await _hold(8)
	_barricade.set_boards(2)
	await _hold(30)
	_stage("from_the_field")
	_camera.look_at_from_position(FIELD_FROM, VIEW_AT)
	_barricade.set_boards(4, false)
	_barricade.set_boards(3)
	await _hold(30)
	_barricade.set_boards(2, false)
	await _hold(5)
	_stage("mend_three")
	for count in [3, 4, 5]:
		_barricade.set_boards(count)
		await _hold(15)
	await _hold(15)
	get_tree().quit()


func _scenery() -> void:
	_camera = Camera3D.new()
	_camera.fov = 60.0
	add_child(_camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.18, 0.22)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	ground.mesh = plane
	add_child(ground)
	for side in [-1.0, 1.0]:  # the fence on each side of the gap
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3.0, 3.0, 0.2)
		post.mesh = box
		post.position = Vector3(side * 3.6, 1.5, 0.0)
		add_child(post)


func _stage(stage: String) -> void:
	print("%s at frame %d" % [stage, Engine.get_frames_drawn()])


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
