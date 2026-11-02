extends Node3D
## Capture: forty zombies spawned on one point of the lot, seen from above. Each frame runs three
## ticks (the first, one). The square is the
## lot; a label counts how many zombies are outside it and how far the farthest got.
##
##   godot --path game res://tests/captures/zombie_pile.tscn --fixed-fps 10 \
##       --write-movie out/pile.png --quit-after 40

const COUNT := 40
const LOT_HALF := Vector2(15.0, 10.0)
const VIEW_HEIGHT := 44.0
const TICKS_PER_FRAME := 3

var _sim: ZombieSim
var _markers: Dictionary[int, MeshInstance3D] = {}
var _label := Label.new()
var _frame := 0
var _ticks := 0


func _ready() -> void:
	_sim = ZombieSim.new(ZombieTuning.shipped(), 5)
	for i in COUNT:
		var zombie := _sim.spawn(i + 1, 2.0, Vector3.ZERO)
		zombie.enter(ZombieBody.Mode.CHASE)
		var marker := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.3
		cylinder.bottom_radius = 0.3
		cylinder.height = 1.7
		marker.mesh = cylinder
		marker.material_override = _colour(Color(0.85, 0.35, 0.3))
		add_child(marker)
		_markers[i + 1] = marker
	_build_stage()
	_refresh()


func _process(_delta: float) -> void:
	_frame += 1
	var ticks := 1 if _frame == 1 else TICKS_PER_FRAME
	for _i in ticks:
		_sim.tick(ZombieSim.STEP, {})
		_ticks += 1
	_refresh()


func _refresh() -> void:
	var outside := 0
	var farthest := 0.0
	for zombie: ZombieBody in _sim.zombies.values():
		_markers[zombie.id].position = Vector3(zombie.position.x, 0.85, zombie.position.z)
		var out := Vector2(
			absf(zombie.position.x) - LOT_HALF.x, absf(zombie.position.z) - LOT_HALF.y
		)
		if out.x > 0.0 or out.y > 0.0:
			outside += 1
		farthest = maxf(farthest, zombie.position.length())
	var line_one := "%d zombies spawned on one point - tick %d (%.1f s)"
	var line_two := "outside the lot: %d    farthest from the spawn: %.1f m"
	_label.text = (
		(line_one % [COUNT, _ticks, _ticks * ZombieSim.STEP])
		+ "\n"
		+ (line_two % [outside, farthest])
	)


func _build_stage() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = VIEW_HEIGHT
	camera.position = Vector3(0, 30, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	add_child(camera)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = LOT_HALF * 2.0
	ground.mesh = plane
	ground.material_override = _colour(Color(0.22, 0.24, 0.28))
	add_child(ground)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-70, 20, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.05, 0.05, 0.07)
	add_child(environment)
	for edge in [Vector3(0, 0, LOT_HALF.y), Vector3(0, 0, -LOT_HALF.y)]:
		_edge(edge, Vector3(LOT_HALF.x * 2.0, 0.1, 0.2))
	for edge in [Vector3(LOT_HALF.x, 0, 0), Vector3(-LOT_HALF.x, 0, 0)]:
		_edge(edge, Vector3(0.2, 0.1, LOT_HALF.y * 2.0))
	var layer := CanvasLayer.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 28)
	layer.add_child(_label)
	add_child(layer)


func _edge(at: Vector3, size: Vector3) -> void:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = _colour(Color(0.95, 0.8, 0.2))
	box.position = at
	add_child(box)


func _colour(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	return material
