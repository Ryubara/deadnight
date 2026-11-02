class_name BotLink
extends RefCounted
## A curated place where a bot may jump: from `from` to `to`, both on the ground plane, with the
## height between them (a car roof is 1.0 m up; the jump is 1.1 m). They are authored data
## (`Marker3D` pairs in the lot, `BotLevel.links`), not found by the bot: the mesh stops at a 0.25 m
## climb, so a bot never paths off an edge and uses a link only on purpose.

var from := Vector3.ZERO
var to := Vector3.ZERO


func _init(p_from: Vector3 = Vector3.ZERO, p_to: Vector3 = Vector3.ZERO) -> void:
	from = p_from
	to = p_to


## The flat direction of the jump.
func heading() -> Vector3:
	var flat := to - from
	flat.y = 0.0
	return flat.normalized()


## Metres of height the jump climbs (negative when it drops).
func rise() -> float:
	return to.y - from.y
