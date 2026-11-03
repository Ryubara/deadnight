extends Node3D
## The small-map kit's lamps and light cards in a room and a corridor at night (issue #636; the page
## is `docs/research/maps/small-map-art.md`). Not part of the game.
##
## The room (6 x 8 m, 2.8 m ceiling) has a barred opening and a boarded window in its north wall,
## each with a moon shaft; the prize crane under a pendant lamp between them; a wall buy under a
## pendant on the east wall with a chalk line; and in the east wall a purchase door with the light
## of the corridor beyond it. The corridor (2 x 8 m) has a row of three pendants with no light of
## their own, a wall lantern that is its one real light, and a barred opening whose shaft lands on
## the far wall over a chalk line. The walls with a door or a window are the blockout's pieces
## (`tools/blender/build_kit_blockout.py --gltf`) when they are in
## `res://tests/captures/kit_pieces/` (`tools/web_smoke/smallmap_lights.py` copies them into its
## copy of the project); without them they are CSG walls of the same sizes. The night is the lot's
## (environment and moon).
##
## Arguments after `--` (or the page's query on the web): `--spot=room|box|door|corridor` holds the
## shoulder camera at one place (without it the four are toured, ten frames each, first without the
## cards and then with them: frame `10 * shot + 9` is the settled one); `--cards=0` leaves the cards
## out (the lamps' real lights and models stay); `--frames=N` measures N frames after a settle and
## reports their times (`window.__bench` on the web, a `SMALLMAP_LIGHTS` line), with `--unpaced`
## lifting vertical sync and the frame limit so a frame's time is its work.

const PIECES := "res://tests/captures/kit_pieces/"
const GREYBOX := "res://world/drive_in_greybox.tscn"
const SOLDIER := "res://assets/characters/soldier/soldier.glb"
## The player scene's scale of the Soldier model (1.8 m in the game).
const SOLDIER_SCALE := 0.8
## The moon indoors: the Compatibility renderer gives it no shadows, so it lights every floor under
## a roof as if there were none. The lot's 0.36 there washes the rooms out; the shafts carry the
## moonlight instead, and the directional light keeps this much, so the dead's moon side still
## reads.
const INDOOR_MOON := 0.1
const PENDANT := preload("res://world/smallmap/lights/pendant_light.tscn")
const LANTERN := preload("res://world/smallmap/lights/lantern_light.tscn")
const PATTERN_BLOCKS := preload("res://assets/lot/textures/blocks.png")
const PATTERN_CONCRETE := preload("res://assets/lot/textures/concrete.png")
const LOT_SURFACE := preload("res://assets/lot/lot_surface.gdshader")
const QUERY := "location.search.replace(/^\\?/, '')"

const CLEAR := 2.8
const WALL_T := 0.3
## The lot's moon: from the north, 38 degrees up (`tools/world/build_greybox.py`).
const MOON_PITCH := 38.0
const SETTLE_FRAMES := 120
const SHOT_FRAMES := 10

## Where the shoulder camera's player stands, which way they face (degrees round Y, 0 is north) and
## the camera's tilt.
const SPOTS := {
	"room": {"feet": Vector3(-1.6, 0.0, 1.6), "yaw": -37.0, "pitch": 2.0},
	"box": {"feet": Vector3(-0.4, 0.0, -0.6), "yaw": 0.0, "pitch": 4.0},
	"door": {"feet": Vector3(0.2, 0.0, -1.3), "yaw": -75.0, "pitch": 0.0},
	"corridor": {"feet": Vector3(7.0, 0.0, -1.3), "yaw": -105.0, "pitch": 0.0},
}
const TOUR: Array[String] = ["room", "box", "door", "corridor"]

## Which lights and cards the room has, for the tests.
var room: Node3D
var corridor: Node3D
var camera: Camera3D
var _args := {}
var _soldier: Node3D
var _frame := 0
var _times: Array[float] = []
var _last_usec := 0
var _reported := false
var _materials := {}


