extends Node
## A walk through a map from the player's own shoulder camera, one PNG a spot, for the map review
## (#833). The real night (no dead, every door open and every circuit on unless a spot says
## otherwise), the player put at each spot with the camera turned as given. Not part of the game;
## run it windowed through the kit's private desktop:
##
##   gds godot -- --path game res://tests/captures/map_review_tour.tscn -- \
##       --map=lot --out=<abs folder> [--only=<prefix>] [--dark]
##
## `--map` is `lot` or `small`. `--dark` switches every circuit off first (the generator dead).
## `--only` runs the spots whose name starts with the prefix. Spots are `[name, feet, yaw degrees,
## pitch degrees]`; yaw 0 looks at -Z (north on the lot, the screen), 180 at +Z, 90 at -X (west),
## -90 at +X.

const LOT_SCENE := "res://world/drive_in_greybox.tscn"
const SMALL_SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const SETTLE := 30
const SEED := 5
const CIRCUITS := [&"screen_lot", &"concession", &"booth", &"back_lot", &"mains", &"battery"]

const LOT_SPOTS := [
	["f01_start_apron", Vector3(0, 0, -44), 180.0, -4.0],
	["f02_screen", Vector3(0, 0, -36), 0.0, 6.0],
	["f03_avenue", Vector3(0, 0, -24), 180.0, -4.0],
	["f04_car_rows_west", Vector3(-14, 0, -26), 120.0, -6.0],
	["f05_west_flank", Vector3(-46, 0, -20), 90.0, -4.0],
	["f06_east_flank", Vector3(46, 0, -20), -90.0, -4.0],
	["f07_breach_w", Vector3(-55, 0, -22), 90.0, -4.0],
	["f08_breach_n", Vector3(-36, 0, -46), 0.0, -4.0],
	["f12_apron_w_inside", Vector3(-66, 0, -22), -90.0, -4.0],
	["f13_apron_n_inside", Vector3(-36, 0, -56), 0.0, -4.0],
	["f09_field_south_west", Vector3(-30, 0, -12.5), 180.0, -4.0],
	["f10_field_south_east", Vector3(30, 0, -12.5), 180.0, -4.0],
	["f11_field_look_back", Vector3(0, 0, -10), 0.0, 4.0],
	["c01_front", Vector3(0, 0, -10), 180.0, -4.0],
	["c02_door_in", Vector3(0, 0, -6.5), 180.0, -4.0],
	["c03_inside_counter", Vector3(0, 0, 6), 0.0, -4.0],
	["c04_inside_rear", Vector3(0, 0, 0.2), 180.0, -4.0],
	["m01_midway_north", Vector3(0, 0, 10), 180.0, -4.0],
	["m02_midway_court_west", Vector3(-8, 0, 14), 150.0, -6.0],
	["m03_midway_alley_w", Vector3(-12, 0, 4), 90.0, -4.0],
	["m04_midway_to_booth", Vector3(0, 0, 17), 180.0, -4.0],
	["m05_midway_south", Vector3(0, 0, 34), 180.0, -4.0],
	["b01_booth_door", Vector3(0, 0, 19), 180.0, -4.0],
	["b02_booth_inside", Vector3(0, 0, 24), 180.0, -4.0],
	["b03_booth_ramp_up", Vector3(-4.8, 0, 24), 180.0, 8.0],
	["b04_booth_ramp_top", Vector3(-4.8, 3.7, 29), 0.0, -4.0],
	["b05_booth_upper_room", Vector3(0, 3.7, 28), 0.0, -4.0],
	["c05_stand_window_inside", Vector3(-6, 0, 0), 0.0, 0.0],
	["y05_generator_close", Vector3(40, 0, 8), 180.0, -2.0],
	["y06_generator_east", Vector3(50, 0, 18), 90.0, -2.0],
	["y01_yard_gate", Vector3(40, 0, -7), 180.0, -4.0],
	["y02_yard_generator", Vector3(40, 0, 6), 180.0, -4.0],
	["y03_yard_far", Vector3(56, 0, 30), -90.0, -4.0],
	["y04_yard_link", Vector3(20, 0, 17), -90.0, -4.0],
	["l01_back_gate", Vector3(-40, 0, -7), 180.0, -4.0],
	["l02_back_lanes", Vector3(-40, 0, 10), 180.0, -4.0],
	["l03_back_neon", Vector3(-30, 0, 28), 150.0, -4.0],
	["l04_back_far", Vector3(-58, 0, 30), -90.0, -4.0],
	["sp1_midway_spawn_se", Vector3(14, 0, 26), 180.0, -4.0],
	["sp2_yard_spawn_ne", Vector3(48, 0, 4), -63.0, -4.0],
	["sp3_yard_spawn_se", Vector3(50, 0, 28), -129.0, -4.0],
	["sp4_back_spawn_nw", Vector3(-48, 0, 5), 60.0, -4.0],
	["sp5_back_spawn_sw", Vector3(-50, 0, 28), 129.0, -4.0],
	["sp6_plaza_spawn_sw", Vector3(-4, 0, 44), 121.0, -4.0],
	["sp7_plaza_spawn_e", Vector3(4, 0, 48), -126.0, -4.0],
	["p01_plaza_gate", Vector3(0, 0, 35), 180.0, -4.0],
	["p02_plaza_booths", Vector3(0, 0, 41), 180.0, -4.0],
	["p03_plaza_end", Vector3(0, 0, 50), 180.0, -4.0],
	["p04_plaza_back", Vector3(0, 0, 55), 0.0, -4.0],
	# The thin stretches (#855): the same spots before and after their loops and cover.
	["t01_flank_w_from_rows", Vector3(-44, 0, -17), 100.0, -4.0],
	["t02_flank_w_from_breach", Vector3(-58, 0, -21), -80.0, -4.0],
	["t03_flank_e_from_rows", Vector3(45, 0, -15), -100.0, -4.0],
	["t04_flank_e_channel", Vector3(58, 0, -27), 170.0, -4.0],
	["t05_south_w_front", Vector3(-27, 0, -14), 160.0, -4.0],
	["t06_south_w_lane", Vector3(-38, 0, -6.6), -90.0, -4.0],
	["t07_south_e_front", Vector3(27, 0, -15), -160.0, -4.0],
	["t08_south_e_lane", Vector3(17.5, 0, -7), -90.0, -4.0],
	["t09_yard_east_from_cage", Vector3(47, 0, 20), -90.0, -4.0],
	["t10_yard_east_from_south", Vector3(55, 0, 34), 10.0, -4.0],
	["t11_plaza_from_booths", Vector3(0, 0, 48.6), 180.0, -4.0],
	["t12_plaza_from_west", Vector3(-12.5, 0, 45.5), -128.0, -4.0],
]

