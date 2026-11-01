class_name WeaponHoldMap
extends RefCounted
## Which Soldier weapon class (clips, model and hold: `PlayerAnimation.CLASSES`) a weapon id is held
## as.
## One table, so the catalogue and the animation do not drift apart (docs/design/weapon-hold.md).
## A melee weapon (`WeaponDef.Kind.MELEE`: the crowbar, a bat, a fire axe) is always `Melee`.

## The class of each firearm in the catalogue. The ids in `NO_MODEL` have no model of their own
## yet and borrow the nearest class: the SMG the lever rifle's, the pistol and the flare gun the
## one-handed Pistol class (its clips; the hand stays empty until the model exists).
const CLASS_OF := {
	&"rifle": &"Rifle",
	&"shotgun": &"Shotgun",
	&"smg": &"Rifle",
	&"pistol": &"Pistol",
	&"flare_gun": &"Pistol",
}
## The weapons shown with a class that is not theirs, or with no model at all: listed here and
## in the docs, and gone from the list when their model and hold file land.
const NO_MODEL: Array[StringName] = [&"pistol", &"smg", &"flare_gun"]
const MELEE_CLASS := &"Melee"


## The weapon class a weapon id is held as; the default class for an id nobody knows.
static func class_of(weapon_id: StringName) -> StringName:
	var def := WeaponCatalog.get_def(weapon_id) if weapon_id in WeaponCatalog.IDS else null
	if def != null and def.is_melee():
		return MELEE_CLASS
	return CLASS_OF.get(weapon_id, PlayerAnimation.DEFAULT_CLASS)
