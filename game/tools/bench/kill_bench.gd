class_name KillBench
extends Node
## A night the bot plays, logged frame by frame, to find what a kill costs (`PerfLog`, and
## `tools/web_smoke/kill_spike.py` in a browser). The game starts it instead of the menu when the
## page's address has `?bench` (or the run has `--bench`): the bot fights through the player's
## shoulder camera in a night that comes quickly, with a player who cannot die, for
## `bench_seconds` (default 60), then publishes the log as `window.deadnightPerf` (JSON text) and
## on a desktop prints a line and quits when `--out=PATH` names a file for it. Not part of the play.

const QUERY := "bench"
const FLAG := "--bench"
const NIGHT := "res://ui/screens/night_screen.tscn"
const DEFAULT_SECONDS := 60.0
## The bot's night is quick: dead arrive at once and break seconds are short.
const FIRST_SPAWN_DELAY := 0.5
const INTRO_SECONDS := 2.0
const BREAK_SECONDS := 3.0
const SPAWN_INTERVAL := 0.6
const SPAWN_INTERVAL_MIN := 0.4
## Enough dead, and quick enough, for forty kills in a minute.
const FIRST_ROUND_COUNT := 30.0
const WALK_SPEED := 3.2
const ALIVE_CAP := 24.0
const PLAYER_HEALTH := 1.0e6

var log := PerfLog.new()

var _running_since := -1.0
var _seconds := DEFAULT_SECONDS
var _out := ""
var _done := false
var _fights_only := false


## Whether this run asked for the bench.
static func requested() -> bool:
	if FLAG in OS.get_cmdline_user_args() or FLAG in OS.get_cmdline_args():
		return true
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		return search is String and QUERY in (search as String)
	return false


## The night the bench plays: quick and with a player who does not die.
static func tuning() -> RulesTuning:
	var rules: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	rules.rounds.first_spawn_delay = FIRST_SPAWN_DELAY
	rules.rounds.intro_seconds = INTRO_SECONDS
	rules.rounds.break_seconds = BREAK_SECONDS
	rules.rounds.spawn_interval_start = SPAWN_INTERVAL
	rules.rounds.spawn_interval_min = SPAWN_INTERVAL_MIN
	rules.rounds.count_base = FIRST_ROUND_COUNT
	rules.rounds.speed_base = WALK_SPEED
	rules.rounds.alive_cap_start = ALIVE_CAP
	rules.health.max_health = PLAYER_HEALTH
	return rules


func _ready() -> void:
	add_child(log)
	_read_arguments()
	NightScreen.start_mode = Night.Mode.AUTOPILOT
	NightScreen.start_tuning = tuning()
	NightScreen.shoulder_camera = true
	UIRouter.reset(NIGHT, UITransition.Kind.CUT)


func _process(_delta: float) -> void:
	var night := _night()
	if _done or night == null or not night.running:
		return
	if not _fights_only:
		_fights_only = true
		_leave_the_shopping(night.autopilot)
	if _since_running() < _seconds:
		return
	_done = true
	_publish(night)


func _night() -> Night:
	var screen := UIRouter.top() as NightScreen
	return screen.night if screen != null else null


## Seconds the night has been running (the log's clock, so the loading is not counted).
func _since_running() -> float:
	if _running_since < 0.0:
		_running_since = log.seconds()
	return log.seconds() - _running_since


## The bot buys no door and no weapon, so what the log shows is the cost of shooting and killing
## (a door starts a navigation bake, which is another cost, measured elsewhere). It still keeps the
## lamps and the tank, as a player does.
func _leave_the_shopping(bot: Autopilot) -> void:
	bot.order.clear()
	bot.wanted.clear()
	bot.spots.clear()


func _read_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2 and parts[0] == "seconds":
			_seconds = float(parts[1])
		elif parts.size() == 2 and parts[0] == "out":
			_out = parts[1]
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		for part in String(search).trim_prefix("?").split("&"):
			if part.begins_with("bench_seconds="):
				_seconds = float(part.get_slice("=", 1))


func _publish(night: Night) -> void:
	var report := {
		"kills": night.state.kills,
		"round": night.state.round_number(),
		"started_at": _running_since,
		"page_origin_ms": log.page_origin_ms,
		"rows": log.rows,
	}
	var json := JSON.stringify(report)
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").deadnightPerf = json
	elif _out != "":
		var file := FileAccess.open(_out, FileAccess.WRITE)
		file.store_string(json)
		file.close()
		get_tree().quit()
