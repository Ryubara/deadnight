extends Node
## The second map's haze columns from the shoulder camera at 1 to 8 m (#854): the pendant lamps'
## cones upstairs and the prize crane's beam. Each view is drawn with the game frozen, the column
## shown and hidden (the body hidden too), and the column's rim is measured on the difference
## (`measure`: how wide a part of the column its edge fades over). Not part of the game; run it
## windowed:
##
##   gds godot -- --path game res://tests/captures/smallmap_haze_cones.tscn -- --out=<folder>
##       [--only=<lamp or crane>] [--old] [--diffs]
##
## Writes `<column>_<distance>m.png` (the view, the column shown) and prints one line a view.
## `--old` puts the crane's beam back as it was, `--diffs` also writes the difference pictures.

const SCENE := "res://world/smallmap/smallmap_greybox.tscn"
## The pendants upstairs on the second map (the node paths the issue names) and the shop's own.
const LAMPS := ["UpperB/Lamp7", "UpperB/Lamp8", "UpperA/Lamp6", "UpperB/ShopLampUp"]
## From the shoulder camera's reach (1 to 4 m) to where the lamp is seen as a whole.
const DISTANCES := [1.0, 2.0, 3.0, 4.0, 6.0, 8.0]
const SETTLE := 30
const SEED := 5
const CIRCUITS := [&"screen_lot", &"concession", &"booth", &"back_lot", &"mains", &"battery"]
## Where the camera looks: a little down, as the shoulder camera's rest.
const PITCH_DEG := -4.0
## A pixel the column adds more than this to (of 1) counts as covered.
const COVERED := 0.02
## The upper floor's height, where the lamps upstairs stand.
const UPPER_FLOOR := 3.4
## A row counts when its brightest gain is this much and it spans this many pixels.
const MIN_ROW_PEAK := 0.04
const MIN_ROW_PX := 24
## Every this many rows are read.
const ROW_STEP := 4

var _night: Night
var _out := "user://haze"
var _only := ""
var _diffs := false
var _old := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument == "--old":
			_old = true
		elif argument == "--diffs":
			_diffs = true
		elif argument.begins_with("--only="):
			_only = argument.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(_out)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.first_spawn_delay = 6000.0
	_night = Night.new()
	_night.scene = load(SCENE) as PackedScene
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, SEED, tuning)
	await _hold(SETTLE)
	var rules := _night.server.rules
	_night.state.apply_events(rules.apply(RulesAction.grant_points(1, 100000)))
	for _pass in 4:
		for item: ShopItem in rules.tuning.economy.items:
			if item.kind == ShopItem.Kind.DOOR and not rules.is_door_open(item.id):
				_night.state.apply_events(rules.apply(RulesAction.buy(1, item.id)))
	await _hold(SETTLE)
	for circuit_id: StringName in CIRCUITS:
		_night.state.apply_events(rules.apply(RulesAction.set_circuit(circuit_id, true)))
	await _hold(SETTLE)
	if _old:
		_back_to_the_old_beam()
	for lamp_path: String in LAMPS:
		if _only == "" or lamp_path.contains(_only):
			var lamp := _night.find_child(lamp_path.get_file(), true, false) as Node3D
			await _column(
				lamp_path.replace("/", "_"),
				lamp,
				lamp.find_children("Cone", "MeshInstance3D", true, false),
				floor_of(lamp.global_position.y)
			)
	if _only == "" or _only == "crane":
		var crane := _night.find_children("*", "PrizeCrane", true, false)[0] as Node3D
		var beam: Array[Node] = []
		for mesh in crane.find_children("*", "MeshInstance3D", false, false):
			if (
				(mesh as MeshInstance3D).mesh is CylinderMesh
				and (mesh as MeshInstance3D).material_override is ShaderMaterial
			):
				beam.append(mesh)
		await _column("crane", crane, beam, UPPER_FLOOR)
	get_tree().quit()


## Every distance for one column: `holders` are the nodes drawn as the column.
func _column(label: String, axis_node: Node3D, holders: Array[Node], floor_y: float) -> void:
	for d: float in DISTANCES:
		await _view(label, axis_node, holders, floor_y, d)


static func floor_of(height: float) -> float:
	return UPPER_FLOOR if height > 2.0 else 0.0


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _aim(player: Player, yaw: float) -> void:
	player.state.facing = yaw
	player.rotation.y = yaw
	player.camera_rig.yaw = yaw
	player.camera_rig.pitch = deg_to_rad(PITCH_DEG)


func _gap(axis: Vector3) -> float:
	var camera := get_viewport().get_camera_3d().global_position
	return Vector2(camera.x - axis.x, camera.z - axis.z).length()


