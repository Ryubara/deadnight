class_name UpgradeTuning
extends Resource
## What a tune-up does to a weapon. The shop sells it as the item `upgrade_weapon` (the price is
## the item's, like every price); the machine in the lot (`docs/design/upgrades.md`) is where a
## player buys it for the weapon in hand. The numbers here are what `WeaponDef.upgraded` applies,
## in the combat server and in the balance simulator alike.

## The weapons that can be tuned up, by catalogue id. A melee weapon has no magazine to grow.
@export var weapons: Array[StringName] = [&"pistol", &"smg", &"shotgun", &"rifle", &"flare_gun"]
## Added to the item's price for each weapon the buyer has already tuned up, so the first is
## the bargain and a bench full of tuned weapons is a rich player's.
@export var price_step: int = 1500
## Damage of a hit (every pellet, the flare gun's blast too) is multiplied by this.
@export var damage_multiplier: float = 1.75
## The magazine and the most rounds a reserve holds are multiplied by these (rounded up), and the
## tune-up fills both.
@export var magazine_multiplier: float = 1.5
@export var reserve_multiplier: float = 1.5
## Put before the weapon's name once it is tuned up ("Tuned Revolver").
@export var name_prefix: String = "Tuned "


## Whether a weapon (a catalogue id, not a shop id) can be tuned up.
func allows(weapon_id: StringName) -> bool:
	return weapons.has(weapon_id)
