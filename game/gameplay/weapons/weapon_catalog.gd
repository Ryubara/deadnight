class_name WeaponCatalog
extends RefCounted
## Every weapon the game ships, by id. The ids are listed here, not found by reading the folder,
## because an exported build hides the `.tres` files behind `.remap`.

const DIR := "res://gameplay/weapons/defs/"
const IDS: Array[StringName] = [&"pistol", &"smg", &"shotgun", &"rifle", &"flare_gun", &"crowbar"]


static func get_def(id: StringName) -> WeaponDef:
	return load(DIR + String(id) + ".tres") as WeaponDef


static func all() -> Array[WeaponDef]:
	var defs: Array[WeaponDef] = []
	for id in IDS:
		defs.append(get_def(id))
	return defs
