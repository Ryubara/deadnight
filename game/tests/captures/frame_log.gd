extends Node
## Frame times through the first seconds of a night on a desktop, with the autopilot firing and the
## dead arriving, to compare with the browser (`tools/web_smoke/first_use.py`). A window is needed:
## a headless run draws nothing. Arguments after `--`: `--warm-up` (warm up before the night, as the
## game does), `--seconds=S` (default 20), `--out=PATH` (a JSON file for the frames).
## Not part of the game.

const SPAWN_DELAY := 0.5
const INTRO_SECONDS := 3.0

var _night: Night
var _args := {}
var _frames: Array[float] = []


func _ready() -> void:
	_args = _parse_args()
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.first_spawn_delay = SPAWN_DELAY
	tuning.rounds.intro_seconds = INTRO_SECONDS
	_night = Night.new()
	_night.warm_up = _args.has("warm-up")
	_night.shoulder_camera = true
	add_child(_night)
	var began := Time.get_ticks_msec()
	await _night.start(Night.Mode.AUTOPILOT, Night.SEED, tuning)
	var loading_ms := Time.get_ticks_msec() - began
	_night.server.rules.apply(RulesAction.skip_break())
	var seconds := float(_args.get("seconds", 20.0))
	var last := Time.get_ticks_usec()
	var end := last + int(seconds * 1_000_000.0)
	while last < end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		_frames.append((now - last) / 1000.0)
		last = now
	_report(loading_ms)
	get_tree().quit()


func _report(loading_ms: int) -> void:
	var ordered := _frames.duplicate()
	ordered.sort()
	var worst: Array = []
	for i in _frames.size():
		worst.append([i, _frames[i]])
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var summary := {
		"warm_up": _args.has("warm-up"),
		"loading_ms": loading_ms,
		"frames": _frames.size(),
		"p50_ms": ordered[ordered.size() / 2],
		"p99_ms": ordered[int(ordered.size() * 0.99)],
		"max_ms": ordered[-1],
		"over_33ms": ordered.filter(func(ms: float) -> bool: return ms > 33.4).size(),
		"worst": worst.slice(0, 8),
		"peak_zombies": _night.server.sim.zombies.size(),
	}
	print("FRAMELOG ", JSON.stringify(summary))
	if _args.has("out"):
		var file := FileAccess.open(String(_args["out"]), FileAccess.WRITE)
		file.store_string(JSON.stringify({"summary": summary, "frames": _frames}))


func _parse_args() -> Dictionary:
	var parsed := {}
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