const SMALL_SPOTS := [
	["a01_counter_roost", Vector3(8, 1.2, 6.25), 180.0, -6.0],
	["a02_counter_from_floor", Vector3(8, 0, 11), 0.0, -4.0],
	["h01_start", Vector3(8.0, 0, 12.0), 0.0, -4.0],
	["h02_hall_counter", Vector3(8.0, 0, 11.5), 0.0, -4.0],
	["h03_hall_windows", Vector3(9.0, 0, 9.5), -50.0, -4.0],
	["h04_hall_south", Vector3(8.0, 0, 9.8), 180.0, -4.0],
	["h05_hall_west_wall", Vector3(4.0, 0, 8.5), 90.0, -4.0],
	["h06_hall_door", Vector3(14.0, 0, 2.5), 0.0, -4.0],
	["s01_side_east", Vector3(14.5, 0, -2.0), 90.0, -4.0],
	["s02_side_box", Vector3(10.5, 0, -3.4), 0.0, -4.0],
	["s03_side_machines", Vector3(7.0, 0, -4.9), 20.0, -4.0],
	["s04_side_breach", Vector3(-3.0, 0, -2.5), 90.0, -4.0],
	["s05_side_west_look_back", Vector3(-8.0, 0, -2.5), -90.0, -4.0],
	["u01_stair_a_foot", Vector3(1.2, 0, 1.0), -90.0, 6.0],
	["u02_upstairs_a", Vector3(3.0, 3.4, 3.4), -90.0, -4.0],
	["u03_opening", Vector3(12.0, 3.4, 2.6), 0.0, -4.0],
	["u04_upstairs_b", Vector3(14.5, 3.4, -4.0), 90.0, -4.0],
	["u05_recut", Vector3(-0.3, 3.4, -5.0), 180.0, -4.0],
	["u06_cabinet", Vector3(-3.0, 3.4, -4.0), 90.0, -4.0],
	["u07_window_north", Vector3(9.0, 3.4, -5.0), 0.0, -4.0],
	["u08_perks_upper", Vector3(13.8, 3.4, -4.0), 0.0, -4.0],
	["u09_stair_b_down", Vector3(3.4, 3.4, -6.8), 90.0, -4.0],
	# The places the use zones' spacing moved things (#994), from a player standing in each zone.
	["z01_hall_west_wall", Vector3(5.5, 0, 11.4), 90.0, -4.0],
	["z02_hall_soda", Vector3(1.7, 0, 9.6), 90.0, -4.0],
	["z03_hall_pistol", Vector3(1.35, 0, 13.2), 90.0, -4.0],
	["z04_side_west_end", Vector3(2.5, 0, -3.0), 90.0, -4.0],
	["z05_side_breach", Vector3(-4.6, 0, -2.0), 90.0, -4.0],
	["z06_side_rescue", Vector3(-1.45, 0, -0.4), 180.0, -4.0],
	["z07_side_smg", Vector3(3.3, 0, -6.45), 0.0, -4.0],
	["z08_side_window", Vector3(14.6, 0, -5.6), 0.0, -4.0],
	["z09_upper_a_east", Vector3(8.5, 3.4, 1.5), -90.0, -4.0],
	["z10_upper_locker", Vector3(14.2, 3.4, 3.15), 180.0, -4.0],
	["z11_upper_bat", Vector3(9.7, 3.4, -1.6), 180.0, -4.0],
	["z12_upper_axe", Vector3(14.7, 3.4, -7.35), -90.0, -4.0],
	["z13_upper_shotgun", Vector3(11.0, 3.4, -6.5), 0.0, -4.0],
]

