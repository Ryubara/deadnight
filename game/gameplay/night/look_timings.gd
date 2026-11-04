class_name LookTimings
extends RefCounted
## The seconds a look's blow and board-tearing take, read from the roster, for the night's view
## (`ZombieView`): its clips are paced to the rules, not to a number of their own.


## Seconds each look's blow takes to land, for the looks of the types that telegraph it.
static func telegraphs(tuning: RulesTuning) -> Dictionary[StringName, float]:
	var telegraphs: Dictionary[StringName, float] = {}
	for type in tuning.roster.types:
		if type.telegraph_seconds > 0.0:
			for look in type.looks:
				telegraphs[look] = type.telegraph_seconds
	return telegraphs


## Seconds each look's type takes to pull one board off, for its tear clip.
static func board_seconds(tuning: RulesTuning) -> Dictionary[StringName, float]:
	var seconds: Dictionary[StringName, float] = {}
	var per_board := tuning.barricades.seconds_per_board
	for type in tuning.roster.types:
		if type.barrier_speed > 0.0:
			for look in type.looks:
				seconds[look] = per_board / type.barrier_speed
	return seconds
