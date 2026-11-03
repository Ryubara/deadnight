extends Node3D
## What the prize crane costs to build and to draw, alone in front of a camera: the time
## `configure` takes the first time (the models read from disk, as the night's loading does) and the
## second (from the cache, as the warm-up's copy and the night's own crane share them), and the
## draw calls, triangles and objects of a frame in each stage, less the same frame without the
## crane. Prints `CRANE <key> <value>` lines. Not part of the game. Run it windowed through
## `gds godot`: `gds godot -- --path game --resolution 1280x720
## res://tests/captures/crane_cost_bench.tscn`.

const FRAMES := 8

var _camera := Camera3D.new()


func _ready() -> void:
	_camera.position = Vector3(0.0, 1.6, 3.2)
	_camera.rotation.x = -0.05
	add_child(_camera)
	_camera.make_current()
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.4, 0.0)
	add_child(sun)
	var empty := await _frame()
	var tuning := load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning
	var pool: Array[StringName] = tuning.economy.item(&"crane_play").pool
	print("CRANE pool %d" % pool.size())
	var crane := PrizeCrane.new()
	add_child(crane)
	var started := Time.get_ticks_usec()
	crane.configure(tuning.crane, pool)
	print("CRANE configure_first_ms %.1f" % ((Time.get_ticks_usec() - started) / 1000.0))
	var again := PrizeCrane.new()
	add_child(again)
	started = Time.get_ticks_usec()
	again.configure(tuning.crane, pool)
	print("CRANE configure_cached_ms %.1f" % ((Time.get_ticks_usec() - started) / 1000.0))
	again.free()
	var stages := {
		"ready": {"stage": CraneState.Stage.READY},
		"spin": {"stage": CraneState.Stage.SPIN, "left": 2.0},
		"grab": {"stage": CraneState.Stage.GRAB, "left": 8.0, "weapon": String(pool[1])},
		"dud": {"stage": CraneState.Stage.LEAVING, "left": 3.0},
	}
	for stage: String in stages:
		for _i in FRAMES:
			crane.show_state(stages[stage], 1.0 / 60.0)
			await get_tree().process_frame
		var seen := await _frame()
		for key: String in seen:
			print("CRANE %s_%s %d" % [stage, key, seen[key] - empty[key]])
	get_tree().quit()


func _frame() -> Dictionary:
	for _i in 3:
		await RenderingServer.frame_post_draw
	return {
		"draws":
		RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
		),
		"triangles":
		RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
		),
		"objects":
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
	}
