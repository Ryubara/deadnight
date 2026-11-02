class_name WeaponCatalog
extends RefCounted
## Every weapon the game ships, by id. The ids are listed here, not found by reading the folder,
## because an exported build hides the `.tres` files behind `.remap`.

const DIR := "res://gameplay/weapons/defs/"
const IDS: Array[StringName] = [
	&"pistol",
	&"smg",
	&"shotgun",
	&"rifle",
	&"flare_gun",
	&"crowbar",
	&"baseball_bat",
	&"fire_axe",
]

## How many weapons a player carries at once (#410): a third replaces the one in hand. There is
## no melee slot; a melee weapon takes one of the two like a gun.
const CARRY_LIMIT := 2

## The shop sells weapons as `weapon_<id>` (the crane's pool too); the catalogue knows `<id>`.
const SHOP_PREFIX := "weapon_"


## The catalogue id behind a shop or crane id (`weapon_rifle`), or the id itself (`rifle`).
static func catalog_id(shop_or_catalog_id: StringName) -> StringName:
	return StringName(String(shop_or_catalog_id).trim_prefix(SHOP_PREFIX))


static func get_def(id: StringName) -> WeaponDef:
	return load(DIR + String(id) + ".tres") as WeaponDef


static func all() -> Array[WeaponDef]:
	var defs: Array[WeaponDef] = []
	for id in IDS:
		defs.append(get_def(id))
	return defs
