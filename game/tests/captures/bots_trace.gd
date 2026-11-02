extends Node
## A top-down trace of bots moving (bots plan, phase 2), for the pull request: the lot seen from
## straight above, each player a disc, each bot's way drawn behind it. Two views, `--mode=door` and
## `--mode=gap`:
## - `door`: a person (white) walks to the concession's door, buys it, and walks on through to the
##   midway; four bots (coloured) follow, wait for the new mesh a moment and go through after them.
## - `gap`: a bot is sent through a car gap that is shut by something the walking mesh does not know
##   about (the red box); it presses against it, steps aside, tries again, gives the goal up and
##   walks back, and the label shows the rung of the stuck ladder it is on.
## Not part of the game. Run with Movie Maker through the kit's `gds godot`, which keeps the window
## off the person's desktop: `gds godot -- --path game res://tests/captures/bots_trace.tscn
## --fixed-fps 10 --write-movie out.png --quit-after 300 -- --mode=door`.

## Game ticks played in each physics frame (the engine runs six of them to each frame of a
## recording at 10 frames a second, which is real time).
const TICKS_PER_FRAME := 1
const SEED := 31
const COLOURS := [
	Color(1.0, 0.35, 0.25),
	Color(0.3, 0.75, 1.0),
	Color(1.0, 0.85, 0.2),
	Color(0.55, 1.0, 0.45),
]
const HUMAN := Color(1.0, 1.0, 1.0)
const DISC_RADIUS := 0.9
const TRAIL_LIFT := 0.6
const TRAIL_EVERY := 3
const DOOR := &"door_concession"

var _night: SeatedNight
var _mode := "door"
var _trails: Dictionary = {}
var _discs: Dictionary = {}
var _label: Label
var _tick := 0
var _stage := 0
var _route: Array[Vector3] = []
var _leg := 0
var _gap: Dictionary = {}
var _trail_mesh: MeshInstance3D
var _immediate := ImmediateMesh.new()
var _goal_brain: GoalBrain
var _args := {}
var _started := false


func _ready() -> void:
	_args = _parse_args()
	_mode = String(_args.get("mode", "door"))
	var holder := Node3D.new()
	add_child(holder)
	_night = await SeatedNight.start(
		holder, 5 if _mode == "door" else 2, SeatedNight.one_a_round(), SEED
	)
	_night.human(1)
	for id in range(2, 6 if _mode == "door" else 3):
		_night.seat(id, BotProfile.regular(), SEED + id)
	await _night.settle(12)
	_make_view()
	if _mode == "door":
		_start_door()
	else:
		_start_gap()
	_started = true


func _physics_process(_delta: float) -> void:
	if not _started:
		return
	for _i in TICKS_PER_FRAME:
		_night.tick()
		_tick += 1
		if _mode == "door":
			_step_door()
		else:
			_step_gap()
		if _tick % TRAIL_EVERY == 0:
			_record()
	_draw()


# --- The scenes ---


func _start_door() -> void:
	_place(1, Vector3(0.0, 0.0, -9.0))
	_place(2, Vector3(-3.0, 0.0, -15.0))
	_place(3, Vector3(3.0, 0.0, -15.0))
	_place(4, Vector3(-6.0, 0.0, -20.0))
	_place(5, Vector3(6.0, 0.0, -20.0))
	_route = [Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, 6.0), Vector3(-10.0, 0.0, 30.0)]
	_night.walkers[0].goto(_route[0])


func _step_door() -> void:
	var walker := _night.walkers[0]
	if not walker.arrived():
		return
	if _stage == 0:
		# At the door: buy it, give the mesh a moment, and go on through.
		_night.open_door(DOOR)
		_stage = 1
		_leg = 1
		walker.goto(_route[1])
	elif _stage == 1 and _leg < _route.size() - 1:
		_leg += 1
		walker.goto(_route[_leg])


func _start_gap() -> void:
	var gaps := _meshed_gaps()
	_gap = gaps[0]
	var middle: Vector3 = _gap["middle"]
	var across: Vector3 = (_gap["to"] - _gap["from"]).normalized()
	var box := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var size := Vector3(2.6, 2.2, 0.8)
	var collider := BoxShape3D.new()
	collider.size = size
	shape.shape = collider
	box.add_child(shape)
	_night.world.add_child(box)
	box.global_position = middle + Vector3(0.0, size.y * 0.5, 0.0)
	box.rotate_y(atan2(-across.x, -across.z))
	var mesh := MeshInstance3D.new()
	var visual := BoxMesh.new()
	visual.size = size
	mesh.mesh = visual
	mesh.material_override = _unshaded(Color(0.9, 0.1, 0.1, 0.8))
	box.add_child(mesh)
	_place(2, _gap["from"])
	_place(1, _gap["from"] + (_gap["from"] - middle).normalized() * 3.0 + Vector3(2.0, 0.0, 0.0))
	_goal_brain = GoalBrain.new()
	_night.host.bots[0].brain = _goal_brain
	_goal_brain.legs = _night.host.bots[0].legs
	_goal_brain.errands = [_gap["to"], _gap["from"]]
	_night.host.bots[0].profile.follows = false


