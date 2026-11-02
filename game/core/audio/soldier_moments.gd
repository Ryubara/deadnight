class_name SoldierMoments
extends Resource
## The table of the soldier's moments, in one resource: what he speaks about and how it ranks. The
## shipped values are in `soldier_moments_default.tres`: edit that file in the inspector;
## `SoldierMoments.table()` is how the game and the tests read it (`SoldierVoiceCatalog.moments()`).

const SHIPPED_PATH := "res://core/audio/soldier_moments_default.tres"

static var _table: Dictionary = {}

## Every moment, most urgent first.
@export var moments: Array[SoldierMoment] = []


## The shipped table as `{event: {takes, priority, cooldown, chance}}`, in the file's order.
static func table() -> Dictionary:
	if _table.is_empty():
		var moments_of_file: Array[SoldierMoment] = (load(SHIPPED_PATH) as SoldierMoments).moments
		for moment in moments_of_file:
			_table[moment.event] = {
				"takes": moment.takes,
				"priority": moment.priority,
				"cooldown": moment.cooldown,
				"chance": moment.chance,
			}
	return _table
