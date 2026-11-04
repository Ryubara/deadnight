class_name UpgradeTuning
extends Resource
## What the re-cut costs and what it does to each weapon. The shop sells it as the item
## `upgrade_weapon` (the price is the item's, like every price: 5,000 flat, whoever buys it and
## however many weapons they have re-cut, #909); the machine in the lot
## (`docs/design/upgrades.md`) is where a player buys it for the weapon in hand. What a re-cut does
## is one `RecutProfile` per weapon (`profiles`): its numbers, its name and, for the weakest guns,
## its element. `WeaponDef.upgraded` applies it in the combat server and in the balance simulator
## alike.

const DEFAULT_TUNING_PATH := "res://gameplay/rules/default_tuning.tres"

## One profile for every weapon that can be re-cut, found by `RecutProfile.weapon`. A weapon with no
## profile cannot be re-cut: the melee weapons have no magazine to grow, and a new firearm is not
## re-cut until it has a row here.
@export var profiles: Array[RecutProfile] = []
## Put before the name of a re-cut weapon whose profile gives none ("Re-Cut Revolver").
@export var name_prefix: String = "Re-Cut "


## The shipped table (`default_tuning.tres`), for code that has no rules to ask.
static func shipped() -> UpgradeTuning:
	return (load(DEFAULT_TUNING_PATH) as RulesTuning).upgrade


## Whether a weapon (a catalogue id, not a shop id) can be re-cut.
func allows(weapon_id: StringName) -> bool:
	return profile_of(weapon_id) != null


## The profile of a weapon, or null when it cannot be re-cut.
func profile_of(weapon_id: StringName) -> RecutProfile:
	for profile in profiles:
		if profile.weapon == weapon_id:
			return profile
	return null


## The weapons of the catalogue that can be re-cut (a profile for a weapon not yet in the
## catalogue is not listed: nothing can hold it).
func catalogue_weapon_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for def in WeaponCatalog.all():
		if allows(def.id):
			ids.append(def.id)
	return ids


## The catalogue ids of every weapon that can be re-cut.
func weapon_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for profile in profiles:
		ids.append(profile.weapon)
	return ids
