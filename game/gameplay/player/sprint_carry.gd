class_name SprintCarry
extends RefCounted
## The sprint carry's weight and place (#459), the part of `PlayerAnimation` that has no tree in
## it: how far the arms carry the weapon (0 to 1, moved linearly; the tree eases it) and where the
## carry's clip is, in its own seconds, locked to the Run clip's place.

## When the carry is out of step with the Run by more than a frame (the locomotion restarted on a
## landing, the carry held still in the air) it catches up at this rate (per second, exponential)
## instead of jumping; within a frame it is locked.
const CATCH_RATE := 12.0

var weight := 0.0
var time := 0.0


## The weight `span` seconds toward `wanted`.
func advance_weight(delta: float, wanted: bool, span: float) -> void:
	weight = move_toward(weight, 1.0 if wanted else 0.0, delta / maxf(span, 0.001))


## The clip's place after a step of `step` seconds while the Run is at `run_place`: the place the
## Run reaches in the step to come, so the two land on the same frame. Out of the
## carry (weight 0) or within a frame (`frame` seconds) it is the Run's place; else it catches up.
func follow_run(delta: float, run_place: float, step: float, length: float, frame: float) -> void:
	var target := fposmod(run_place + step, length)
	var error := wrapf(target - (time + step), -length * 0.5, length * 0.5)
	if weight == 0.0 or absf(error) < frame:
		time = target
	else:
		time = fposmod(time + step + error * (1.0 - exp(-CATCH_RATE * delta)), length)
