class_name WeaponHoldMap
extends RefCounted
## Which Soldier weapon class (clips, model and hold: `PlayerAnimation.CLASSES`) a weapon id is held
## as.
## One table, so the catalogue and the animation do not drift apart (docs/design/weapon-hold.md).
## A melee weapon (`WeaponDef.Kind.MELEE`: the crowbar, a bat, a fire axe) is always `Melee`.

## The class of each firearm in the catalogue: the clips it is held with. Its model and size are
## its own hold file (`holds/<id>.tres`, `hold_for`), never a class's.
const CLASS_OF := {
	&"rifle": &"Rifle",
	&"shotgun": &"Shotgun",
	&"smg": &"Rifle",
	&"pistol": &"Pistol",
	&"flare_gun": &"Pistol",
	&"ray_gun": &"Pistol",
	&"freeze_gun": &"Pistol",
}
const MELEE_CLASS := &"Melee"


## The weapon class a weapon id is held as; the default class for an id nobody knows.
static func class_of(weapon_id: StringName) -> StringName:
	var def := WeaponCatalog.get_def(weapon_id) if weapon_id in WeaponCatalog.IDS else null
	if def != null and def.is_melee():
		return MELEE_CLASS
	return CLASS_OF.get(weapon_id, PlayerAnimation.DEFAULT_CLASS)


## The catalogue weapons whose model has not landed (their hold file names it, the glb is not
## there yet): the hand is empty for them, never another weapon's model. Gone from this list the
## moment the glb is in `assets/weapons/`.
static func no_model() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in WeaponCatalog.IDS:
		if hold_for(id) == null:
			ids.append(id)
	return ids


## The hold of a catalogue weapon: its own file `holds/<id>.tres` (its own model, size and grip),
## or null when it has none or its model has not arrived (`WeaponHold.has_model`): the hand
## stays empty rather than showing another weapon's model. A weapon with no file of its own
## is held as its class (`hold_of`), which is how a future bat or axe gets in.
static func hold_for(weapon_id: StringName) -> WeaponHold:
	var path := PlayerAnimation.HOLDS_DIR + String(weapon_id) + ".tres"
	if ResourceLoader.exists(path):
		var own := load(path) as WeaponHold
		return own if own != null and own.has_model() else null
	return PlayerAnimation.hold_of(class_of(weapon_id))
