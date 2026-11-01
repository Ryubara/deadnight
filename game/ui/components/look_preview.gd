class_name LookPreview
extends SubViewportContainer
## A lit turntable with the character on it, drawn in its own little 3D world so it can sit inside
## a menu. `show_look` rebuilds the model; the turntable turns by itself (not with reduced
## motion) and by hand: drag with the mouse, or push the right stick / the look keys.
##
## The nodes are built in code so a test or a capture can use the control without a scene.

## Radians per second of the idle turn.
const IDLE_SPEED := 0.5
## Radians per second at full right stick.
const STICK_SPEED := 3.2
## Radians per pixel of mouse drag.
const DRAG_SPEED := 0.011
const CAMERA_FOV := 26.0
const CAMERA_POSITION := Vector3(0.0, 1.35, 5.2)
const CAMERA_TARGET := Vector3(0.0, 0.95, 0.0)
const MODEL_SCALE := 0.8
const PLATE_RADIUS := 0.95
const PLATE_HEIGHT := 0.1
const RIM_RADIUS := 0.98

## Angle of the turntable in radians.
var angle := 0.0
## The model currently on the turntable.
var model: Node3D

var _tokens := UITokens.active()
var _viewport := SubViewport.new()
var _turntable := Node3D.new()
var _dragging := false


func _init() -> void:
	stretch = true
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.handle_input_locally = true
	add_child(_viewport)
	_build_world()
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	custom_minimum_size = Vector2(560, 640)


func _process(delta: float) -> void:
	var stick := Input.get_axis(&"look_left", &"look_right")
	if absf(stick) > 0.0:
		angle += stick * STICK_SPEED * delta
	elif not UIMotion.reduced and not _dragging:
		angle += IDLE_SPEED * delta
	_turntable.rotation.y = angle


func _gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	):
		_dragging = (event as InputEventMouseButton).pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		angle += (event as InputEventMouseMotion).relative.x * DRAG_SPEED
		accept_event()


## Puts the character with `look` on the turntable, wearing the armband of `seat`.
func show_look(look: CharacterLook, seat := 0) -> void:
	var previous := model
	model = CharacterAssembler.assemble(look, seat)
	model.scale = Vector3.ONE * MODEL_SCALE
	model.position.y = PLATE_HEIGHT
	# A new model stands in its T-pose for the first frame, before its clip first runs, so it is
	# kept hidden for a frame and the old one stays until then.
	_turntable.add_child(model)
	if not is_inside_tree():
		_reveal(model, previous)
		return
	model.visible = false
	var fresh := model
	get_tree().process_frame.connect(func() -> void: _reveal(fresh, previous), CONNECT_ONE_SHOT)


func _reveal(fresh: Node3D, previous: Node3D) -> void:
	if is_instance_valid(fresh):
		fresh.visible = true
	if is_instance_valid(previous):
		previous.queue_free()


func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.32, 0.27, 0.48)
	environment.ambient_light_energy = 0.7
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)

	var camera := Camera3D.new()
	camera.fov = CAMERA_FOV
	_viewport.add_child(camera)
	camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET)

	# The key light is the sign's warm tube, high and in front; the rim light is the screen's cold
	# glow behind, which keeps the silhouette readable on a dark ground.
	var key := SpotLight3D.new()
	key.light_color = _tokens.accent_bright
	key.light_energy = 6.0
	key.spot_range = 12.0
	key.spot_angle = 32.0
	_viewport.add_child(key)
	key.look_at_from_position(Vector3(1.4, 4.6, 3.4), Vector3(0.0, 0.8, 0.0))
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.45, 0.62, 1.0)
	rim.light_energy = 2.6
	rim.omni_range = 9.0
	rim.position = Vector3(-2.0, 2.2, -2.8)
	_viewport.add_child(rim)

	_viewport.add_child(_turntable)
	_turntable.add_child(_build_plate())


func _build_plate() -> Node3D:
	var plate := Node3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = PLATE_RADIUS
	disc.bottom_radius = PLATE_RADIUS
	disc.height = PLATE_HEIGHT
	var disc_material := StandardMaterial3D.new()
	disc_material.albedo_color = Color(0.1, 0.09, 0.14)
	disc_material.roughness = 0.45
	disc_material.metallic = 0.5
	disc.material = disc_material
	var disc_node := MeshInstance3D.new()
	disc_node.mesh = disc
	disc_node.position.y = PLATE_HEIGHT * 0.5
	plate.add_child(disc_node)

	var rim := TorusMesh.new()
	rim.inner_radius = RIM_RADIUS - 0.03
	rim.outer_radius = RIM_RADIUS
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = _tokens.accent
	rim_material.emission_enabled = true
	rim_material.emission = _tokens.accent
	rim_material.emission_energy_multiplier = 1.6
	rim.material = rim_material
	var rim_node := MeshInstance3D.new()
	rim_node.mesh = rim
	rim_node.position.y = PLATE_HEIGHT
	plate.add_child(rim_node)
	return plate
