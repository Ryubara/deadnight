extends Node
## Captures the small map's outside backdrop (issue #638) from the player's own shoulder camera
## inside a blockout room: a 10.6 x 8 m block room with a zombie window in its north wall, a broken
## hole in its east wall, a doorway in the south wall, and the kit's roof on it (five bays, the
## fourth broken, a gable at each end), and last in the yard outside, under the drive-in
## lot's night (its `Lighting`: sky, moon, ambient, fog). Not a test. Each spot holds
## `HOLD_FRAMES` frames; frame `spot * HOLD_FRAMES +
## HOLD_FRAMES - 1` is the settled shot.
##
##     gds godot -- --path game res://tests/captures/smallmap_backdrop_tour.tscn \
##         --write-movie <abs>/b.png --fixed-fps 10 --quit-after 51 -- [--off] [--fog=0.035]
##
## `--off` hides the backdrop (the room alone); `--fog` sets the fog density (default 0.035, the
## small map's from the art page; the lot's is 0.013). Prints SPOT <name> <frame> as each spot
## starts. `--bench` holds the window spot and prints, then reports as `window.__bench` in a
## browser, the frame time and the renderer's draw calls and primitives with the backdrop shown and
## hidden, alternating blocks of frames. In a browser (`tools/web_smoke/backdrop_web.py`) the page's
## query gives the same arguments (`?spot=window&hold=60`, `?bench=1&frames=600`);
## `window.__backdrop` says a spot settled.

const HOLD_FRAMES := 10
const ROOM_HALF := Vector2(5.0, 3.7)  # inside the walls
const WALL := 0.3
const HEIGHT := 2.8
const BAYS := 5
const BROKEN_BAY := 3
## Where the player stands (metres), the view's yaw and pitch (degrees).
const SPOTS := [
	{"name": "window", "at": Vector3(-1.7, 0.0, -0.9), "yaw": 0.0, "pitch": 5.0},
	{"name": "broken_wall", "at": Vector3(1.4, 0.0, 0.6), "yaw": -52.0, "pitch": 6.0},
	{"name": "door", "at": Vector3(3.0, 0.0, 0.9), "yaw": 180.0, "pitch": 4.0},
	{"name": "roof", "at": Vector3(2.4, 0.0, -1.2), "yaw": 180.0, "pitch": 44.0},
	{"name": "yard", "at": Vector3(-3.0, 0.0, -9.0), "yaw": 8.0, "pitch": 8.0},
]
const QUERY := "location.search.replace(/^\\?/, '')"
const BENCH_BLOCK := 50

var _player: Player
var _backdrop: Backdrop
var _frame := 0
var _spot := -1
var _first := 0
var _last := SPOTS.size() - 1
var _hold := HOLD_FRAMES
var _args := {}
var _told := false
var _bench := {
	"on": [], "off": [], "on_draws": [], "off_draws": [], "on_prims": [], "off_prims": []
}
var _last_usec := 0
var _shown := true


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=")
		_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	if OS.has_feature("web"):
		for pair in str(JavaScriptBridge.eval(QUERY)).split("&", false):
			var parts := pair.split("=", true, 1)
			_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	_hold = int(_args.get("hold", HOLD_FRAMES))
	if _args.has("bench"):
		_args["spot"] = "window"
	if _args.has("spot"):
		for index in SPOTS.size():
			if SPOTS[index]["name"] == _args["spot"]:
				_first = index
				_last = index
	_night_lighting()
	_room()
	_backdrop = (
		(load("res://world/smallmap/backdrop.tscn") as PackedScene).instantiate() as Backdrop
	)
	add_child(_backdrop)
	_backdrop.visible = not _args.has("off")
	_player = (load("res://gameplay/player/player.tscn") as PackedScene).instantiate() as Player
	_player.capture_mouse = false
	add_child(_player)
	_player.local_input = false
	print("BACKDROP_TRIS ", backdrop_triangles(_backdrop))


func _process(_delta: float) -> void:
	_frame += 1
	if _args.has("bench"):
		_bench_step()
		return
	var spot := _first + (_frame - 1) / _hold
	if spot > _last:
		_finish()
		return
	if spot != _spot:
		_spot = spot
		_pose(SPOTS[spot])
		print("SPOT ", SPOTS[spot]["name"], " ", _frame - 1)