func _ready() -> void:
	_args = _parse_args()
	if _args.has("unpaced"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	build()
	set_cards(str(_args.get("cards", "1")) != "0")
	_place_camera(str(_args.get("spot", "room")))


## Builds the night, the room and the corridor, and the camera; tests call it on a fresh node.
func build() -> void:
	_night()
	room = Node3D.new()
	room.name = "Room"
	add_child(room)
	corridor = Node3D.new()
	corridor.name = "Corridor"
	add_child(corridor)
	_build_room()
	_build_corridor()
	camera = Camera3D.new()
	# Placed by hand each frame: physics interpolation would draw it a tick behind the cards.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = 60.0  # PlayerTuning.fov
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(camera)
	camera.make_current()
	_soldier = _model(SOLDIER)
	if _soldier != null:
		_soldier.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_soldier)
		var player := _soldier.find_children("*", "AnimationPlayer", true, false)
		if not player.is_empty():
			var anims := player[0] as AnimationPlayer
			for clip in anims.get_animation_list():
				if clip.to_lower().begins_with("idle"):
					anims.play(clip)
					break


## The light cards on or off: off leaves the lamps' models and real lights, as the room was lit
## before the cards.
func set_cards(on: bool) -> void:
	for node in find_children("*", "", true, false):
		if node is MoonShaft or node is DoorGlow or node is ChalkMessage:
			(node as Node3D).visible = on
		elif node is KitLamp:
			for part in [^"Halo", ^"Pool", ^"Haze", ^"Wash"]:
				var card := node.get_node_or_null(part) as Node3D
				if card != null:
					card.visible = on


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_frame += 1
	if _args.has("frames"):
		if _frame == SETTLE_FRAMES and OS.has_feature("web"):
			# The probe counts the GL programs linked from here on (none, once everything is drawn).
			JavaScriptBridge.eval("window.__measure_from = performance.now();")
		if _frame > SETTLE_FRAMES and _last_usec > 0:
			_times.append((now - _last_usec) / 1000.0)
		if _times.size() >= int(_args["frames"]) and not _reported:
			_reported = true
			_report()
	elif _args.has("tour"):
		var shot := _frame / SHOT_FRAMES
		if shot >= TOUR.size() * 2:
			get_tree().quit()
			return
		set_cards(shot >= TOUR.size())
		_place_camera(TOUR[shot % TOUR.size()])
	_last_usec = now


func _report() -> void:
	var sorted := _times.duplicate()
	sorted.sort()
	var total := 0.0
	for t: float in _times:
		total += t
	var report := {
		"spot": str(_args.get("spot", "room")),
		"cards": str(_args.get("cards", "1")) != "0",
		"frames": _times.size(),
		"mean_ms": snappedf(total / _times.size(), 0.001),
		"p50_ms": snappedf(sorted[sorted.size() / 2], 0.001),
		"p95_ms": snappedf(sorted[int(sorted.size() * 0.95)], 0.001),
		"max_ms": snappedf(sorted[sorted.size() - 1], 0.001),
		"lights": get_tree().get_nodes_in_group(&"smallmap_capture_light").size(),
	}
	var json := JSON.stringify(report)
	print("SMALLMAP_LIGHTS ", json)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__bench = %s;" % json)
	elif not _args.has("stay"):
		get_tree().quit()


func _place_camera(spot_name: String) -> void:
	var spot: Dictionary = SPOTS.get(spot_name, SPOTS["room"])
	var feet: Vector3 = spot["feet"]
	var yaw := deg_to_rad(float(spot["yaw"]))
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var pivot := feet + Vector3.UP * 1.6  # PlayerTuning: pivot 1.6, shoulder 0.6, arm 2.3
	camera.global_position = pivot + right * 0.6 - forward * 2.3
	camera.global_rotation = Vector3(deg_to_rad(float(spot["pitch"])), yaw, 0.0)
	if _soldier != null:
		_soldier.global_position = feet
		_soldier.global_basis = Basis(Vector3.UP, yaw + PI).scaled(Vector3.ONE * SOLDIER_SCALE)


# --- The night: the lot's environment and moon ---------------------------------------------------


func _night() -> void:
	var lot := (load(GREYBOX) as PackedScene).instantiate()
	var lot_env := lot.get_node("Lighting/WorldEnvironment") as WorldEnvironment
	var lot_moon := lot.get_node("Lighting/Moon") as DirectionalLight3D
	var env := WorldEnvironment.new()
	env.environment = lot_env.environment.duplicate()
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = lot_moon.light_color
	moon.light_energy = INDOOR_MOON if not _args.has("lot_moon") else lot_moon.light_energy
	moon.shadow_enabled = false
	add_child(moon)
	moon.look_at_from_position(Vector3.ZERO, moon_direction(), Vector3.UP)
	lot.free()
	var ground := CSGBox3D.new()
	ground.name = "Outskirts"
	ground.size = Vector3(80.0, 0.2, 80.0)
	ground.position = Vector3(4.0, -0.12, 0.0)
	ground.material = _surface("outside", PATTERN_CONCRETE, Color("#3a404c"), 4.0)
	add_child(ground)


