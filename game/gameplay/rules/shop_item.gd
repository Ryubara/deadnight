class_name ShopItem
extends Resource
## One thing the shop sells: a door, a weapon, a crane play, a tonic, fuel, grenades or ammunition.
##
## Data only. The price is a base plus a rise per round, so fuel can get dearer as the night goes
## on.

enum Kind { DOOR, WEAPON, CRANE, TONIC, FUEL, GRENADES, AMMO }

## A fuel purchase needs at least this much room in the tank.
const MIN_FUEL_SPACE := 1.0

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


## FUEL: what a purchase puts in a tank with `space` units of room this round: `{price, units}`. A
## part fill pays only for the room; with less than `MIN_FUEL_SPACE` of room (or for an item that
## is no fuel) nothing is sold: `units` and `price` are 0.
func fuel_offer(round_number: int, space: float) -> Dictionary:
	if kind != Kind.FUEL or space < MIN_FUEL_SPACE:
		return {"price": 0, "units": 0.0}
	var units := minf(amount, space)
	return {"price": ceili(float(price_at(round_number)) * units / amount), "units": units}


## The crane's weapons not in `owned`.
func pool_without(owned: Array[StringName]) -> Array[StringName]:
	var left: Array[StringName] = []
	for weapon_id in pool:
		if not owned.has(weapon_id):
			left.append(weapon_id)
	return left


## One of the weapons not in `owned`, drawn by weight from `rng`. The pool must not be empty.
func roll(owned: Array[StringName], rng: RandomNumberGenerator) -> StringName:
	var left := pool_without(owned)
	var total := 0.0
	for weapon_id in left:
		total += _weight(weapon_id)
	var pick := rng.randf() * total
	for weapon_id in left:
		pick -= _weight(weapon_id)
		if pick < 0.0:
			return weapon_id
	return left[left.size() - 1]


func _weight(weapon_id: StringName) -> float:
	var index := pool.find(weapon_id)
	return pool_weights[index] if index < pool_weights.size() else 1.0