func _physics_process(_delta: float) -> void:
	if _spot >= 0 and _spot <= _last:
		var spot: Dictionary = SPOTS[_spot]
		_player.camera_rig.yaw = deg_to_rad(spot["yaw"])
		_player.camera_rig.pitch = deg_to_rad(spot["pitch"])


func _pose(spot: Dictionary) -> void:
	_player.teleport(spot["at"])
	_player.camera_rig.yaw = deg_to_rad(spot["yaw"])
	_player.camera_rig.pitch = deg_to_rad(spot["pitch"])
	_player.camera_rig.snap_to(spot["at"])
	_player.state.facing = deg_to_rad(spot["yaw"])
	_player.rotation.y = _player.state.facing


## Every triangle the backdrop would draw if it were all in view: each multimesh's mesh times its
## count, and the quads.
static func backdrop_triangles(root: Node) -> int:
	var total := 0
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var mesh: Mesh = null
		var copies := 1
		if node is MultiMeshInstance3D:
			mesh = (node as MultiMeshInstance3D).multimesh.mesh
			copies = (node as MultiMeshInstance3D).multimesh.instance_count
		elif node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := (
				indices.size()
				if not indices.is_empty()
				else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			)
			total += count / 3 * copies
	return total


func _bench_step() -> void:
	var now := Time.get_ticks_usec()
	var warmup := int(_args.get("warmup", 60))
	var frames := int(_args.get("frames", 600))
	if _frame == 1:
		_spot = 0
		_pose(SPOTS[_first])
	if _frame > warmup and _frame <= warmup + frames:
		# The frame that just ended was drawn with the visibility set in the frame before it.
		var key := "on" if _shown else "off"
		_bench[key].append((now - _last_usec) / 1000.0)
		_bench[key + "_draws"].append(
			RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
			)
		)
		_bench[key + "_prims"].append(
			RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
			)
		)
	_shown = _frame <= warmup or ((_frame - warmup) / BENCH_BLOCK) % 2 == 0
	_backdrop.visible = _shown
	_last_usec = now
	if _frame == warmup + frames + 1 and not _told:
		_told = true
		var report := {
			"frames": frames,
			"tris_total": backdrop_triangles(_backdrop),
			"on_ms": _stats(_bench["on"]),
			"off_ms": _stats(_bench["off"]),
			"on_draws": _median(_bench["on_draws"]),
			"off_draws": _median(_bench["off_draws"]),
			"on_prims": _median(_bench["on_prims"]),
			"off_prims": _median(_bench["off_prims"]),
		}
		print("BENCH ", JSON.stringify(report))
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.__bench = %s" % JSON.stringify(report))
		else:
			get_tree().quit()


static func _median(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2]) if not sorted.is_empty() else 0.0


