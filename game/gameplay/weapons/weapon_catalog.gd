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
	&"mp5",
	&"ppsh",
	&"m4a1",
	&"m249",
	&"fifty_cal",
	&"pump_870",
]

## The weapon every player starts the night with.
const START_WEAPON := &"pistol"

## The blow every player has on its own button (#411): a knife-like swing with whatever is in hand.
## It is a definition like the others (`defs/quick_melee.tres`, the server's sweep and cooldown) but
## it is not a weapon: nobody carries, buys or is given it, so it is not in `IDS`.
const QUICK_MELEE := &"quick_melee"

## How many weapons a player carries at once (#410): a third replaces the one in hand. There is
## no melee slot; a melee weapon takes one of the two like a gun.
const CARRY_LIMIT := 2

## The shop sells weapons as `weapon_<id>` (the crane's pool too); the catalogue knows `<id>`.
const SHOP_PREFIX := "weapon_"

static var _re_cut: Dictionary[StringName, WeaponDef] = {}


## The catalogue id behind a shop or crane id (`weapon_rifle`), or the id itself (`rifle`).
static func catalog_id(shop_or_catalog_id: StringName) -> StringName:
	return StringName(String(shop_or_catalog_id).trim_prefix(SHOP_PREFIX))


static func get_def(id: StringName) -> WeaponDef:
	return load(DIR + String(id) + ".tres") as WeaponDef


## The weapon as its carrier has it: the shipped one at tier 0, and at a higher tier its re-cut by
## the shipped table (`WeaponDef.upgraded`), made once. What the bots value and fire by, so a
## re-cut revolver is judged by its new hit and its slower rate, not by the plain one's.
static func get_def_at(id: StringName, tier: int) -> WeaponDef:
	var plain := get_def(id)
	if tier <= 0 or plain == null:
		return plain
	if not _re_cut.has(id):
		_re_cut[id] = plain.upgraded(UpgradeTuning.shipped())
	return _re_cut[id]


## The quick melee's definition (`QUICK_MELEE`).
static func quick_melee() -> WeaponDef:
	return get_def(QUICK_MELEE)


static func all() -> Array[WeaponDef]:
	var defs: Array[WeaponDef] = []
	for id in IDS:
		defs.append(get_def(id))
	return defs