func _step_gap() -> void:
	pass


## The gaps between parked cars that the walking mesh passes (the same search as the scenario test).
func _meshed_gaps() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var map := _night.world.map()
	for row in _night.world.greybox.get_node("Field/Rows").get_children():
		var cars := row.get_children()
		for i in cars.size() - 1:
			var a: Vector3 = (cars[i] as Node3D).global_position
			var b: Vector3 = (cars[i + 1] as Node3D).global_position
			if Vector2(a.x - b.x, a.z - b.z).length() > 5.0:
				continue
			var middle := (a + b) * 0.5
			var across := Vector3(-(b.z - a.z), 0.0, b.x - a.x).normalized()
			var from := middle - across * 3.5
			var to := middle + across * 3.5
			var way := NavigationServer3D.map_get_path(map, from, to, true)
			var length := 0.0
			for k in way.size() - 1:
				length += way[k].distance_to(way[k + 1])
			if not way.is_empty() and length < 7.6:
				found.append({"middle": middle, "from": from, "to": to})
	return found


func _place(id: int, at: Vector3) -> void:
	_night.server.body_of(id).teleport(at + Vector3(0.0, 0.1, 0.0))


# --- The picture ---


func _make_view() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 300.0
	add_child(camera)
	camera.current = true
	if _mode == "door":
		camera.size = 80.0
		camera.position = Vector3(0.0, 120.0, 4.0)
	else:
		var middle: Vector3 = _meshed_gaps()[0]["middle"]
		camera.size = 22.0
		camera.position = Vector3(middle.x, 120.0, middle.z)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_label)
	_trail_mesh = MeshInstance3D.new()
	_trail_mesh.mesh = _immediate
	_trail_mesh.material_override = _unshaded(Color.WHITE)
	_trail_mesh.material_override.vertex_color_use_as_albedo = true
	add_child(_trail_mesh)
	var ids: Array[int] = [1]
	for bot in _night.host.bots:
		ids.append(bot.state.player_id)
	for id in ids:
		var disc := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = DISC_RADIUS * (1.3 if id == 1 else 1.0)
		cylinder.bottom_radius = cylinder.top_radius
		cylinder.height = 0.4
		disc.mesh = cylinder
		disc.material_override = _unshaded(_colour_of(id))
		add_child(disc)
		_discs[id] = disc
		_trails[id] = PackedVector3Array()


func _colour_of(id: int) -> Color:
	return HUMAN if id == 1 else COLOURS[(id - 2) % COLOURS.size()]


func _unshaded(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	if colour.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _record() -> void:
	for id: int in _trails:
		var points: PackedVector3Array = _trails[id]
		points.append(_night.server.body_of(id).global_position + Vector3(0.0, TRAIL_LIFT, 0.0))
		_trails[id] = points


func _draw() -> void:
	_immediate.clear_surfaces()
	var drawn := false
	for id: int in _trails:
		drawn = drawn or (_trails[id] as PackedVector3Array).size() > 1
	if drawn:
		_draw_trails()
	for id: int in _discs:
		var at := _night.server.body_of(id).global_position
		(_discs[id] as MeshInstance3D).global_position = at + Vector3(0.0, 1.2, 0.0)
	var title := "Following through a door" if _mode == "door" else "A shut gap"
	var text := "%s   t = %.1f s" % [title, float(_tick) / 60.0]
	if _mode == "gap":
		var bot: BotClient = _night.host.bots[0]
		text += (
			"   ladder rung %d   goals dropped %d" % [bot.legs.stuck.rung, bot.legs.dropped.size()]
		)
	_label.text = text


func _draw_trails() -> void:
	_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for id: int in _trails:
		var points: PackedVector3Array = _trails[id]
		var colour := _colour_of(id)
		for i in range(1, points.size()):
			_immediate.surface_set_color(colour)
			_immediate.surface_add_vertex(points[i - 1])
			_immediate.surface_set_color(colour)
			_immediate.surface_add_vertex(points[i])
	_immediate.surface_end()


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
