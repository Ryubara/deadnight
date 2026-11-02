class_name SpecialTuning
extends Resource
## Which rounds are special and in which order the kinds come. A special round is announced in the
## break before it (a longer break, so the marquee and the sting have time) and pays a reward when
## it is cleared.

## A special round every this many rounds, starting at `first_round`. 0 turns them off.
@export_range(1, 50, 1, "or_greater") var every: int = 5
@export_range(1, 100, 1, "or_greater") var first_round: int = 5
## The break before a special round is this much longer.
@export_range(0.0, 60.0, 0.5, "or_greater", "suffix:s") var break_bonus_seconds: float = 10.0
## The kinds, in turn: the first special round is the first entry, the next the second, and the list
## starts again at its end.
@export var rounds: Array[SpecialRound] = []


func is_special(round_number: int) -> bool:
	return (
		every > 0
		and not rounds.is_empty()
		and round_number >= first_round
		and (round_number - first_round) % every == 0
	)


## The kind of special round this round is, or null for a normal one.
func special_for(round_number: int) -> SpecialRound:
	if not is_special(round_number):
		return null
	return rounds[((round_number - first_round) / every) % rounds.size()]


func by_id(special_id: StringName) -> SpecialRound:
	for candidate in rounds:
		if candidate.id == special_id:
			return candidate
	return null
