class_name RulesTuning
extends Resource
## The whole tuning table in one resource. Designers edit `default_tuning.tres`; no code holds a
## game number.

const FINGERPRINT_LENGTH := 16

@export var rounds: RoundTuning = RoundTuning.new()
@export var economy: EconomyTuning = EconomyTuning.new()
@export var fuel: FuelTuning = FuelTuning.new()
@export var roster: ZombieRoster = ZombieRoster.new()
@export var specials: SpecialTuning = SpecialTuning.new()
@export var explosives: ExplosiveTuning = ExplosiveTuning.new()
@export var barricades: BarricadeTuning = BarricadeTuning.new()
@export var health: HealthTuning = HealthTuning.new()
@export var revive: ReviveTuning = ReviveTuning.new()
@export var crane: CraneTuning = CraneTuning.new()
@export var upgrade: UpgradeTuning = UpgradeTuning.new()
@export var perks: PerkTuning = PerkTuning.new()


## A short hex fingerprint of every number in the table. Two sides with the same fingerprint run the
## same rules; a snapshot is refused under a different one. It reads the values, not the file, so a
## re-saved `.tres` with the same numbers matches.
func fingerprint() -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(_canonical(self)))
	return hashing.finish().hex_encode().substr(0, FINGERPRINT_LENGTH)


## Resources become dictionaries of their stored script variables, dictionaries are key-sorted,
## so the same values always make the same bytes.
static func _canonical(value: Variant) -> Variant:
	if value is Resource:
		var fields := {}
		for property: Dictionary in (value as Resource).get_property_list():
			var usage: int = property["usage"]
			var stored := (usage & PROPERTY_USAGE_STORAGE) != 0
			if stored and (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
				fields[property["name"]] = _canonical(value.get(property["name"]))
		return fields
	if value is Array:
		var items := []
		for item: Variant in value:
			items.append(_canonical(item))
		return items
	if value is Dictionary:
		var keys: Array = (value as Dictionary).keys()
		keys.sort()
		var sorted := {}
		for key: Variant in keys:
			sorted[key] = _canonical(value[key])
		return sorted
	return value
