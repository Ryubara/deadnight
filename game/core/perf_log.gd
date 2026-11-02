class_name PerfLog
extends Node
## A log of every frame for a measuring run (`KillBench`, `tools/web_smoke/kill_spike.py`): when it
## was, the time since the frame before, how many objects, resources and nodes existed, and what
## `PerfProbe` timed and counted in it. Off in the game.
##
## Rows: `{"t", "dt", "objects", "resources", "nodes", "orphans", "usec", "counts"}`, times in
## milliseconds (`usec` in microseconds).

var rows: Array[Dictionary] = []
## On the web: the page's clock (`performance.now()`, milliseconds) at the first row, to line the
## rows up with what the page records itself.
var page_origin_ms := 0.0

var _started := 0
var _last := 0


func _init() -> void:
	# After every other node's `_process`, so the probes of a frame are whole when they are taken.
	process_priority = 1 << 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	PerfProbe.enabled = true
	PerfProbe.take()


func _exit_tree() -> void:
	PerfProbe.enabled = false


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _started == 0:
		_started = now
		_last = now
		if OS.has_feature("web"):
			page_origin_ms = float(JavaScriptBridge.eval("performance.now()", true))
	var taken := PerfProbe.take()
	(
		rows
		. append(
			{
				"t": snappedf((now - _started) / 1000.0, 0.01),
				"dt": snappedf((now - _last) / 1000.0, 0.01),
				"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
				"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
				"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
				"usec": taken["usec"],
				"counts": taken["counts"],
			}
		)
	)
	_last = now


## Seconds since the first frame.
func seconds() -> float:
	return (Time.get_ticks_usec() - _started) / 1_000_000.0 if _started != 0 else 0.0


## The rows as JSON.
func to_json() -> String:
	return JSON.stringify(rows)