func _view(
	label: String, axis_node: Node3D, holders: Array[Node], floor_y: float, distance: float
) -> void:
	var axis := axis_node.global_position
	var player := _night.player()
	var found := false
	# Eight bearings: the first where the camera stands at the distance, nothing between it and
	# the column.
	for k in 8:
		var bearing := TAU * float(k) / 8.0 + 0.4
		var away := Vector3(cos(bearing), 0.0, sin(bearing))
		var yaw := atan2(away.x, away.z)
		var reach := distance + 0.6
		for _i in 4:
			var feet := Vector3(axis.x, floor_y + 0.05, axis.z) + away * reach
			player.teleport(feet)
			_aim(player, yaw)
			await _hold(10)
			reach += distance - _gap(axis)
		var space := _night.get_world_3d().direct_space_state
		var camera := get_viewport().get_camera_3d().global_position
		var query := PhysicsRayQueryParameters3D.create(camera, Vector3(axis.x, camera.y, axis.z))
		if absf(_gap(axis) - distance) < 0.12 and space.intersect_ray(query).is_empty():
			found = true
			break
	if not found:
		print("%s %.0f m: no free camera" % [label, distance])
		return
	await _hold(6)
	# Frozen: the pictures differ by what the lines below change alone.
	get_tree().paused = true
	var shown := await _grab()
	# The rim is measured on the column alone: the body's own edges are not the column's.
	player.visible = false
	var column := await _grab()
	# Out of the camera's layers rather than `visible`: the crane sets its beam's visibility itself.
	for node: Node in holders:
		(node as VisualInstance3D).layers = 0
	var bare := await _grab()
	for node: Node in holders:
		(node as VisualInstance3D).layers = 1
	player.visible = true
	get_tree().paused = false
	shown.save_png("%s/%s_%dm.png" % [_out, label, roundi(distance)])
	var numbers := measure(column, bare)
	if _diffs:
		var diff := Image.create(shown.get_width(), shown.get_height(), false, Image.FORMAT_RGB8)
		for y in diff.get_height():
			for x in diff.get_width():
				var c := column.get_pixel(x, y) - bare.get_pixel(x, y)
				diff.set_pixel(x, y, Color(c.r * 2.0, c.g * 2.0, c.b * 2.0))
		diff.save_png("%s/%s_%dm_diff.png" % [_out, label, roundi(distance)])
	print(
		(
			(
				"%s_%dm: camera %.2f m from the axis; rim softness %.3f, plateau %.3f,"
				+ " covers %.3f of the picture"
			)
			% [
				label,
				roundi(distance),
				_gap(axis),
				numbers["rim_softness"],
				numbers["plateau"],
				numbers["covered"]
			]
		)
	)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## What a column adds to a picture (`shown` less `hidden`, luminance 0 to 1). On each row it spans,
## the rim is how many pixels the gain takes to rise from a tenth to nine tenths of that row's
## brightest, from each edge, as a share of the row's width: a hard edge rises in a pixel or two
## (about 0.01), a soft fade over a good part of the column (`rim_softness`, the median over the
## rows). Also its `plateau` (the median gain where it adds) and the share of the picture it
## `covered`.
static func measure(shown: Image, hidden: Image) -> Dictionary:
	var w := shown.get_width()
	var h := shown.get_height()
	# Plain bytes, every ROW_STEP-th row: a reading of a whole picture in script is slow.
	var lit_image := shown.duplicate() as Image
	var bare_image := hidden.duplicate() as Image
	lit_image.convert(Image.FORMAT_RGB8)
	bare_image.convert(Image.FORMAT_RGB8)
	var lit := lit_image.get_data()
	var bare := bare_image.get_data()
	var rows: Array[float] = []
	var levels: Array[float] = []
	var gains := PackedFloat32Array()
	gains.resize(w)
	for y in range(0, h, ROW_STEP):
		var best := 0.0
		for x in w:
			var at := (y * w + x) * 3
			var gain := (
				(
					0.2126 * (lit[at] - bare[at])
					+ 0.7152 * (lit[at + 1] - bare[at + 1])
					+ 0.0722 * (lit[at + 2] - bare[at + 2])
				)
				/ 255.0
			)
			gain = maxf(gain, 0.0)
			gains[x] = gain
			best = maxf(best, gain)
			if gain > COVERED:
				levels.append(gain)
		if best < MIN_ROW_PEAK:
			continue
		var width := _span(gains, best, 0.1, -1) - _span(gains, best, 0.1, 1)
		if width < MIN_ROW_PX:
			continue
		var rise_left := _span(gains, best, 0.9, 1) - _span(gains, best, 0.1, 1)
		var rise_right := _span(gains, best, 0.1, -1) - _span(gains, best, 0.9, -1)
		rows.append(minf(rise_left, rise_right) / float(width))
	if rows.is_empty():
		return {"rim_softness": 0.0, "plateau": 0.0, "covered": 0.0}
	rows.sort()
	levels.sort()
	return {
		"rim_softness": rows[rows.size() / 2],
		"plateau": levels[levels.size() / 2] if not levels.is_empty() else 0.0,
		"covered": float(levels.size() * ROW_STEP) / float(w * h)
	}


## The first pixel from the left (`way` 1) or from the right (`way` -1) whose gain reaches `share`
## of `best`; for the right, the pixel after it, so a span is a plain difference.
static func _span(gains: PackedFloat32Array, best: float, share: float, way: int) -> int:
	if way > 0:
		for x in gains.size():
			if gains[x] >= best * share:
				return x
		return 0
	for x in range(gains.size() - 1, -1, -1):
		if gains[x] >= best * share:
			return x + 1
	return 0


## `--old`: the crane's beam as it was before #854 (no edge fade, no near fade), for the "before"
## numbers and pictures from the same build.
func _back_to_the_old_beam() -> void:
	for crane in _night.find_children("*", "PrizeCrane", true, false):
		for mesh in crane.find_children("*", "MeshInstance3D", false, false):
			var beam := (mesh as MeshInstance3D).material_override as ShaderMaterial
			if beam != null:
				beam.set_shader_parameter(&"rim_power", 0.0)
				beam.set_shader_parameter(&"near_fade", 0.0)