## Where the moonlight goes (from the north, down).
static func moon_direction() -> Vector3:
	var p := deg_to_rad(MOON_PITCH)
	return Vector3(0.0, -sin(p), cos(p))


# --- The room ------------------------------------------------------------------------------------


func _build_room() -> void:
	var walls := _surface("room_wall", PATTERN_BLOCKS, Color("#9a968c"), 3.2)
	var floor_paint := _surface("room_floor", PATTERN_CONCRETE, Color("#8f8c84"), 4.0)
	var ceiling := _surface("room_ceiling", PATTERN_CONCRETE, Color("#6f6c66"), 4.0)
	_slab(room, "Floor", Vector3(0.0, -0.1, 0.0), Vector3(6.0, 0.2, 8.0), floor_paint)
	_slab(room, "Ceiling", Vector3(0.0, CLEAR + 0.1, 0.0), Vector3(6.6, 0.2, 8.6), ceiling)
	# North wall, room side +Z: the barred opening, a plain module, the boarded window.
	_barred(room, "Barred", Transform3D(Basis(), Vector3(-2.0, 0.0, -4.15)), walls)
	_plain(room, "NorthPlain", Transform3D(Basis(), Vector3(0.0, 0.0, -4.15)), 2.0, walls)
	_piece(room, "wall_window_boarded", Transform3D(Basis(), Vector3(2.0, 0.0, -4.15)), walls)
	_shaft(
		room,
		"BarredShaft",
		Transform3D(Basis(), Vector3(-2.0, 0.0, -4.15)),
		Vector2(2.0, 2.4),
		0.0,
		7,
		0
	)
	var boarded := _shaft(
		room,
		"WindowShaft",
		Transform3D(Basis(), Vector3(2.0, 0.0, -4.15)),
		Vector2(1.2, 1.3),
		0.9,
		0,
		4
	)
	boarded.shadow = 0.7
	# East wall, room side -X: the purchase door into the corridor in its middle module.
	var east := Basis(Vector3.UP, deg_to_rad(-90.0))
	_plain(room, "EastPlainN", Transform3D(east, Vector3(3.15, 0.0, -3.0)), 2.0, walls)
	_piece(room, "wall_door_narrow", Transform3D(east, Vector3(3.15, 0.0, -1.0)), walls)
	_plain(room, "EastPlainS", Transform3D(east, Vector3(3.15, 0.0, 2.0)), 4.0, walls)
	# West and south walls, plain.
	var west := Basis(Vector3.UP, deg_to_rad(90.0))
	_plain(room, "West", Transform3D(west, Vector3(-3.15, 0.0, 0.0)), 8.6, walls)
	_plain(room, "South", Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 4.15)), 6.0, walls)
	# The box: the prize crane on the north wall, its pendant following the crane's own lamp (the
	# crane's light is the real one; the pendant adds no slot).
	var crane := PrizeCrane.new()
	crane.name = "Crane"
	room.add_child(crane)
	var tuning := load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning
	var item := tuning.economy.item(&"crane_play")
	crane.configure(tuning.crane, item.pool if item != null else [])
	crane.position = Vector3(0.0, 0.0, -3.35)
	crane.show_state({"stage": CraneState.Stage.READY}, 0.0)
	var crane_light := crane.find_children("*", "OmniLight3D", true, false)[0] as OmniLight3D
	crane_light.add_to_group(&"smallmap_capture_light")
	_pendant(room, "BoxLamp", Vector3(0.0, 0.0, -1.9), false, crane_light)
	# The wall buy: the lot's plaque on the east wall under a pendant with a light of its own, and a
	# chalk line beside it in that lamp's light.
	var plaque := CSGBox3D.new()
	plaque.name = "BuyPlaque"
	plaque.size = Vector3(0.12, 0.9, 1.7)
	plaque.position = Vector3(2.94, 1.6, -3.0)
	plaque.material = load("res://assets/lot/materials/plaque.tres")
	room.add_child(plaque)
	var buy_lamp := _pendant(room, "BuyLamp", Vector3(2.3, 0.0, -3.0), true, null)
	_chalk(
		room,
		"BuyChalk",
		Transform3D(east, Vector3(2.99, 0.8, -3.0)),
		0,
		1.3,
		buy_lamp.get_node("Light")
	)


