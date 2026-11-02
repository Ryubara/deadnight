class_name ClipEvents
extends RefCounted
## The event frames of the soldier's clips (`clips.json`, written by the build script): a reload's
## magazine-out and magazine-in, the lever, the shells. The player's animation emits them as the
## clip plays; the sounds read the same frames, so a step sounds on the frame it is drawn.

const SPEC := "res://assets/characters/soldier/clips.json"

static var _spec: Dictionary = {}


static func fps() -> float:
	return float(_load()["fps"])


## Seconds into `clip` at which `event` happens, one entry per frame it is listed at (a clip may
## list an event more than once, as the rifle's three rounds); empty for an unknown event.
static func times(clip: StringName, event: StringName) -> Array[float]:
	var found: Array[float] = []
	var events: Dictionary = _load()["clips"].get(String(clip), {}).get("events", {})
	if not events.has(String(event)):
		return found
	var frames: Variant = events[String(event)]
	for frame: float in frames if frames is Array else [frames]:
		found.append(frame / fps())
	return found


## Seconds the clip runs, as written in the spec (0 for an unknown clip).
static func length(clip: StringName) -> float:
	return float(_load()["clips"].get(String(clip), {}).get("seconds", 0.0))


static func _load() -> Dictionary:
	if _spec.is_empty():
		_spec = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	return _spec
