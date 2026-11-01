class_name EconomyTuning
extends Resource
## Points: what earns them and what the shop charges. Prices are chosen against what a round earns
## (see docs/design/rounds.md), so retune them together.

@export_group("Earning")
@export var start_points: int = 200
## A hit that does not kill.
@export var hit: int = 4
## A hit to the head that does not kill.
@export var headshot_hit: int = 8
## Hits that do not kill pay for at most this many per zombie, so one zombie is a bounded purse
## (4 headshot hits and the kill are worth 132 at most) however many shots it soaks up.
@export var max_paid_hits: int = 4
## The killing blow (shot, not a headshot, not melee).
@export var kill: int = 60
@export var headshot_kill: int = 100
## Melee pays best: it is the riskiest.
@export var melee_kill: int = 130
## One barricade board put back (in a break or a round).
@export var repair: int = 12
## Most a player can earn from repairs from one round's end to the next (stops board farming).
@export var repair_cap_per_round: int = 120
## Paid to every player on their feet when a round ends: base + per_round * round.
@export var round_bonus_base: int = 20
@export var round_bonus_per_round: int = 10
## A player still down when the round ends gets up, minus this fraction of their points.
@export var down_penalty_fraction: float = 0.1

@export_group("Shop")
@export var max_tonics: int = 4
@export var items: Array[ShopItem] = []


func item(item_id: StringName) -> ShopItem:
	for candidate in items:
		if candidate.id == item_id:
			return candidate
	return null


func round_bonus(round_number: int) -> int:
	return round_bonus_base + round_bonus_per_round * round_number
