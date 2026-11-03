class_name ElementCatalog
extends RefCounted
## Every element the game ships, by id. Listed here, not found by reading the folder, because an
## exported build hides the `.tres` files behind `.remap` (as `WeaponCatalog` does).

const DIR := "res://gameplay/weapons/elements/defs/"
const IDS: Array[StringName] = [&"explosive", &"shock", &"ground_fire"]

static var _cache: Dictionary[StringName, ElementDef] = {}


## The element called `id`, or null for none or one no build knows.
static func get_def(id: StringName) -> ElementDef:
	if not IDS.has(id):
		return null
	if not _cache.has(id):
		_cache[id] = load(DIR + String(id) + ".tres") as ElementDef
	return _cache[id]
