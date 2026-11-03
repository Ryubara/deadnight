class_name UpgradeTuning
extends Resource
## What a re-cut does to a weapon. The shop sells it as the item `upgrade_weapon` (the price is
## the item's, like every price); the machine in the lot (`docs/design/upgrades.md`) is where a
## player buys it for the weapon in hand. The numbers here are what `WeaponDef.upgraded` applies,
## in the combat server and in the balance simulator alike.

## The weapons that can be re-cut, by catalogue id. A melee weapon has no magazine to grow.
@export var weapons: Array[StringName] = [
	&"pistol",
	&"smg",
	&"shotgun",
	&"rifle",
	&"flare_gun",
	&"mp5",
	&"ppsh",
	&"m4a1",
	&"m249",
	&"fifty_cal",
	&"pump_870",
]
## Added to the item's price for each weapon the buyer has already re-cut, so the first is
## the bargain and a bench full of re-cut weapons is a rich player's.
@export_range(0, 10000, 50, "or_greater", "suffix:pts") var price_step: int = 1500
## Damage of a hit (every pellet, the flare gun's blast too) is multiplied by this.
@export_range(0.1, 10.0, 0.05, "or_greater", "suffix:x") var damage_multiplier: float = 1.75
## The magazine and the most rounds a reserve holds are multiplied by these (rounded up), and the
## re-cut fills both.
@export_range(0.1, 10.0, 0.05, "or_greater", "suffix:x") var magazine_multiplier: float = 1.5
@export_range(0.1, 10.0, 0.05, "or_greater", "suffix:x") var reserve_multiplier: float = 1.5
## Put before the weapon's name once it is re-cut ("Re-Cut Revolver").
@export var name_prefix: String = "Re-Cut "


## Whether a weapon (a catalogue id, not a shop id) can be re-cut.
func allows(weapon_id: StringName) -> bool:
	return weapons.has(weapon_id)
