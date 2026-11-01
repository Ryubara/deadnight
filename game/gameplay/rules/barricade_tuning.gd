class_name BarricadeTuning
extends Resource
## The boards across the fence's breaches: which breaches there are, how many boards each holds and
## how long a walker takes to pull one off. The lot's greybox has one `Barricade` per id (a test
## fails when the scene and this list disagree), so the breaches have one source, like the doors.

## The breaches, one id each; the lot's `Field/Breach*` nodes carry the same ids.
@export var ids: Array[StringName] = [&"nw", &"ne", &"w", &"e", &"n", &"n2"]
## Boards a whole barricade holds, and each one starts the night with.
@export var boards: int = 5
## Seconds a walker takes to pull one board off (a type's `barrier_speed` makes it faster; 0 never
## holds the zombie at all, it goes under). Matches a walker's swing, so a board comes off a swing.
@export var seconds_per_board: float = 1.2