static func _stats(values: Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v: float in sorted:
		total += v
	return {
		"mean": total / maxf(1.0, sorted.size()),
		"p50": _median(sorted),
		"p95": float(sorted[int(sorted.size() * 0.95)]) if not sorted.is_empty() else 0.0,
	}


func _finish() -> void:
	if not OS.has_feature("web"):
		get_tree().quit()
		return
	if not _told:
		_told = true
		JavaScriptBridge.eval("window.__backdrop = {spot: '%s'}" % SPOTS[_last]["name"])


## The drive-in lot's night: its `Lighting` node (the sky, the moon, the ambient and the fog), with
## the fog density set for a small map.
func _night_lighting() -> void:
	var lot := (load("res://world/drive_in_greybox.tscn") as PackedScene).instantiate()
	var lighting := lot.get_node("Lighting")
	lot.remove_child(lighting)
	lot.free()
	add_child(lighting)
	var world_environment := lighting.get_node("WorldEnvironment") as WorldEnvironment
	world_environment.environment = world_environment.environment.duplicate()
	world_environment.environment.fog_density = float(_args.get("fog", 0.035))


## The blockout room, CSG with the lot's block and concrete paint, and the kit's roof on it.
func _room() -> void:
	var wall_material := load("res://assets/lot/materials/booth_wall.tres") as Material
	var floor_material := load("res://assets/lot/materials/booth_ground.tres") as Material
	var outer := ROOM_HALF + Vector2(WALL, WALL)
	_box(self, Vector3(0, -0.1, 0), Vector3(outer.x * 2, 0.2, outer.y * 2), floor_material)
	# The yard is the level's: here a hidden floor under the backdrop's frosted ground, for the yard
	# spot.
	_box(self, Vector3(0, -0.6, 0), Vector3(62, 1.0, 54), null).visible = false
	# North wall: a zombie window, 1.2 x 1.3 m, its sill at 0.9 m.
	var north := _wall(
		Vector3(0, HEIGHT / 2, -ROOM_HALF.y - WALL / 2),
		Vector3(outer.x * 2, HEIGHT, WALL),
		wall_material
	)
	_cut(north, Vector3(-1.0, 0.9 + 0.65 - HEIGHT / 2, 0), Vector3(1.2, 1.3, 1.0))
	# East wall: a broken hole, ragged (three boxes turned against each other).
	var east := _wall(
		Vector3(ROOM_HALF.x + WALL / 2, HEIGHT / 2, 0),
		Vector3(WALL, HEIGHT, outer.y * 2),
		wall_material
	)
	_cut(east, Vector3(0, 0.0, -0.8), Vector3(1.0, 1.5, 1.7), Vector3(0, 0, 0.0))
	_cut(east, Vector3(0, 0.35, -0.5), Vector3(1.0, 1.0, 1.4), Vector3(31, 0, 0))
	_cut(east, Vector3(0, -0.35, -1.2), Vector3(1.0, 0.9, 1.2), Vector3(-24, 0, 0))
	# South wall: a 1.4 x 2.4 m doorway; west wall: plain.
	var south := _wall(
		Vector3(0, HEIGHT / 2, ROOM_HALF.y + WALL / 2),
		Vector3(outer.x * 2, HEIGHT, WALL),
		wall_material
	)
	_cut(south, Vector3(1.5, 1.2 - HEIGHT / 2, 0), Vector3(1.4, 2.4, 1.0))
	_wall(
		Vector3(-ROOM_HALF.x - WALL / 2, HEIGHT / 2, 0),
		Vector3(WALL, HEIGHT, outer.y * 2),
		wall_material
	)
	# The roof: bays along X on the wall tops, a gable at each end.
	for index in BAYS:
		var bay := "roof_bay_broken" if index == BROKEN_BAY else "roof_bay"
		var x := -float(BAYS - 1) + index * 2.0
		_model("res://assets/smallmap/%s.gltf" % bay, Vector3(x, HEIGHT, 0), 0.0)
	_model("res://assets/smallmap/roof_gable.gltf", Vector3(-outer.x + 0.1, HEIGHT, 0), 90.0)
	_model("res://assets/smallmap/roof_gable.gltf", Vector3(outer.x - 0.1, HEIGHT, 0), -90.0)
	# One warm lamp in the room, as the kit's pendant lamps will be.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffd9a0")
	lamp.light_energy = 1.4
	lamp.omni_range = 7.0
	lamp.position = Vector3(-2.0, 2.4, -0.5)
	add_child(lamp)


func _wall(at: Vector3, size: Vector3, material: Material) -> CSGCombiner3D:
	var combiner := CSGCombiner3D.new()
	combiner.use_collision = true
	combiner.position = at
	add_child(combiner)
	_box(combiner, Vector3.ZERO, size, material)
	return combiner


func _cut(wall: CSGCombiner3D, at: Vector3, size: Vector3, turn := Vector3.ZERO) -> void:
	var hole := CSGBox3D.new()
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	hole.position = at
	hole.rotation_degrees = turn
	hole.size = size
	wall.add_child(hole)


func _box(parent: Node, at: Vector3, size: Vector3, material: Material) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.position = at
	box.size = size
	box.material = material
	if parent == self:
		box.use_collision = true
	parent.add_child(box)
	return box


func _model(path: String, at: Vector3, yaw: float) -> void:
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.position = at
	model.rotation_degrees.y = yaw
	add_child(model)
