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


## Adds the carry clips of `classes` from the file `glb` to the library (the repair clip's recipe)
## and their entries from `spec_path` to `spec`.
static func add_clips(
	library: AnimationLibrary, classes: Array, glb: String, spec_path: String, spec: Dictionary
) -> void:
	var from: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	var holder: Node = null
	for cls: StringName in classes:
		var clip := StringName("Sprint_" + String(cls))
		spec["clips"][String(clip)] = from["clips"][String(clip)]
		if library.has_animation(clip):
			continue
		if holder == null:
			holder = (load(glb) as PackedScene).instantiate()
		var source := holder.find_child("AnimationPlayer", true, false) as AnimationPlayer
		library.add_animation(clip, source.get_animation(clip))
	if holder != null:
		holder.free()
