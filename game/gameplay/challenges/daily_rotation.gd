class_name DailyRotation
extends RefCounted
## Which dailies a day holds. A pure function of the day number and the catalogue: the same day
## gives the same three for everyone and on every run, and no stored state is needed to know
## yesterday's.
##
## A day deals one short, one medium and one long challenge. Two of one `group` never share a day,
## and a challenge dealt the day before is passed over when its tier has another to give, so
## neighbouring days differ. That needs the day before, which needs the one before it: the chain
## runs from the first day of a 30-day block (dealt with no history), so any day is worked out
## from its own block alone, and only the first day of a block can repeat its neighbour.

const SEED_MULTIPLIER := 1103515245
const SEED_STEP := 12345
const SEED_MASK := 0x7fffffff
const BLOCK_DAYS := 30
const TIERS: Array[ChallengeDef.Tier] = [
	ChallengeDef.Tier.SHORT, ChallengeDef.Tier.MEDIUM, ChallengeDef.Tier.LONG
]


## The ids dealt for `day`, short first.
static func deal(catalog: ChallengeCatalog, day: int) -> Array[StringName]:
	var dealt: Array[StringName] = []
	for step in range(day - posmod(day, BLOCK_DAYS), day + 1):
		dealt = _draw(catalog, step, dealt)
	return dealt


static func _draw(
	catalog: ChallengeCatalog, day: int, avoid: Array[StringName]
) -> Array[StringName]:
	var rng := RandomNumberGenerator.new()
	rng.seed = (day * SEED_MULTIPLIER + SEED_STEP) & SEED_MASK
	var dealt: Array[StringName] = []
	var groups: Array[StringName] = []
	for tier in TIERS:
		var pool := catalog.dailies_of(tier)
		var fresh: Array[ChallengeDef] = pool.filter(
			func(def: ChallengeDef) -> bool:
				return not avoid.has(def.id) and not groups.has(def.group)
		)
		if fresh.is_empty():
			fresh = pool.filter(func(def: ChallengeDef) -> bool: return not groups.has(def.group))
		if fresh.is_empty():
			fresh = pool
		if fresh.is_empty():
			continue
		var pick := fresh[rng.randi_range(0, fresh.size() - 1)]
		dealt.append(pick.id)
		groups.append(pick.group)
	return dealt
