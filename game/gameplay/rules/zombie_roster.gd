class_name ZombieRoster
extends Resource
## Every zombie type of the night and how a round's mix is drawn from them.
##
## Pure: the same inputs and the same generator give the same plan.

## The type that fills what the others leave (the common dead).
@export var base_id: StringName = &"walker"
## The special types together never take more than this share of a normal round.
@export var max_special_share: float = 0.7
@export var types: Array[ZombieType] = []


func type_of(type_id: StringName) -> ZombieType:
	for candidate in types:
		if candidate.id == type_id:
			return candidate
	return null


## The types of a normal round's zombies, in the order they arrive. A type's first round brings
## exactly `intro_count` of it; after that its share of the count, with the fraction left over
## rounded by `rng`. Shuffled by `rng`.
func plan_for_round(round_number: int, count: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var plan: Array[StringName] = []
	var room := floori(float(count) * max_special_share)
	for type in types:
		if type.id == base_id or type.boss or round_number < type.first_round or room <= 0:
			continue
		var wanted := type.intro_count
		if round_number > type.first_round:
			var exact := float(count) * type.share_at(round_number)
			wanted = floori(exact)
			if rng.randf() < exact - float(wanted):
				wanted += 1
		wanted = mini(wanted, room)
		room -= wanted
		for _i in wanted:
			plan.append(type.id)
	while plan.size() < count:
		plan.append(base_id)
	shuffle(plan, rng)
	return plan


## Fisher-Yates with the caller's generator, so a shuffle is part of the seeded night.
static func shuffle(items: Array[StringName], rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var kept := items[i]
		items[i] = items[j]
		items[j] = kept
