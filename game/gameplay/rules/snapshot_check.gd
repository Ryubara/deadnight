class_name SnapshotCheck
extends RefCounted
## Checks the shape of a snapshot piece before anything is restored from it: every key a spec names
## is present and holds the type the spec says. Pure functions; a restore that passes them cannot
## trip over a missing key or a wrong type halfway through.


## True when `data` has every key of `spec` and each value fits its type.
static func fits(data: Dictionary, spec: Dictionary) -> bool:
	for key: String in spec:
		if not data.has(key) or not fits_type(data[key], spec[key]):
			return false
	return true


## True when `value` has type `expected`. A whole number fits a float; a String and a StringName
## fit each other (a name is one or the other depending on the road it came by).
static func fits_type(value: Variant, expected: int) -> bool:
	var actual := typeof(value)
	if actual == expected:
		return true
	if expected == TYPE_FLOAT:
		return actual == TYPE_INT
	return is_name_type(actual) and is_name_type(expected)


static func is_name_type(variant_type: int) -> bool:
	return variant_type == TYPE_STRING or variant_type == TYPE_STRING_NAME


## True when every element of `items` is a String or StringName.
static func all_names(items: Array) -> bool:
	for item: Variant in items:
		if not is_name_type(typeof(item)):
			return false
	return true


## True when what a snapshot holds inside its top-level keys (which are already known to be there,
## each of its type) can be restored under `tuning`: the phase, the plan, the special round, the
## doors, the zombies, the players and the generator. Changes nothing.
static func insides_fit(data: Dictionary, tuning: RulesTuning) -> bool:
	return (
		data["phase"] >= 0
		and data["phase"] < GameRules.Phase.size()
		and is_finite(data["night_time"])
		and data["night_time"] >= 0.0
		and _plan_fits(data["plan"], tuning)
		and _special_fits(data["special_id"], tuning)
		and all_names(data["doors_open"])
		and _entries_fit(data["zombies"], ZombieState.SNAPSHOT_KEYS, _zombie_fits.bind(tuning))
		and _entries_fit(data["players"], PlayerState.SNAPSHOT_KEYS, _player_fits)
		and _generator_fits(data["generator"])
		and BarricadeState.new(tuning.barricades).fits(data["barricades"])
		and CraneState.new().fits(data["crane"], tuning.crane.spot_count())
		and MatchSettings.problem(data["match_settings"]).is_empty()
	)


static func _plan_fits(plan: Array, tuning: RulesTuning) -> bool:
	return all_names(plan) and plan.all(func(id: Variant) -> bool: return _is_type(id, tuning))


static func _special_fits(special_id: String, tuning: RulesTuning) -> bool:
	return special_id == "" or tuning.specials.by_id(StringName(special_id)) != null


static func _is_type(type_id: Variant, tuning: RulesTuning) -> bool:
	return tuning.roster.type_of(StringName(type_id)) != null


## Every entry is a dictionary under an integer key that is its own `id`, with the keys of `spec`,
## and passes `extra`.
static func _entries_fit(entries: Dictionary, spec: Dictionary, extra: Callable) -> bool:
	for entry_id: Variant in entries:
		var entry: Variant = entries[entry_id]
		if typeof(entry_id) != TYPE_INT or typeof(entry) != TYPE_DICTIONARY:
			return false
		if not fits(entry, spec) or entry["id"] != entry_id or not extra.call(entry):
			return false
	return true


static func _zombie_fits(zombie: Dictionary, tuning: RulesTuning) -> bool:
	return _is_type(zombie["type"], tuning)


static func _player_fits(player: Dictionary) -> bool:
	return (
		all_names(player["weapons"])
		and all_names(player["tonics"])
		and all_names(player["upgraded"])
		and _health_fits(player["health"], player["max_health"])
		and is_finite(player["since_blow"])
		and player["since_blow"] >= 0.0
		and player["kills"] >= 0
		and player["downs"] >= 0
	)


## Health is a number from nothing to the player's most, which is something.
static func _health_fits(health: float, max_health: float) -> bool:
	if not is_finite(health) or not is_finite(max_health):
		return false
	return max_health > 0.0 and health >= 0.0 and health <= max_health


static func _generator_fits(generator: Dictionary) -> bool:
	if not fits(generator, GeneratorState.SNAPSHOT_KEYS):
		return false
	var circuits: Dictionary = generator["circuits"]
	for circuit_id: Variant in circuits:
		if not is_name_type(typeof(circuit_id)) or typeof(circuits[circuit_id]) != TYPE_BOOL:
			return false
	return true
