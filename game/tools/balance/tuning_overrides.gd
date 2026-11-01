class_name TuningOverrides
extends RefCounted
## Changes numbers of a tuning table for one run, so a balance experiment needs no edit to the
## shipped file. A spec is `path=value`; the path walks the table by property name, and an entry of
## a list is named by its id after a colon:
##
##   rounds.health_growth=1.05
##   roster.types:headliner.health_multiplier=18
##   specials.rounds:stampede.count_fraction=0.6


## Applies every spec to `tuning` (a private copy: the caller duplicates it first). Returns the
## specs that did not name anything, empty when all were applied.
static func apply(tuning: RulesTuning, specs: PackedStringArray) -> PackedStringArray:
	var failed := PackedStringArray()
	for spec in specs:
		if not _apply_one(tuning, spec):
			failed.append(spec)
	return failed


static func _apply_one(tuning: RulesTuning, spec: String) -> bool:
	var halves := spec.split("=", true, 1)
	if halves.size() != 2:
		return false
	var steps := halves[0].split(".")
	var target: Object = tuning
	for i in steps.size() - 1:
		target = _step(target, steps[i])
		if target == null:
			return false
	var name := steps[steps.size() - 1]
	if not name in target:
		return false
	var current: Variant = target.get(name)
	target.set(name, int(halves[1]) if typeof(current) == TYPE_INT else float(halves[1]))
	return true


static func _step(from: Object, step: String) -> Object:
	if not ":" in step:
		return from.get(step) as Object
	var parts := step.split(":")
	for entry: Object in from.get(parts[0]):
		if str(entry.get("id")) == parts[1]:
			return entry
	return null
