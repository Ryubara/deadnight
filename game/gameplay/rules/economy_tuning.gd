class_name EconomyTuning
extends Resource
## Points: what earns them and what the shop charges. Prices are chosen against what a round earns
## (see docs/design/rounds.md), so retune them together.

@export_group("Earning")
@export_range(0, 1000, 1, "or_greater", "suffix:pts") var start_points: int = 200
## What a player carries at the start, as shop ids, the firearm last so it is the one in hand.
## They count as carried: a third weapon replaces the one in hand, and the replaced one is a prize
## or a purchase again (`WeaponCarry`).
@export var start_weapons: Array[StringName] = [&"weapon_pistol"]
## A hit that does not kill.
@export_range(0, 100, 1, "or_greater", "suffix:pts") var hit: int = 4
## A hit to the head that does not kill.
@export_range(0, 100, 1, "or_greater", "suffix:pts") var headshot_hit: int = 8
## Hits that do not kill pay for at most this many per zombie, so one zombie is a bounded purse
## (4 headshot hits and the kill are worth 102 at most) however many shots it soaks up.
@export_range(0, 20, 1, "or_greater") var max_paid_hits: int = 4
## The killing blow (shot, not a headshot, not melee).
@export_range(0, 1000, 1, "or_greater", "suffix:pts") var kill: int = 60
@export_range(0, 1000, 1, "or_greater", "suffix:pts") var headshot_kill: int = 70
## Melee pays best: it is the riskiest.
@export_range(0, 1000, 1, "or_greater", "suffix:pts") var melee_kill: int = 130
## One barricade board put back (in a break or a round).
@export_range(0, 100, 1, "or_greater", "suffix:pts") var repair: int = 12
## Most a player can earn from repairs from one round's end to the next (stops board farming).
@export_range(0, 1000, 1, "or_greater", "suffix:pts") var repair_cap_per_round: int = 120
## Paid to every player on their feet when a round ends: base + per_round * round.
@export_range(0, 100, 1, "or_greater", "suffix:pts") var round_bonus_base: int = 20
@export_range(0, 100, 1, "or_greater", "suffix:pts") var round_bonus_per_round: int = 10
## A player still down when the round ends gets up, minus this fraction of their points.
@export_range(0.0, 1.0, 0.01) var down_penalty_fraction: float = 0.1

@export_group("Shop")
@export_range(0, 20, 1, "or_greater") var max_tonics: int = 4
@export var items: Array[ShopItem] = []


func item(item_id: StringName) -> ShopItem:
	for candidate in items:
		if candidate.id == item_id:
			return candidate
	return null


## The ammunition item of a weapon (a catalogue id), or null when the shop sells none for it.
func ammo_item_for(weapon_id: StringName) -> ShopItem:
	for candidate in items:
		if candidate.kind == ShopItem.Kind.AMMO and candidate.weapon == weapon_id:
			return candidate
	return null


func round_bonus(round_number: int) -> int:
	return round_bonus_base + round_bonus_per_round * round_number
