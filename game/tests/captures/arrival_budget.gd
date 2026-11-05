extends Node
## What the helicopter drop costs on a desktop (#1057): the engine's own counts, sampled in each
## physics
## frame of the show and compared with the same night without it. Not part of the game. Run windowed
## (draw calls read 0 headless), one arm to a process so the counts start clean:
##
##     gds godot -- --path game res://tests/captures/arrival_budget.tscn --resolution 960x540
##         -- --map=drive_in --arm=on
## `--arm=` is `off` (no show: the player's own camera on the night), `on` (the show), `nolamp` (the
## show with
## its lamp and haze out, to read what the light costs) or `crowd` (a late join over a crowd: the
## night
## runs 70 s with the player unhurtable, then the show begins over the dead that came for them; it
## prints a
## `BUDGET arm=crowd-view` line for the player's own camera first and the `crowd` line for the
## show). It prints
## one `BUDGET` line: the draw calls, the triangles, the objects, the nodes, the resources and the
## orphans,
## the median and the most over the sampled frames, and what the process holds before, at the most
## and
## after the show (the show must give back what it took).

const SECOND := 60
const SAMPLE_FROM := 30

var _args := NetArgs.new()
var _night: Night
var _rows: Array[Dictionary] = []


func _ready() -> void:
	var map_id := _args.get_string("map") if _args.has("map") else MapRegistry.DEFAULT
	var arm := _args.get_string("arm") if _args.has("arm") else "on"
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 60.0
	tuning.rounds.first_spawn_delay = 600.0
	if arm == "crowd":
		tuning.rounds.intro_seconds = 1.0
		tuning.rounds.first_spawn_delay = 1.0
		tuning.health.max_health = 1000000.0
	_night = Night.new()
	_night.arrival = arm != "off" and arm != "crowd"
	_night.match_settings.map = map_id
	if arm == "crowd":
		_night.match_settings.count_multiplier = 5.0
		_night.match_settings.max_alive = 40
	add_child(_night)
	var before := _counts()
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	var player := _night.player()
	player.local_input = false
	player.capture_mouse = false
	if arm == "crowd":
		await _crowd_view()
	var show := _night.arrival_show
	if show != null:
		show.lamp_enabled = arm != "nolamp"
	await _sample(SECOND * 5 if show == null else int(show.plan.seconds() * SECOND) - 20)
	var peak := _peak()
	if show != null and not show.is_over():
		while not show.is_over():
			await get_tree().physics_frame
	for _i in 3 * SECOND:
		await get_tree().physics_frame
	var after := _counts()
	print(
		(
			(
				"BUDGET map=%s arm=%s frames=%d draws_med=%d draws_max=%d prims_med=%d prims_max=%d "
				+ "objects_before=%d objects_peak=%d objects_after=%d nodes_before=%d nodes_peak=%d "
				+ "nodes_after=%d resources_before=%d resources_after=%d orphans_after=%d"
			)
			% [
				map_id,
				arm,
				_rows.size(),
				_median("draws"),
				_peak_of("draws"),
				_median("prims"),
				_peak_of("prims"),
				before["objects"],
				peak["objects"],
				after["objects"],
				before["nodes"],
				peak["nodes"],
				after["nodes"],
				before["resources"],
				after["resources"],
				after["orphans"],
			]
		)
	)
	Audio.stop_all()
	await Audio.wait_for_mixer()
	get_tree().quit()


## Seventy seconds of night, a look at what the player's camera draws among the dead, and the show
## over them.
func _crowd_view() -> void:
	for _i in 70 * SECOND:
		await get_tree().physics_frame
	await _sample(SECOND)
	print("BUDGET dead=%d" % _night.server.sim.zombies.size())
	print("BUDGET arm=crowd-view draws_med=%d prims_med=%d" % [_median("draws"), _median("prims")])
	_rows.clear()
	NightArrival.begin(_night)


func _sample(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		if i >= SAMPLE_FROM:
			_rows.append(_counts())


func _counts() -> Dictionary:
	return {
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}


func _peak() -> Dictionary:
	var peak := {"objects": 0, "nodes": 0}
	for row in _rows:
		peak["objects"] = maxi(peak["objects"], row["objects"])
		peak["nodes"] = maxi(peak["nodes"], row["nodes"])
	return peak


func _median(key: String) -> int:
	var values: Array[int] = []
	for row in _rows:
		values.append(row[key])
	values.sort()
	return values[values.size() / 2] if not values.is_empty() else 0


func _peak_of(key: String) -> int:
	var most := 0
	for row in _rows:
		most = maxi(most, row[key])
	return most