var _night: Night
var _out := ""
var _map := "lot"
var _only := ""
var _dark := false
var _plan := false
var _chain := ""
var _doors := "all"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--map="):
			_map = argument.trim_prefix("--map=")
		elif argument.begins_with("--only="):
			_only = argument.trim_prefix("--only=")
		elif argument == "--dark":
			_dark = true
		elif argument == "--plan":
			_plan = true
		elif argument.begins_with("--chain="):
			_chain = argument.trim_prefix("--chain=")
		elif argument.begins_with("--doors="):
			_doors = argument.trim_prefix("--doors=")
	DirAccess.make_dir_recursive_absolute(_out)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	# No dead: the first wave waits past the end of the walk.
	tuning.rounds.first_spawn_delay = 6000.0
	_night = Night.new()
	_night.scene = load(LOT_SCENE if _map == "lot" else SMALL_SCENE) as PackedScene
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, SEED, tuning)
	await _hold(SETTLE)
	_open_all()
	print("DOORS OPEN ", rules_doors())
	await _hold(SETTLE)
	for circuit_id: StringName in CIRCUITS:
		var on := not _dark or circuit_id == &"battery"
		_night.state.apply_events(
			_night.server.rules.apply(RulesAction.set_circuit(circuit_id, on))
		)
	await _hold(SETTLE)
	if _chain != "":
		await _chain_shots()
		get_tree().quit()
		return
	if _plan:
		await _plans()
		get_tree().quit()
		return
	for spot: Array in LOT_SPOTS if _map == "lot" else SMALL_SPOTS:
		if _only != "" and not String(spot[0]).begins_with(_only):
			continue
		await _visit(spot)
	get_tree().quit()


