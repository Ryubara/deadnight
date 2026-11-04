class_name BarricadeTuning
extends Resource
## The boards across the fence's breaches: which breaches there are, how many boards each holds and
## how long a walker takes to pull one off. The lot's greybox has one `Barricade` per id (a test
## fails when the scene and this list disagree), so the breaches have one source, like the doors.

## The breaches, one id each; the lot's `Breach*` nodes carry the same ids: the field's six, then
## the midway's two bays, the yard's, the back lot's and the plaza's (#849).
@export var ids: Array[StringName] = [
	&"nw",
	&"ne",
	&"w",
	&"e",
	&"n",
	&"n2",
	&"mid_w",
	&"mid_e",
	&"yard_e1",
	&"yard_e2",
	&"yard_s",
	&"back_w1",
	&"back_w2",
	&"back_s",
	&"plaza_w",
	&"plaza_e",
]
## Boards a whole barricade holds, and each one starts the night with.
@export_range(1, 20, 1, "or_greater") var boards: int = 5
## Seconds a walker takes to pull one board off (a type's `barrier_speed` makes it faster; 0 never
## holds the zombie at all, it goes under). Matches a walker's swing, so a board comes off a swing.
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:s") var seconds_per_board: float = 1.2
