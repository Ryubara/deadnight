class_name NetArgs
extends RefCounted
## Options given after `--` on the command line, as `--server`, `--port 8910` or `--port=8910`,
## `--connect ws://host:8910`. On the web there is no command line: the page address supplies them
## (`index.html?connect=wss://host`).
##
## A word after a `--key` that does not itself start with `--` is its value.

var _values: Dictionary[String, String] = {}


func _init(args: PackedStringArray = OS.get_cmdline_user_args()) -> void:
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search")
		for pair in str(search).trim_prefix("?").split("&", false):
			var kv := pair.split("=", true, 1)
			_values[kv[0]] = kv[1].uri_decode() if kv.size() > 1 else "true"
	var i := 0
	while i < args.size():
		var arg := args[i]
		i += 1
		if not arg.begins_with("--"):
			continue
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() > 1:
			_values[parts[0]] = parts[1]
		elif i < args.size() and not args[i].begins_with("--"):
			_values[parts[0]] = args[i]
			i += 1
		else:
			_values[parts[0]] = "true"


func has(key: String) -> bool:
	return _values.has(key)


func get_string(key: String, fallback: String = "") -> String:
	return _values.get(key, fallback)


func get_int(key: String, fallback: int = 0) -> int:
	return int(_values[key]) if _values.has(key) else fallback


func get_float(key: String, fallback: float = 0.0) -> float:
	return float(_values[key]) if _values.has(key) else fallback


## The match settings a game server is started with, one option for each setting of
## `MatchSettings.KEYS` (each left out is the default): `--count 2`, `--max-alive 12`, `--break 10`,
## `--map small_indoor`, `--bots 2`, `--bot-skill 2`, `--perk-limit 1`. Not pulled into bounds: the
## caller asks `MatchSettings.problem` of the result and stops on a value the game does not take,
## instead of starting a night with other rules than the ones asked for (Deadnight #944).
func match_settings() -> MatchSettings:
	var settings := MatchSettings.new()
	settings.count_multiplier = get_float("count", settings.count_multiplier)
	settings.max_alive = get_int("max-alive", settings.max_alive)
	settings.break_seconds = get_float("break", settings.break_seconds)
	settings.map = get_string("map", settings.map)
	settings.bots = get_int("bots", settings.bots)
	settings.bot_skill = get_int("bot-skill", settings.bot_skill)
	settings.perk_limit = get_int("perk-limit", settings.perk_limit)
	return settings
