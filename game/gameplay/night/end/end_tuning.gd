class_name EndTuning
extends Resource
## The numbers of the camera at the end of a night (`EndCamera`, docs/design/end-of-night.md): how
## long and how far it pulls back from the player's own lens, how long each authored angle stays,
## and the air it keeps from a wall. The shipped values are in `end_tuning_default.tres`;
## `EndTuning.shipped()` is how the night and the tests read it.

const SHIPPED_PATH := "res://gameplay/night/end/end_tuning_default.tres"

@export_group("Pull-back")
## Seconds the lens takes from where the player's own camera was to the high place over them.
@export_range(1.0, 10.0, 0.5, "suffix:s") var pullback_seconds := 4.0
## Metres back from the player (along the way the lens was behind them) the pull-back ends.
@export_range(2.0, 40.0, 0.5, "suffix:m") var pullback_distance := 12.0
## Metres over the player's feet the pull-back ends.
@export_range(2.0, 40.0, 0.5, "suffix:m") var pullback_height := 8.0
## Metres over the player's feet the lens looks at.
@export_range(0.0, 3.0, 0.1, "suffix:m") var look_lift := 1.2
## The field of view (degrees) the pull-back ends on; it starts on the player's own.
@export_range(30.0, 100.0, 1.0, "suffix:°") var pullback_fov := 62.0

@export_group("Angles")
## Seconds each authored angle of the map stays before the cut to the next.
@export_range(2.0, 12.0, 0.5, "suffix:s") var shot_seconds := 3.5

@export_group("Walls")
## Metres of air the lens keeps from a wall on the pull-back (a sphere this big is swept).
@export_range(0.05, 1.0, 0.05, "suffix:m") var margin := 0.3


## A private copy of the shipped table: a test may change it without touching the file.
static func shipped() -> EndTuning:
	return (load(SHIPPED_PATH) as EndTuning).duplicate(true) as EndTuning
