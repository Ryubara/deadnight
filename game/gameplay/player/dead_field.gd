class_name DeadField
extends RefCounted
## The dead one player's body can meet this tick: the zombies near it, as ids and feet positions,
## and (written by the simulation) the ones it touched. A server fills it from the positions the
## player's client had seen (`DeadSnapshot`), a predicting client from the frame it drew; both give
## the same positions to the same step (`DeadBlock`), so the body is stopped at the same place on
## both machines.

var tuning: DeadContactTuning
var ids := PackedInt32Array()
var positions := PackedVector3Array()

## What the last step touched: the zombie's id, the flat unit vector from it to the body, and how
## fast (m/s) the stick pushed into it.
var touch_ids := PackedInt32Array()
var touch_normals := PackedVector3Array()
var touch_pushes := PackedFloat32Array()
## The flat unit vector of the way the stick pushed, for each.
var touch_intents := PackedVector3Array()
## Whether the last step stopped the body at a zombie.
var blocked := false


func _init(p_tuning: DeadContactTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else DeadContactTuning.shipped()


## Takes the zombies of `snapshot` that stand within `near_range` of `centre`.
func fill(snapshot: DeadSnapshot, centre: Vector3) -> void:
	ids.clear()
	positions.clear()
	var limit := tuning.near_range * tuning.near_range
	var all := snapshot.positions
	for i in all.size():
		var at := all[i]
		var dx := at.x - centre.x
		var dz := at.z - centre.z
		if dx * dx + dz * dz <= limit:
			ids.append(snapshot.ids[i])
			positions.append(at)


func clear() -> void:
	ids.clear()
	positions.clear()
	clear_touches()


func clear_touches() -> void:
	touch_ids.clear()
	touch_normals.clear()
	touch_pushes.clear()
	touch_intents.clear()
	blocked = false
