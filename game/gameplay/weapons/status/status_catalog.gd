class_name StatusCatalog
extends RefCounted
## Every status effect the game ships, by id. Listed here, not found by reading the folder, because
## an exported build hides the `.tres` files behind `.remap` (as `WeaponCatalog` does).

const DIR := "res://gameplay/weapons/status/defs/"
const IDS: Array[StringName] = [&"frozen", &"chilled", &"burning"]

static var _cache: Dictionary[StringName, StatusDef] = {}


static func get_def(id: StringName) -> StatusDef:
	if not _cache.has(id):
		_cache[id] = load(DIR + String(id) + ".tres") as StatusDef
	return _cache[id]


## The status a snapshot's wire id means, or null for none (0) or an id no build knows.
static func by_wire(wire: int) -> StatusDef:
	if wire == StatusDef.NONE:
		return null
	for id in IDS:
		var def := get_def(id)
		if def.wire == wire:
			return def
	return null
