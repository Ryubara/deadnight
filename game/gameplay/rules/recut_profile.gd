class_name RecutProfile
extends Resource
## What one weapon becomes when it is re-cut at the bench: its own numbers, its own name and, for
## the weakest guns, its element (`ElementDef`). The table is `UpgradeTuning.profiles`; the plan and
## the reasons for each row are in docs/design/upgrades.md (#785). `WeaponDef.upgraded` applies a
## profile in the combat server and in the balance simulator alike, so a weapon the table lists is
## re-cut the same everywhere, and a weapon it does not list cannot be re-cut at all.

## The catalogue id of the weapon (`pistol`, not `weapon_pistol`).
@export var weapon: StringName = &""
## The name the weapon carries once re-cut, on the card, the feed and the bench. Empty: the tuning's
## prefix before its own name ("Re-Cut Revolver"), for a weapon whose display name is not settled.
@export var recut_name: String = ""

@export_group("Numbers")
## Damage of a hit (every pellet, a blast too) is multiplied by this.
@export_range(0.1, 10.0, 0.05, "or_greater", "suffix:x") var damage_multiplier: float = 1.0
## The magazine and the most rounds a reserve holds are multiplied by these (rounded up); the
## re-cut fills both.
@export_range(0.1, 10.0, 0.05, "or_greater", "suffix:x") var magazine_multiplier: float = 1.0
@export_range(0.1, 10.0, 0.05, "or_greater", "suffix:x") var reserve_multiplier: float = 1.0
## Seconds between two shots, and a reload takes this long, once re-cut; 0 leaves the weapon's own.
@export_range(0.0, 3.0, 0.01, "or_greater", "suffix:s") var fire_interval: float = 0.0
@export_range(0.0, 8.0, 0.05, "or_greater", "suffix:s") var reload_time: float = 0.0
## A weapon whose burst puts a status on the dead (the freeze gun): its burst radius is multiplied
## by this.
@export_range(1.0, 3.0, 0.01, "suffix:x") var burst_radius_multiplier: float = 1.0

@export_group("Element")
## The element the re-cut weapon carries, or none: only the weakest guns get one.
@export var element: ElementDef


## The name of the weapon once re-cut: this profile's own, or `prefix` before `plain_name`.
func name_of(plain_name: String, prefix: String) -> String:
	return recut_name if recut_name != "" else prefix + plain_name


func has_element() -> bool:
	return element != null


## What the re-cut does to `plain`, in the card's words: "DAMAGE x1.75, ROUNDS x1.5, EXPLOSIVE
## ROUNDS". A weapon that hurts no one (the flare gun) has no damage to name; a slower rate is
## said, since it is the price of the gain.
func card_line(plain: WeaponDef) -> String:
	var parts := PackedStringArray()
	if plain.damage > 0.0 or plain.splash_damage > 0.0:
		parts.append("DAMAGE x%s" % String.num(damage_multiplier, 2))
	parts.append("ROUNDS x%s" % String.num(magazine_multiplier, 2))
	if fire_interval > plain.fire_interval:
		parts.append("FIRES SLOWER")
	elif fire_interval > 0.0 and fire_interval < plain.fire_interval:
		parts.append("FIRES FASTER")
	if element != null:
		parts.append(element.display_name.to_upper())
	return ", ".join(parts)
