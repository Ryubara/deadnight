class_name LagCompensator
extends RefCounted
## Lag compensation for the server: remembers where every target was, and answers "where were
## they at time T" so a shot is judged against what the shooter saw, not against the present.
##
## Plain data in, plain data out. A frame is `record(time, targets)` with `targets` a list of
## `{"id": int, "pos": Vector3, "yaw": float, "scale": float, "weak": bool, "pose": StringName}`
## (`scale`, the size of the hit zones, defaults to 1; `weak`, whether it has a weak spot, to false;
## `pose`, the id of its hit set, to `Hitbox.DEFAULT_SET`); `rewind(view_time, now)` answers
## `{"time", "rewound_by", "clamped", "targets": {id: {"pos", "yaw", "scale", "weak", "pose"}}}`.
## No node, no peer, no clock of its own: `time` is whatever seconds the caller counts
## (the server's tick clock).
##
## The rewind is capped at `max_rewind` seconds, so a laggy or lying client cannot make the server
## judge a shot against the distant past: past the cap, the shot is judged at the cap and the
## shooter leads the target.

const DEFAULT_MAX_REWIND := 0.25
## History kept beyond the cap, so a rewind right at the cap still has a frame before it.
const HISTORY_MARGIN := 0.1
const PLACED_KEYS: Array[String] = ["pos", "yaw", "scale", "weak", "pose"]

var max_rewind: float = DEFAULT_MAX_REWIND
var _frames: Array[Dictionary] = []


func _init(p_max_rewind: float = DEFAULT_MAX_REWIND) -> void:
	max_rewind = p_max_rewind


func frame_count() -> int:
	return _frames.size()


## Stores where the targets are at `time`. Times must not go backwards.
func record(time: float, targets: Array) -> void:
	var at: Dictionary[int, Dictionary] = {}
	for target in targets:
		at[target["id"]] = placed(target)
	_frames.append({"time": time, "targets": at})
	_trim(time)


func _trim(time: float) -> void:
	var oldest := time - max_rewind - HISTORY_MARGIN
	while _frames.size() > 2 and _frames[1]["time"] < oldest:
		_frames.pop_front()


## Stores the frame of the last `record` again at `time`: the targets have not changed. The frames
## share one table (nothing writes to a frame; `rewind` copies), so a tick with nothing new costs
## no table. Does nothing before the first `record`.
func record_again(time: float) -> void:
	if _frames.is_empty():
		return
	_frames.append({"time": time, "targets": _frames[_frames.size() - 1]["targets"]})
	_trim(time)


## A target as the history keeps it: `{"pos", "yaw", "scale", "weak", "pose"}` with the defaults
## filled in. A target that has all five is kept as it is (nothing writes to one, and the server
## hands over a new one for each zombie at every tick: copying each twice was most of the cost of
## the list).
static func placed(target: Dictionary) -> Dictionary:
	if target.has_all(PLACED_KEYS):
		return target
	return {
		"pos": target["pos"],
		"yaw": target.get("yaw", 0.0),
		"scale": target.get("scale", 1.0),
		"weak": target.get("weak", false),
		"pose": target.get("pose", Hitbox.DEFAULT_SET),
	}


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
				"pose": b["pose"],
			}
		elif weight < 0.5:
			blended[id] = earlier[id]
	for id in later:
		if not earlier.has(id) and weight >= 0.5:
			blended[id] = later[id]
	return blended
