extends Node
## The dead's arrival at the lot's later areas (#849), from the player's own shoulder camera: the
## real night on the drive-in lot with every door bought, the player put at a spot looking at one
## spawn marker, only that marker's dead let in. One PNG when the first one has risen
## (`<name>_rise.png`) and one when two boards are down at a boarded breach, or a few seconds
## after the rise at a bare spawn (`<name>_arrive.png`). Not part of the game; run it windowed
## through the kit's private desktop:
##
##   gds godot -- --path game res://tests/captures/breach_arrivals.tscn -- \
##       --spots=<abs json> --out=<abs folder> [--only=<name prefix>] [--dark]
##
## The spots file is a list of `{"name", "marker", "from": [x, y, z]}`: `marker` is the spawn
## marker's path from the scene root (`GeneratorYard/ZombieSpawns/SpawnNE`), `from` the player's
## feet; the body faces the marker. The draw calls of each shot are printed (`DRAWS`).

const LOT_SCENE := "res://world/drive_in_greybox.tscn"
const SEED := 5
const SETTLE := 30
const GIVE_UP_FRAMES := 2400
const RISE_PAUSE := 8
const BARE_WAIT := 40
const CIRCUITS := [&"screen_lot", &"concession", &"booth", &"back_lot", &"mains", &"battery"]

var _night: Night
var _out := ""
var _spots_file := ""
var _only := ""
var _dark := false
var _only_points: Array[Vector3] = []


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--spots="):
			_spots_file = argument.trim_prefix("--spots=")
		elif argument.begins_with("--only="):
			_only = argument.trim_prefix("--only=")
		elif argument == "--dark":
			_dark = true
	DirAccess.make_dir_recursive_absolute(_out)
	var spots: Array = JSON.parse_string(FileAccess.get_file_as_string(_spots_file))
	for spot: Dictionary in spots:
		if _only != "" and not String(spot["name"]).begins_with(_only):
			continue
		await _arrival(spot)
	get_tree().quit()


func _arrival(spot: Dictionary) -> void:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	_night = Night.new()
	_night.scene = load(LOT_SCENE) as PackedScene
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, SEED, tuning)
	await _hold(SETTLE)
	_open_all()
	for circuit_id: StringName in CIRCUITS:
		var on := not _dark or circuit_id == &"battery"
		_night.state.apply_events(
			_night.server.rules.apply(RulesAction.set_circuit(circuit_id, on))
		)
	await _hold(SETTLE)
	var marker := _night.world.greybox.get_node(String(spot["marker"])) as Marker3D
	var gate_id := StringName(marker.get_meta(&"barricade_id", ""))
	_only_points = [marker.global_position]
	var from_array: Array = spot["from"]
	var from := Vector3(from_array[0], from_array[1], from_array[2])
	_put_player(from, marker.global_position)
	_night.server.director.spawn_points = _only_points
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	await _until(func() -> bool: return not _night.server.sim.zombies.is_empty())
	await _hold(RISE_PAUSE)
	await _shot("%s_rise" % spot["name"])
	if gate_id != &"":
		var whole := _night.server.rules.tuning.barricades.boards
		await _until(func() -> bool: return _night.world.barricade(gate_id).boards() <= whole - 2)
		await _hold(6)
	else:
		await _hold(BARE_WAIT)
	await _shot("%s_arrive" % spot["name"])
	_night.queue_free()
	await _hold(10)


func _put_player(from: Vector3, look_at: Vector3) -> void:
	var player := _night.player()
	player.teleport(from + Vector3(0, 0.05, 0))
	var yaw := atan2(-(look_at.x - from.x), -(look_at.z - from.z))
	player.state.facing = yaw
	player.rotation.y = yaw
	player.camera_rig.yaw = yaw
	player.camera_rig.pitch = deg_to_rad(-4.0)


func _shot(name: String) -> void:
	# Hold the dead's spawn restriction: the night would otherwise reset it.
	for _i in 4:
		_night.server.director.spawn_points = _only_points
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var draws := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("SHOT ", name, " DRAWS ", draws)


func _open_all() -> void:
	var rules := _night.server.rules
	_night.state.apply_events(rules.apply(RulesAction.grant_points(1, 100000)))
	for _pass in 4:
		for item: ShopItem in rules.tuning.economy.items:
			if item.kind == ShopItem.Kind.DOOR and not rules.is_door_open(item.id):
				_night.state.apply_events(rules.apply(RulesAction.buy(1, item.id)))


func _hold(frames: int) -> void:
	for _i in frames:
		if _night != null and is_instance_valid(_night) and _night.server != null:
			_night.server.director.spawn_points = (
				_only_points if not _only_points.is_empty() else _night.server.director.spawn_points
			)
		await get_tree().physics_frame


func _until(done: Callable) -> void:
	for _i in GIVE_UP_FRAMES:
		if done.call():
			return
		_night.server.director.spawn_points = _only_points
		await get_tree().physics_frame
	push_error("breach_arrivals: gave up waiting")
	get_tree().quit()
