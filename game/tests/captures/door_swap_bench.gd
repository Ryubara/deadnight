extends Node3D
## The cost of the lot's navigation as a night pays it, in the browser (#335): builds the lot, joins
## the navigation (`DoorNavigation.setup`), then opens every door in turn and records the longest
## frame after each. Two phases: with the saved meshes (what the game does) and with none (every
## mesh baked at run time, what the game did before `LotNavmeshes`). Not part of the game: the
## `tools/web_smoke/door_swap.py` run exports a copy of the project that starts on this scene and
## reads `window.__bench`. Outside a browser it prints the same JSON.

## Frames let go by after each door, long enough for a mesh to reach the map.
const FRAMES_AFTER := 150
## Frames given to the first mesh before it counts as never answering.
const MAP_WAIT := 600
const BAKE_WAIT := 1800

var _frames: Array[float] = []
var _last_usec := 0
var _report: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec != 0:
		_frames.append((now - _last_usec) / 1000.0)
	_last_usec = now


func _run() -> void:
	await get_tree().process_frame
	await _phase("saved", true)
	await _phase("runtime_bake", false)
	var json := JSON.stringify(_report)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__bench = %s;" % json)
	print("BENCH ", json)
	if not OS.has_feature("web"):
		get_tree().quit()


func _phase(label: String, use_saved: bool) -> void:
	var out := {"phase": label}
	var started := Time.get_ticks_usec()
	var shared := LotNavmeshes.shared()
	out["load_res_ms"] = _since(started)
	var lot := (load("res://world/drive_in_greybox.tscn") as PackedScene).instantiate() as Node3D
	add_child(lot)
	for _i in NightWorld.SETTLE_FRAMES:
		await get_tree().physics_frame
	var doors := lot.get_node("Doors") as LotDoors
	var navigation := DoorNavigation.new()
	add_child(navigation)
	navigation.saved = shared if use_saved else null
	started = Time.get_ticks_usec()
	navigation.setup(lot, doors)
	out["setup_ms"] = _since(started)
	out["map_answers_after_frames"] = await _wait_for_the_map(lot)
	for _i in 60:
		await get_tree().process_frame
	var opened: Array[Dictionary] = []
	for door in doors.get_children():
		_frames.clear()
		var before := navigation.bake_count
		started = Time.get_ticks_usec()
		doors.open(StringName(door.get_meta("shop_id")))
		var call_ms := _since(started)
		for _i in FRAMES_AFTER:
			await get_tree().process_frame
		var waited := 0
		while navigation.is_busy() and waited < BAKE_WAIT:
			waited += 1
			await get_tree().process_frame
		(
			opened
			. append(
				{
					"door": door.get_meta("shop_id"),
					"open_call_ms": call_ms,
					"max_frame_ms_after": snappedf(_frames.max(), 0.1),
					"meshes_in_region": navigation.bake_count - before,
				}
			)
		)
	out["doors"] = opened
	_report.append(out)
	lot.queue_free()
	navigation.queue_free()
	await get_tree().process_frame


## Physics frames until the map finds a way between the field's first two spawn points.
func _wait_for_the_map(lot: Node3D) -> int:
	var spawns := lot.get_node("Field/ZombieSpawns").get_children()
	var from := (spawns[0] as Marker3D).global_position
	var to := (spawns[1] as Marker3D).global_position
	for waited in MAP_WAIT:
		var way := NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)
		if not way.is_empty() and way[way.size() - 1].distance_to(to) < NightWorld.NAV_REACHED:
			return waited
		await get_tree().physics_frame
	return MAP_WAIT


func _since(started_usec: int) -> float:
	return snappedf((Time.get_ticks_usec() - started_usec) / 1000.0, 0.1)
