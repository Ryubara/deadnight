class_name ErrorCatcher
extends Logger
## Collects the errors the engine prints while it is installed, so a test can say "nothing was
## printed" (a navigation query before the map had synchronised prints an error and the test run
## goes on). `start()` before, `stop()` after; `lines` holds the message of each error.

var lines: Array[String] = []
var _active := false


func start() -> void:
	if not _active:
		_active = true
		OS.add_logger(self)


func stop() -> void:
	if _active:
		_active = false
		OS.remove_logger(self)


func _log_error(
	function: String,
	_file: String,
	_line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	_error_type: int,
	_script_backtraces: Array[ScriptBacktrace]
) -> void:
	lines.append("%s: %s %s" % [function, code, rationale])