# --- The corridor ---------------------------------------------------------------------------------


func _build_corridor() -> void:
	var walls := _surface("corridor_wall", PATTERN_CONCRETE, Color("#b3a588"), 2.0)
	var floor_paint := _surface("corridor_floor", PATTERN_CONCRETE, Color("#8f8c84"), 4.0)
	var ceiling := _surface("corridor_ceiling", PATTERN_CONCRETE, Color("#6f6c66"), 4.0)
	# Inside: x 3.3 to 11.3, z -2 to 0; the door (in the room's east wall) is its west end.
	_slab(corridor, "Floor", Vector3(7.3, -0.1, -1.0), Vector3(8.0, 0.2, 2.0), floor_paint)
	_slab(corridor, "Ceiling", Vector3(7.3, CLEAR + 0.1, -1.0), Vector3(8.6, 0.2, 2.6), ceiling)
	_plain(corridor, "NorthW", Transform3D(Basis(), Vector3(4.8, 0.0, -2.15)), 3.0, walls)
	_barred(corridor, "Barred", Transform3D(Basis(), Vector3(7.3, 0.0, -2.15)), walls)
	_plain(corridor, "NorthE", Transform3D(Basis(), Vector3(9.8, 0.0, -2.15)), 3.0, walls)
	_plain(
		corridor, "South", Transform3D(Basis(Vector3.UP, PI), Vector3(7.3, 0.0, 0.15)), 8.6, walls
	)
	var east := Basis(Vector3.UP, deg_to_rad(-90.0))
	_plain(corridor, "End", Transform3D(east, Vector3(11.45, 0.0, -1.0)), 2.6, walls)
	# The moon through the bars lands on the far (south) wall, 2 m on, and a chalk line is in it.
	var shaft := _shaft(
		corridor,
		"Shaft",
		Transform3D(Basis(), Vector3(7.3, 0.0, -2.15)),
		Vector2(2.0, 2.4),
		0.0,
		7,
		0
	)
	shaft.land_wall = 2.0
	_chalk(
		corridor,
		"ShaftChalk",
		Transform3D(Basis(Vector3.UP, PI), Vector3(7.2, 0.5, -0.01)),
		1,
		1.4,
		get_node("Moon")
	)
	# The lantern on the end wall is the corridor's one real light; the row of pendants follows it.
	var lantern := LANTERN.instantiate() as KitLamp
	lantern.name = "Lantern"
	lantern.transform = Transform3D(east, Vector3(11.3, 0.0, -1.0))
	corridor.add_child(lantern)
	var lantern_light := lantern.get_node("Light") as Light3D
	lantern_light.add_to_group(&"smallmap_capture_light")
	for x: float in [5.3, 7.7, 10.1]:
		_pendant(
			corridor, "Pendant%d" % roundi(x * 10), Vector3(x, 0.0, -1.0), false, lantern_light
		)
	# The light beyond the room's purchase door is the corridor's: it burns with the lantern.
	var glow := DoorGlow.new()
	glow.name = "DoorGlow"
	glow.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3(3.15, 0.0, -1.0))
	glow.light_path = lantern_light.get_path()
	room.add_child(glow)


# --- Builders -------------------------------------------------------------------------------------


func _pendant(parent: Node3D, label: String, at: Vector3, own: bool, follow: Light3D) -> KitLamp:
	var lamp := PENDANT.instantiate() as KitLamp
	lamp.name = label
	lamp.own_light = own
	lamp.position = at
	if follow != null:
		lamp.light_path = follow.get_path()  # absolute: the lamp is not in the tree yet
	parent.add_child(lamp)
	if own:
		(lamp.get_node("Light") as Light3D).add_to_group(&"smallmap_capture_light")
	return lamp


