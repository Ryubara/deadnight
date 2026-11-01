class_name NetArgs
extends RefCounted
## Options given after `--` on the command line: `--server`, `--port=8910`, `--bot`, `--seed=3`.
## On the web there is no command line: the page address supplies them (`?bot-seed=3&url=wss://h`).

## Not 9080: the Godot editor MCP bridge listens there on the maintainer machine.
const DEFAULT_PORT := 8910

var _values: Dictionary[String, String] = {}


func _init(args: PackedStringArray = OS.get_cmdline_user_args()) -> void:
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search")
		for pair in str(search).trim_prefix("?").split("&", false):
			var kv := pair.split("=", true, 1)
			_values[kv[0]] = kv[1].uri_decode() if kv.size() > 1 else "true"
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_values[parts[0]] = parts[1] if parts.size() > 1 else "true"


func has(key: String) -> bool:
	return _values.has(key)


func get_string(key: String, fallback: String = "") -> String:
	return _values.get(key, fallback)


func get_int(key: String, fallback: int = 0) -> int:
	return int(_values[key]) if _values.has(key) else fallback


func get_float(key: String, fallback: float = 0.0) -> float:
	return float(_values[key]) if _values.has(key) else fallback
