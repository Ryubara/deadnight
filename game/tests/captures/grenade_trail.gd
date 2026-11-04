extends Node3D
## A grenade thrown over a dark floor with its trail on, for before and after captures of the trail
## (Deadnight #936). Not part of the game. Run with a window, through `gds godot`:
## `godot --path game res://tests/captures/grenade_trail.tscn --write-movie <dir>/trail.png
## --fixed-fps 30 --quit-after 150`.

const STEP := 1.0 / 60.0
const SCALE := 2.0
const CAMERA_DISTANCE := 3.5

var _view: GrenadeView
var _camera: Camera3D
var _cast: Callable


func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.03, 0.05)
	environment.ambient_light_color = Color(0.4, 0.45, 0.6)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.12, 0.12, 0.13)
	plane.material = floor_material
	add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	_camera.make_current()
	_cast = GrenadesFixture.world_cast()
	_view = GrenadeView.new()
	_view.visual_scale = SCALE
	_view.trail = true
	_view.state = GrenadeState.new(
		1, 1, GrenadesFixture.def(), Vector3(0.0, 1.5, 0.0), Vector3(7.5, 6.0, 0.0), 3.0
	)
	add_child(_view)
	_view.follow(0.0)
	_look()


func _physics_process(_delta: float) -> void:
	_view.state.step(STEP, _cast)
	_view.follow(STEP)
	_look()


## The camera stays beside the grenade, a few metres off, so the dots are seen large.
func _look() -> void:
	var at := _view.state.position
	_camera.look_at_from_position(
		at + Vector3(-1.2, 0.5, CAMERA_DISTANCE), at + Vector3(-1.2, 0.0, 0.0)
	)
