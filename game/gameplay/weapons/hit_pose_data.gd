class_name HitPoseData
extends RefCounted
## The fitted hit zones (`HitPoseSets`, written by `tools/hit_fit/fit_hit_shapes.gd` into
## `hit_pose_data.tres`), loaded once.

const FILE := "res://gameplay/weapons/hit_pose_data.tres"

static var _sets: Dictionary = {}


## `{set id: {shapes, bound_centre, bound_radius}}`; the ids are `<look>.<pose>` (`ZombiePose`).
static func sets() -> Dictionary:
	if _sets.is_empty():
		_sets = (load(FILE) as HitPoseSets).sets
	return _sets
