class_name MapRegistry
extends RefCounted
## The maps there are. The night loads the map the match settings name from here (`NightWorld`),
## the picker lists them (`MapPicker`), and the settings, the backend's lobby and a ticket carry
## only the id. The drive-in lot is the one shipped map; the small indoor map is listed, not
## shipped, so its card is locked until its scene lands (a line in its resource: `shipped` and
## `scene_path`). A test puts its own list in with `use` and puts the real one back with `reset`.

## The map every night had before there was a choice; what a settings dictionary without a `map`
## means.
const DEFAULT := "drive_in"
## The map resources, in the order the picker shows them.
const PATHS: Array[String] = [
	"res://world/maps/drive_in.tres",
	"res://world/maps/small_indoor.tres",
]

## The levels kept for the third and fourth maps when they exist (a map is a `.tres` with its own
## `unlock_level`; these are the rungs the design page holds for them, docs/design/maps.md).
const RESERVED_UNLOCKS: Array[int] = [25, 40]

static var _maps: Array[MapInfo] = []


## Every map, shipped or not, in the order of the picker.
static func all() -> Array[MapInfo]:
	if _maps.is_empty():
		for path in PATHS:
			_maps.append(load(path) as MapInfo)
	return _maps


## The maps a night can be played on.
static func playable() -> Array[MapInfo]:
	var out: Array[MapInfo] = []
	for info in all():
		if info.is_playable():
			out.append(info)
	return out


## The map called `id`, or null.
static func find(id: String) -> MapInfo:
	for info in all():
		if info.id == id:
			return info
	return null


## Whether `id` names a map a night can be played on.
static func is_playable(id: String) -> bool:
	var info := find(id)
	return info != null and info.is_playable()


## Whether `id` is a map a night can be played on that an account of `level` may choose for a night
## it hosts: it is playable and the level opens it.
static func is_open(id: String, level: int) -> bool:
	var info := find(id)
	return info != null and info.is_playable() and info.is_open_at(level)


## The maps a host of `level` is offered, in the picker's order.
static func open_at(level: int) -> Array[MapInfo]:
	var out: Array[MapInfo] = []
	for info in playable():
		if info.is_open_at(level):
			out.append(info)
	return out


## `id` when a host of `level` may choose it, else the default map's id: a lobby whose host is below
## a map's level does not offer it (the maintainer decided the host's level picks, 2026-11-04).
static func fit_host(id: String, level: int) -> String:
	return id if is_open(id, level) else DEFAULT


## The map called `id`; the default map for an id nobody knows (a night never fails to load).
static func of(id: String) -> MapInfo:
	var info := find(id)
	return info if info != null and info.is_playable() else default_map()


static func default_map() -> MapInfo:
	return find(DEFAULT)


## The map a lobby or a preview from the backend says it is on: the `map` of its settings, else
## the `map` the preview names, else the default.
static func of_lobby(held: Dictionary) -> MapInfo:
	var settings: Variant = held.get("settings")
	if typeof(settings) == TYPE_DICTIONARY and (settings as Dictionary).has("map"):
		return of(str((settings as Dictionary)["map"]))
	return of(str(held.get("map", DEFAULT)))


## Replaces the list (a test's second map). `reset` brings the real one back.
static func use(list: Array[MapInfo]) -> void:
	_maps = list


static func reset() -> void:
	_maps = []
