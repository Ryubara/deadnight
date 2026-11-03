extends Node
## The generator in its cage (#853) from the player's shoulder camera, in the real night: from the
## yard's gate and from the midway link (the two places it must read from), from each side up
## close, and from the gate again in the brown-out and dry. Not part of the game. Each spot saves a
## PNG and prints `DRAWS <spot> <draw calls> <primitives> <objects>` from the renderer, so a change
## to the generator can be measured against the budget (#728) at the same views. Run with a window
## (through `gds godot`, not headless):
##
##     gds godot -- --path game res://tests/captures/generator_views.tscn --resolution 1280x720 \
##         -- --out=<abs folder>

const SEED := 5
## Ticks after a spot is set, and the frames the renderer is given, before the shot.
const SETTLE_TICKS := 6
const SETTLE_FRAMES := 4
## Where the player stands (lot metres), the camera's yaw and pitch (degrees; yaw 0 looks at the
## screen, -z; 180 at the road, +z; -90 east, +x) and the tank (fraction of capacity, -1 leaves it).
const SPOTS := [
	{"name": "1_gate", "at": Vector3(40, 0, 1.0), "yaw": 180.0, "pitch": 4.0},
	{"name": "2_midway_link", "at": Vector3(20, 0, 17), "yaw": -90.0, "pitch": 4.0},
	{"name": "3_north_close", "at": Vector3(40, 0, 8), "yaw": 180.0, "pitch": 6.0},
	{"name": "4_west_opening", "at": Vector3(30, 0, 18), "yaw": -90.0, "pitch": 4.0},
	{"name": "5_south", "at": Vector3(40, 0, 29), "yaw": 0.0, "pitch": 6.0},
	{"name": "6_east_opening", "at": Vector3(51, 0, 18), "yaw": 90.0, "pitch": 4.0},
	{"name": "7_inside", "at": Vector3(37.2, 0, 18), "yaw": -90.0, "pitch": -4.0},
	{
		"name": "8_gate_brownout",
		"at": Vector3(40, 0, 1.0),
		"yaw": 180.0,
		"pitch": 4.0,
		"fuel": 0.05
	},
	{"name": "9_gate_dry", "at": Vector3(40, 0, 1.0), "yaw": 180.0, "pitch": 4.0, "fuel": 0.0},
]

var _night: Night
var _out := "user://generator_views"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_night = Night.new()
	add_child(_night)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	# No dead in the shots: the first wave waits past the end of the tour.
	tuning.rounds.first_spawn_delay = 600.0
	await _night.start(Night.Mode.MANUAL, SEED, tuning)
	var rules := _night.server.rules
	var fuel: FuelTuning = rules.tuning.fuel
	for spot: Dictionary in SPOTS:
		var share: float = spot.get("fuel", -1.0)
		if share >= 0.0:
			# The dry tank keeps a crumb so the next tick empties it through the rules (the events).
			rules.generator.fuel = maxf(fuel.capacity * share, 0.001)
		for _i in SETTLE_TICKS + (40 if share == 0.0 else 0):
			_pose(spot)
			_night.tick()
		for _i in SETTLE_FRAMES:
			_pose(spot)
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s/%s.png" % [_out, spot["name"]])
		print(
			(
				"DRAWS %s %d %d %d"
				% [
					spot["name"],
					RenderingServer.get_rendering_info(
						RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
					),
					RenderingServer.get_rendering_info(
						RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
					),
					RenderingServer.get_rendering_info(
						RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
					),
				]
			)
		)
	get_tree().quit()


func _pose(spot: Dictionary) -> void:
	var player := _night.player()
	player.teleport(spot["at"])
	# The body faces the way the camera looks, so it stands with its back to the shot.
	player.state.facing = deg_to_rad(spot["yaw"])
	player.rotation.y = player.state.facing
	player.camera_rig.yaw = deg_to_rad(spot["yaw"])
	player.camera_rig.pitch = deg_to_rad(spot["pitch"])
