class_name LagCompensator
extends RefCounted
## Lag compensation for the server: remembers where every target was, and answers "where were
## they at time T" so a shot is judged against what the shooter saw, not against the present.
##
## Plain data in, plain data out. A frame is `record(time, targets)` with `targets` a list of
## `{"id": int, "pos": Vector3, "yaw": float, "scale": float, "weak": bool}` (`scale`, the size of
## the hit zones, defaults to 1; `weak`, whether it has a weak spot, to false); `rewind(view_time,
## now)` answers `{"time", "rewound_by", "clamped", "targets": {id: {"pos", "yaw", "scale",
## "weak"}}}`. No node, no peer, no clock of its own: `time` is whatever seconds the caller counts
## (the server's tick clock).
##
## The rewind is capped at `max_rewind` seconds, so a laggy or lying client cannot make the server
## judge a shot against the distant past: past the cap, the shot is judged at the cap and the
## shooter leads the target.

const DEFAULT_MAX_REWIND := 0.25
## History kept beyond the cap, so a rewind right at the cap still has a frame before it.
const HISTORY_MARGIN := 0.1

var max_rewind: float = DEFAULT_MAX_REWIND
var _frames: Array[Dictionary] = []


func _init(p_max_rewind: float = DEFAULT_MAX_REWIND) -> void:
	max_rewind = p_max_rewind


func frame_count() -> int:
	return _frames.size()


## Stores where the targets are at `time`. Times must not go backwards.
func record(time: float, targets: Array) -> void:
	var placed: Dictionary[int, Dictionary] = {}
	for target in targets:
		placed[target["id"]] = {
			"pos": target["pos"],
			"yaw": target.get("yaw", 0.0),
			"scale": target.get("scale", 1.0),
			"weak": target.get("weak", false),
		}
	_frames.append({"time": time, "targets": placed})
	var oldest := time - max_rewind - HISTORY_MARGIN
	while _frames.size() > 2 and _frames[1]["time"] < oldest:
		_frames.pop_front()


## The targets as the shooter saw them at `view_time`, clamped to `[now - max_rewind, now]`.
func rewind(view_time: float, now: float) -> Dictionary:
	var used := clampf(view_time, now - max_rewind, now)
	var answer := {
		"time": used,
		"rewound_by": now - used,
		"clamped": not is_equal_approx(used, view_time),
		"targets": {},
	}
	if _frames.is_empty():
		return answer
	answer["targets"] = _at(used)
	return answer


func _at(time: float) -> Dictionary:
	var last := _frames.size() - 1
	if time >= _frames[last]["time"]:
		return _frames[last]["targets"].duplicate()
	if time <= _frames[0]["time"]:
		return _frames[0]["targets"].duplicate()
	for i in range(last, 0, -1):
		var later: Dictionary = _frames[i]
		var earlier: Dictionary = _frames[i - 1]
		if time >= earlier["time"]:
			var span: float = later["time"] - earlier["time"]
			var weight: float = (time - earlier["time"]) / span if span > 0.0 else 1.0
			return _blend(earlier["targets"], later["targets"], weight)
	return _frames[0]["targets"].duplicate()


## Interpolates targets present in both frames; one present in a single frame is not blended (it
## appeared or vanished in between), it is taken from the nearer frame.
func _blend(earlier: Dictionary, later: Dictionary, weight: float) -> Dictionary:
	var blended := {}
	for id in earlier:
		if later.has(id):
			var a: Dictionary = earlier[id]
			var b: Dictionary = later[id]
			blended[id] = {
				"pos": (a["pos"] as Vector3).lerp(b["pos"], weight),
				"yaw": lerp_angle(a["yaw"], b["yaw"], weight),
				"scale": lerpf(a["scale"], b["scale"], weight),
				"weak": b["weak"],
			}
		elif weight < 0.5:
			blended[id] = earlier[id]
	for id in later:
		if not earlier.has(id) and weight >= 0.5:
			blended[id] = later[id]
	return blended