func _open_all() -> void:
	var rules := _night.server.rules
	_night.state.apply_events(rules.apply(RulesAction.grant_points(1, 100000)))
	# A door needs the one before it: a few passes sell them in order.
	for _pass in 4:
		for item: ShopItem in rules.tuning.economy.items:
			var wanted := _doors == "all" or _doors.split(",").has(String(item.id))
			if wanted and item.kind == ShopItem.Kind.DOOR and not rules.is_door_open(item.id):
				var events := rules.apply(RulesAction.buy(1, item.id))
				for event in events:
					if event["type"] == &"purchase_denied":
						print("DENIED ", item.id, " ", event["result"])
				_night.state.apply_events(events)


func _visit(spot: Array) -> void:
	var player := _night.player()
	player.teleport(spot[1] + Vector3(0, 0.05, 0))
	_aim(player, spot)
	await _hold(SETTLE)
	player.teleport(spot[1] + Vector3(0, 0.05, 0))
	_aim(player, spot)
	await _hold(8)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var suffix := "_dark" if _dark else ""
	get_viewport().get_texture().get_image().save_png(
		_out.path_join("%s%s.png" % [spot[0], suffix])
	)
	print("SHOT ", spot[0], " at ", spot[1])


## The body faces where the camera looks, so the shot is from behind the player.
func _aim(player: Player, spot: Array) -> void:
	var yaw := deg_to_rad(spot[2])
	player.state.facing = yaw
	player.rotation.y = yaw
	player.camera_rig.yaw = yaw
	player.camera_rig.pitch = deg_to_rad(spot[3])


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func rules_doors() -> Array:
	return _night.server.rules.doors_open


## Top-down views for the review page: orthographic, fog off, a flat light. The lot is one plan
## (`plan_lot.png`); the second map is two (`plan_small_ground.png`, `plan_small_upper.png`).
## The camera centre and size are printed so a picture can be annotated in metres.
func _plans() -> void:
	var environment := (
		(_night.find_child("WorldEnvironment", true, false) as WorldEnvironment).environment
	)
	environment.ambient_light_energy = 2.2
	environment.fog_enabled = false
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, 30, 0)
	sun.light_energy = 0.6
	add_child(sun)
	var camera := Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	if _map == "lot":
		camera.size = 128.0
		camera.look_at_from_position(Vector3(0, 80, 0), Vector3(0, 0, 0), Vector3(0, 0, -1))
		print("PLAN lot centre 0,0 height 128")
		await _plan_shot("plan_lot")
	else:
		camera.size = 28.0
		camera.look_at_from_position(Vector3(4, 80, 3), Vector3(4, 0, 3), Vector3(0, 0, -1))
		print("PLAN small centre 4,3 height 28")
		var hidden := _hide_above(3.15)
		await _plan_shot("plan_small_ground")
		for node in hidden:
			node.visible = true
		hidden = _hide_above(6.55)
		await _plan_shot("plan_small_upper")


func _hide_above(height: float) -> Array[Node3D]:
	var hidden: Array[Node3D] = []
	for node in _night.find_children("*", "CSGBox3D", true, false):
		var box := node as CSGBox3D
		if box.visible and box.global_position.y - box.size.y * 0.5 > height:
			box.visible = false
			hidden.append(box)
	return hidden


func _plan_shot(name: String) -> void:
	await _hold(8)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))


## Walks a chain of hops found by `tools/world/map_escape_probe.gd` (`--chain=<report json>`): the
## player is put where each hop began and where the last one landed, with the camera turned the way
## the next hop goes, one PNG each (`chain_<n>.png`).
func _chain_shots() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_chain))
	var via: Array = data["via"]
	var count := 0
	for step: Dictionary in via:
		var from := Vector3(step["from"][0], step["from"][1], step["from"][2])
		var yaw_deg := rad_to_deg(float(step["yaw"]))
		await _visit(["chain_%d_%s" % [count, step["mode"]], from, yaw_deg, -6.0])
		count += 1
	var end := Vector3(data["pos"][0], data["pos"][1], data["pos"][2])
	var last_yaw := rad_to_deg(float(via[via.size() - 1]["yaw"]))
	await _visit(["chain_%d_landing" % count, end, last_yaw, -6.0])
