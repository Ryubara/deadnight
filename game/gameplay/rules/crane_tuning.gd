class_name CraneTuning
extends Resource
## The prize crane's timing and its chance to break down. What a play costs and what it can give
## are the shop item `crane_play` (`EconomyTuning`); how the crane behaves is here. The model is
## the Call of Duty Zombies Mystery Box, see docs/research/mystery-box.md.

## The places the crane can stand on the lot, by index (docs/design/map.md): the door that must be
## open before the crane can be there (`&""` for none). The world has one marker per index. The
## stand and the midway lie behind the concession, the field is open, the yard behind its door.
@export
var spot_doors: Array[StringName] = [&"door_concession", &"door_concession", &"", &"door_yard"]
## Where the crane stands at the start of the night.
@export var start_spot: int = 0
## Seconds the claw digs and the prizes cycle above the glass before one is chosen.
@export var spin_seconds: float = 4.5
## Seconds the chosen weapon floats for; only the buyer may take it, and it is lost after.
@export var grab_seconds: float = 12.0
## Plays at one spot that cannot break down. The next one can.
@export var safe_plays: int = 3
## The chance a play breaks the crane down, for the first play that can (the one after
## `safe_plays`), the second, and so on; the last entry repeats. Four at 15%, four at 30%, then 50%
## is the Mystery Box's table by uses since it moved.
@export var leave_chances: PackedFloat32Array = PackedFloat32Array(
	[0.15, 0.15, 0.15, 0.15, 0.3, 0.3, 0.3, 0.3, 0.5]
)
## Seconds from the dud prize showing to the crane being gone (the power-down, then the hop).
@export var breakdown_seconds: float = 4.0
## The share of the price a breakdown gives back.
@export var refund_fraction: float = 1.0


func spot_count() -> int:
	return spot_doors.size()


## The chance that the play after `plays_so_far` plays at this spot breaks the crane down.
func leave_chance(plays_so_far: int) -> float:
	if plays_so_far < safe_plays or leave_chances.is_empty():
		return 0.0
	var index := mini(plays_so_far - safe_plays, leave_chances.size() - 1)
	return leave_chances[index]
