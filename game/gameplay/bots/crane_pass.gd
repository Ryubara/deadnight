class_name CranePass
extends RefCounted
## That a shopper let the crane's prize go (#1322, #1331): the round it was in and the weapons it
## carried then. It plays no more in that round with those weapons: nothing it knows has changed,
## so another play would be dealt the same kind of hand. Held by a bot's beliefs and by the
## simulator's shopper, so both stop at the same place.

## The round the prize was last left in, or -1.
var round_number := -1
var _arms := ""


## Notes that the prize was left on the glass in `in_round` by a shopper carrying `arms` (a
## dictionary keyed by weapon id).
func note(in_round: int, arms: Dictionary) -> void:
	round_number = in_round
	_arms = arms_key(arms)


## Whether the shopper passed the prize in `in_round` carrying `arms` (nothing has changed).
func holds(in_round: int, arms: Dictionary) -> bool:
	return round_number == in_round and _arms == arms_key(arms)


## The weapons of `arms` as one string, in order of name.
static func arms_key(arms: Dictionary) -> String:
	var names: Array[String] = []
	for id: StringName in arms:
		names.append(String(id))
	names.sort()
	return ",".join(names)
