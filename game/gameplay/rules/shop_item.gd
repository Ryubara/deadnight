class_name ShopItem
extends Resource
## One thing the shop sells: a door, a weapon, a crane play, a tonic, fuel, grenades or ammunition.
##
## Data only. The price is a base plus a rise per round, so fuel can get dearer as the night goes
## on.

enum Kind { DOOR, WEAPON, CRANE, TONIC, FUEL, GRENADES, AMMO }

@export var id: StringName = &""
@export var kind: Kind = Kind.DOOR
## Points at round 1.
@export var price: int = 100
## Points added to the price for each round after the first.
@export var price_per_round: int = 0
## FUEL: units one purchase adds to the tank. GRENADES: grenades one purchase adds. AMMO: rounds
## one purchase adds to the weapon's reserve (a partial purchase pays a part price).
@export var amount: float = 0.0
## AMMO: the weapon (a `WeaponCatalog` id, `rifle`) whose reserve the purchase fills.
@export var weapon: StringName = &""
## DOOR: another door that must be open first (the lot opens outward).
@export var requires: StringName = &""
## CRANE: the weapons a play can give, with one weight each.
@export var pool: Array[StringName] = []
@export var pool_weights: PackedFloat32Array = PackedFloat32Array()


func price_at(round_number: int) -> int:
	return price + price_per_round * maxi(round_number - 1, 0)


## AMMO: what `rounds` rounds cost this round (one whole purchase at most), rounded up to a point.
func ammo_price(round_number: int, rounds: int) -> int:
	return ceili(float(price_at(round_number)) * mini(rounds, int(amount)) / amount)


## CRANE: the weapons of the pool the player does not own yet.
func crane_pool(owned: Array[StringName]) -> Array[StringName]:
	var left: Array[StringName] = []
	for weapon_id in pool:
		if not owned.has(weapon_id):
			left.append(weapon_id)
	return left


## CRANE: the weight of a weapon in the pool (1 when the table gives none).
func weight_of(weapon_id: StringName) -> float:
	var index := pool.find(weapon_id)
	return pool_weights[index] if index < pool_weights.size() else 1.0
