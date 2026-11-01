extends Node
## A top-down picture of the reconciliation replay (not a test), for Movie Maker captures:
##
##   godot --path game --write-movie <dir>/reconcile.png --fixed-fps 10 \
##     res://tests/player/capture_reconcile.tscn
##
## The player is dropped above the ramp and plays 150 commands one per physics tick (large green
## dots). Then, in an idle frame (where a network handler runs), the state is rewound and the same
## 150 commands are simulated in one go (small red dots, drawn on top). When the replay is right the
## red dots sit in the middle of the green ones; before the fix in `PlayerSimulation._slide` they
## ran off. Printed as `RECONCILE error=<metres>`.

const OVERHEAD_HEIGHT := 30.0
const COMMANDS := 150
const HOLD_FRAMES := 12

var _player: Player
var _trail_root: Node3D
var _recorded: Array[PackedByteArray] = []
var _start: PlayerMotionState
var _first_end: PlayerMotionState
var _ticks := 0
var _hold := -1
var _label: Label


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_player.get_node("AnimationTree").set_process(false)
	_build_overhead()
	_player.teleport(Vector3(6.0, 3.0, -5.0))
	_start = _player.state.duplicate_state()


func _build_overhead() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(camera)
	camera.global_transform = Transform3D(
		Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(6.5, OVERHEAD_HEIGHT, -9.0)
	)
	camera.current = true
	_trail_root = Node3D.new()
	add_child(_trail_root)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24.0, 20.0)
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	_label.text = "playing 150 commands, one per physics tick (green)"
	layer.add_child(_label)


func _physics_process(_delta: float) -> void:
	if _ticks < COMMANDS:
		var command := _command(_ticks)
		_recorded.append(command.to_bytes())
		_player.submit_command(command)
		_ticks += 1
		if _ticks % 3 == 0:
			_dot(_player.state.position, Color(0.2, 0.9, 0.3), 0.3, 0.0)
	elif _ticks == COMMANDS:
		_first_end = _player.state.duplicate_state()
		_ticks += 1
		# Scheduled for the idle frame that follows this physics frame.
		get_tree().process_frame.connect(_replay_in_an_idle_frame, CONNECT_ONE_SHOT)


func _command(i: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = Vector2(0.0, -1.0) if i < 100 else Vector2(1.0, 0.0)
	command.yaw = 0.004 * i
	command.sprint = i > 30 and i < 80
	command.jump = i == 60 or i == 110
	command.aim = i > 120
	command.fire = i > 40 and i < 90
	return command


func _replay_in_an_idle_frame() -> void:
	_player.state.copy_from(_start)
	_player.global_position = _start.position
	_player.velocity = _start.velocity
	var i := 0
	for bytes in _recorded:
		PlayerSimulation.simulate(
			_player,
			_player.state,
			PlayerCommand.from_bytes(bytes),
			_player.tuning,
			get_physics_process_delta_time()
		)
		i += 1
		if i % 3 == 0:
			_dot(_player.state.position, Color(1.0, 0.15, 0.15), 0.15, 1.0)
	var error := _player.state.position.distance_to(_first_end.position)
	print("RECONCILE error=%.4f" % error)
	_label.text = (
		"the same 150 commands replayed in one idle-frame call (red): end error %.3f m" % error
	)
	_hold = HOLD_FRAMES


func _process(_delta: float) -> void:
	if _hold > 0:
		_hold -= 1
	elif _hold == 0:
		get_tree().quit()


func _dot(position: Vector3, color: Color, radius: float, lift: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dot := MeshInstance3D.new()
	dot.mesh = mesh
	dot.material_override = material
	_trail_root.add_child(dot)
	dot.global_position = position + Vector3(0.0, 4.0 + radius + lift, 0.0)
