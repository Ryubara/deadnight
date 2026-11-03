class_name HitPoseSets
extends Resource
## The hit zones fitted to each body in each pose (`HitPoseData`), as a resource the fitting tool
## writes (`tools/hit_fit/fit_hit_shapes.gd`): `{set id: {shapes, bound_centre, bound_radius}}`, the
## shapes `{zone, a, b, r}` with the points relative to the feet, +Z forward, in units of the look's
## height. Never edited by hand: re-run the tool after a model or a clip changes.

@export var sets: Dictionary = {}