func _shaft(
	parent: Node3D,
	label: String,
	at: Transform3D,
	opening: Vector2,
	sill: float,
	bars: int,
	rails: int
) -> MoonShaft:
	var shaft := MoonShaft.new()
	shaft.name = label
	shaft.transform = at
	shaft.opening = opening
	shaft.sill = sill
	shaft.bars = bars
	shaft.rails = rails
	shaft.pitch = MOON_PITCH
	parent.add_child(shaft)
	return shaft


func _chalk(
	parent: Node3D, label: String, at: Transform3D, message: int, width: float, follow: Node
) -> void:
	var chalk := ChalkMessage.new()
	chalk.name = label
	chalk.transform = at
	chalk.message = message
	chalk.width = width
	if follow != null:
		chalk.light_path = follow.get_path()
	parent.add_child(chalk)


## A blockout piece when it is there, otherwise a CSG wall of its size with its opening.
func _piece(parent: Node3D, piece: String, at: Transform3D, paint: Material) -> void:
	var path := PIECES + piece + ".gltf"
	var model := _model(path)
	if model != null:
		model.name = piece
		model.transform = at
		parent.add_child(model)
		return
	var opening := (
		Rect2(-0.7, 0.0, 1.4, 2.4) if piece == "wall_door_narrow" else Rect2(-0.6, 0.9, 1.2, 1.3)
	)
	var wall := _plain(parent, piece, at, 2.0, paint)
	var hole := CSGBox3D.new()
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	hole.size = Vector3(opening.size.x, opening.size.y, WALL_T + 0.1)
	hole.position = Vector3(
		opening.position.x + opening.size.x / 2.0,
		opening.position.y + opening.size.y / 2.0 - CLEAR / 2.0,
		0.0
	)
	wall.add_child(hole)
	if piece == "wall_door_narrow":
		var leaf := CSGBox3D.new()
		leaf.size = Vector3(1.36, 2.36, 0.08)
		leaf.position = Vector3(0.0, 1.18 - CLEAR / 2.0, 0.0)
		leaf.material = load("res://assets/lot/materials/door.tres")
		wall.add_child(leaf)


## A 2 m module with a 2.0 x 2.4 m opening from the floor and seven bars (not in the blockout).
func _barred(parent: Node3D, label: String, at: Transform3D, paint: Material) -> void:
	var wall := _plain(parent, label, at, 2.0, paint)
	var hole := CSGBox3D.new()
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	hole.size = Vector3(1.9, 2.4, WALL_T + 0.1)
	hole.position = Vector3(0.0, 1.2 - CLEAR / 2.0, 0.0)
	wall.add_child(hole)
	var iron := _flat("iron", Color("#7d4b2f"))
	for i in 7:
		var bar := CSGCylinder3D.new()
		bar.radius = 0.025
		bar.height = 2.4
		bar.sides = 6
		bar.position = Vector3(-0.95 + (i + 1) * 1.9 / 8.0, 1.2 - CLEAR / 2.0, 0.0)
		bar.material = iron
		wall.add_child(bar)


func _plain(
	parent: Node3D, label: String, at: Transform3D, width: float, paint: Material
) -> CSGBox3D:
	var wall := CSGBox3D.new()
	wall.name = label
	wall.size = Vector3(width, CLEAR, WALL_T)
	wall.transform = at * Transform3D(Basis(), Vector3(0.0, CLEAR / 2.0, 0.0))
	wall.material = paint
	parent.add_child(wall)
	return wall


func _slab(parent: Node3D, label: String, at: Vector3, size: Vector3, paint: Material) -> void:
	var slab := CSGBox3D.new()
	slab.name = label
	slab.size = size
	slab.position = at
	slab.material = paint
	parent.add_child(slab)


func _surface(key: String, pattern: Texture2D, tint: Color, metres: float) -> ShaderMaterial:
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = LOT_SURFACE
		material.set_shader_parameter(&"pattern", pattern)
		material.set_shader_parameter(&"tint", tint)
		material.set_shader_parameter(&"metres_per_tile", metres)
		_materials[key] = material
	return _materials[key]


func _flat(key: String, colour: Color) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 1.0
		_materials[key] = material
	return _materials[key]


func _model(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	return (load(path) as PackedScene).instantiate() as Node3D


func _parse_args() -> Dictionary:
	var parsed := {}
	var args := OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		args = PackedStringArray(str(JavaScriptBridge.eval(QUERY, true)).split("&", false))
	for arg in args:
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
