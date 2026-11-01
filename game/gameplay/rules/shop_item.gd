class_name ShopItem
extends Resource
## One thing the shop sells: a door, a weapon, a crane play, a tonic, fuel or grenades.
##
## Data only. The price is a base plus a rise per round, so fuel can get dearer as the night goes
## on.

enum Kind { DOOR, WEAPON, CRANE, TONIC, FUEL, GRENADES }

@export var id: StringName = &""
@export var kind: Kind = Kind.DOOR
## Points at round 1.
@export var price: int = 100
## Points added to the price for each round after the first.
@export var price_per_round: int = 0
## FUEL: units one purchase adds to the tank. GRENADES: grenades one purchase adds.
@export var amount: float = 0.0
## DOOR: another door that must be open first (the lot opens outward).
@export var requires: StringName = &""
## CRANE: the weapons a play can give, with one weight each.
@export var pool: Array[StringName] = []
@export var pool_weights: PackedFloat32Array = PackedFloat32Array()


func price_at(round_number: int) -> int:
	return price + price_per_round * maxi(round_number - 1, 0)
