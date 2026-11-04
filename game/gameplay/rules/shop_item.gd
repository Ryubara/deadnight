class_name ShopItem
extends Resource
## One thing the shop sells: a door, a weapon, a crane play, a tonic (a perk, `perks.md`),
## fuel, grenades, ammunition or a weapon re-cut.
##
## Data only. The price is a base plus a rise per round, so fuel can get dearer as the night goes
## on.

enum Kind { DOOR, WEAPON, CRANE, TONIC, FUEL, GRENADES, AMMO, UPGRADE }

## What a tonic does for the player who has had it (`PerkEffects` reads it, `PerkTuning` has the
## numbers). The effects follow the genre's perks; the names and the machines are ours.
enum Effect { NONE, HEALTH, FIRE_RATE, RELOAD_SPEED, EXTRA_WEAPON, REVIVE, SHOCK }

## A fuel purchase needs at least this much room in the tank.
const MIN_FUEL_SPACE := 1.0

@export var id: StringName = &""
@export var kind: Kind = Kind.DOOR
## The name the prompt card and the machine's board show (a tonic's; the rest are named by the
## places that sell them).
@export var display_name: String = ""
## Points at round 1.
@export_range(0, 10000, 5, "or_greater", "suffix:pts") var price: int = 100
## Points added to the price for each round after the first.
@export_range(0, 1000, 5, "or_greater", "suffix:pts") var price_per_round: int = 0
## FUEL: units one purchase adds to the tank. GRENADES: grenades one purchase adds. AMMO: rounds
## one purchase adds to the weapon's reserve (a partial purchase pays a part price).
@export_range(0.0, 1000.0, 1.0, "or_greater") var amount: float = 0.0
## AMMO: the weapon (a `WeaponCatalog` id, `rifle`) whose reserve the purchase fills.
@export var weapon: StringName = &""
## TONIC: what having it does. `HEALTH` uses `health_bonus`, the others `PerkTuning`.
@export var effect: Effect = Effect.NONE
## TONIC: health added to the buyer's most (and to their health now), so a perk can make a player
## harder to kill. 0 is a tonic with no effect on health.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:hp") var health_bonus: float = 0.0
## DOOR: another door that must be open first (the lot opens outward).
@export var requires: StringName = &""
## CRANE: the weapons a play can give. Each is drawn by its definition's `crane_weight`
## (`WeaponDef`, #972); `pool_weights` is a map's own weights, one for each weapon of `pool`, and is
## empty (the definitions' weights) as shipped.
@export var pool: Array[StringName] = []
@export var pool_weights: PackedFloat32Array = PackedFloat32Array()


func price_at(round_number: int) -> int:
	return PointSteps.price(price + price_per_round * maxi(round_number - 1, 0))


## What `part` of the `amount` one whole purchase adds costs this round: the share of the price,
## rounded up to a step of 5 (`PointSteps.price`), so every part purchase is a multiple of 5.
func part_price(round_number: int, part: float) -> int:
	return PointSteps.price(float(price_at(round_number)) * part / amount)


## AMMO: what `rounds` rounds cost this round (one whole purchase at most), rounded up to a point.
func ammo_price(round_number: int, rounds: int) -> int:
	return part_price(round_number, mini(rounds, int(amount)))


## FUEL: what a purchase puts in a tank with `space` units of room this round: `{price, units}`. A
## part fill pays only for the room; with less than `MIN_FUEL_SPACE` of room (or for an item that
## is no fuel) nothing is sold: `units` and `price` are 0.
func fuel_offer(round_number: int, space: float) -> Dictionary:
	if kind != Kind.FUEL or space < MIN_FUEL_SPACE:
		return {"price": 0, "units": 0.0}
	var units := minf(amount, space)
	return {"price": part_price(round_number, units), "units": units}


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
		total += weight_of(weapon_id)
	var pick := rng.randf() * total
	for weapon_id in left:
		pick -= weight_of(weapon_id)
		if pick < 0.0:
			return weapon_id
	return left[left.size() - 1]


## The weight of a weapon of the pool in the draw: this item's own when it lists weights, the
## weapon definition's `crane_weight` otherwise (1 for an id the catalogue does not know).
func weight_of(weapon_id: StringName) -> float:
	var index := pool.find(weapon_id)
	if index >= 0 and index < pool_weights.size():
		return pool_weights[index]
	var id := WeaponCatalog.catalog_id(weapon_id)
	return WeaponCatalog.get_def(id).crane_weight if WeaponCatalog.has(id) else 1.0


## The weight of every weapon of the pool, in the pool's order.
func weights() -> PackedFloat32Array:
	var all := PackedFloat32Array()
	for weapon_id in pool:
		all.append(weight_of(weapon_id))
	return all
