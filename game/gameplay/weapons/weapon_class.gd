class_name WeaponClass
extends RefCounted
## What kind of gun a weapon is (#972). A class is the weapon's job and the yardstick it is judged
## by: `WeaponClassTargets` states, for each class, the pulls and seconds a walker of a round takes,
## the bodies a shot passes and the rounds it carries, and a test fails when a weapon leaves its
## class's band. The class of a weapon is on its definition (`WeaponDef.weapon_class`).

enum Id {
	STARTER_PISTOL,
	PISTOL,
	SMG,
	SHOTGUN,
	RIFLE,
	LMG,
	SNIPER,
	SPECIAL,
	MELEE,
}

## The name the audit table and the targets file use for each class.
const KEYS: Dictionary[Id, StringName] = {
	Id.STARTER_PISTOL: &"starter_pistol",
	Id.PISTOL: &"pistol",
	Id.SMG: &"smg",
	Id.SHOTGUN: &"shotgun",
	Id.RIFLE: &"rifle",
	Id.LMG: &"lmg",
	Id.SNIPER: &"sniper",
	Id.SPECIAL: &"special",
	Id.MELEE: &"melee",
}

const TITLES: Dictionary[Id, String] = {
	Id.STARTER_PISTOL: "Starter pistol",
	Id.PISTOL: "Pistols",
	Id.SMG: "SMGs",
	Id.SHOTGUN: "Shotguns",
	Id.RIFLE: "Rifles",
	Id.LMG: "LMG",
	Id.SNIPER: "Snipers",
	Id.SPECIAL: "Specials",
	Id.MELEE: "Melee",
}


static func key(id: Id) -> StringName:
	return KEYS[id]


static func title(id: Id) -> String:
	return TITLES[id]


## The class named by `key` (`smg`), or -1 when there is none.
static func from_key(name: StringName) -> int:
	for id: Id in KEYS:
		if KEYS[id] == name:
			return id
	return -1


## Every class, in the order of the enum.
static func all() -> Array[Id]:
	var ids: Array[Id] = []
	for id: Id in KEYS:
		ids.append(id)
	return ids
