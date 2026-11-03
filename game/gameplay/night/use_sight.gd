class_name UseSight
extends RefCounted
## Whether a hand reaches a thing: the line from a player's hand to it meets no wall, prop, floor or
## shut door on the way. A reach is a distance on the flat (`NightTuning.use_reach` and its kin) and
## a distance alone goes through a wall: the prompt showed, and the press worked, from the far side
## of one (#831). Every use the server decides asks this as well, so the prompt a client draws (it
## is the server's, in the frame) and the press the server takes can never disagree.
##
## The line is cast with the probe's static answer (`WorldProbe.static_callable`): walls, props and
## doors count, a person, a zombie or a thrown thing does not, so two players side by side never
## "wall" one another (the shots' probe meets bodies, and its ray stopped on the target's own
## capsule: the grenades lesson of #805).

## Metres above the feet the line runs at, at both ends: the hand, over a counter one metre high.
const HAND := 1.1
## Metres short of the thing the line may stop and still reach it: the face of the prop the thing
## stands against, or of the post it is on.
const SKIN := 0.2
## The same for a thing that hangs on a wall or stands in it (a breaker post, a door's slab, a
## window the boards go across): the wall's own face is the first thing the line meets.
const MOUNT_SKIN := 0.6
## Metres within which a stand belongs to a slab (the stand is `DOOR_STAND_DISTANCE`, 1.5 m, out).
const STAND_NEAR := 2.5

## `from, to -> distance to the first static surface, or -1.0 when clear` (`WorldProbe`).
var _ray: Callable


## `ray` is `WorldProbe.static_callable()`; without one (a stand-in world) nothing is walled off.
func _init(ray: Callable = Callable()) -> void:
	_ray = ray


## Whether the hand at feet `here` reaches `there` (the feet of whatever stands at the point, or the
## point itself for a thing the map places at its middle), `skin` metres short of it at the most.
func clear(here: Vector3, there: Vector3, skin: float = SKIN) -> bool:
	if not _ray.is_valid():
		return true
	var from := here + Vector3(0.0, HAND, 0.0)
	var to := there + Vector3(0.0, HAND, 0.0)
	var along := from.distance_to(to)
	if along <= skin:
		return true
	var hit: float = _ray.call(from, to)
	return hit < 0.0 or hit >= along - skin


## Whether the hand at `here` reaches a thing mounted in a wall at `there`, whose front (a flat
## direction out of the wall) the hand must be on the side of: from behind, the wall it hangs on is
## between, however thin. The line may end `MOUNT_SKIN` short of it.
func clear_mounted(here: Vector3, there: Vector3, front: Vector3) -> bool:
	var side := Vector2(here.x - there.x, here.z - there.z)
	if Vector2(front.x, front.z).dot(side) < 0.0:
		return false
	return clear(here, there, MOUNT_SKIN)


## Whether the hand at `here` reaches the slab of a door from a side the door is bought from (a
## stand of its own: the open ground in front of it; some doors have one on each side): a player on
## the far side of a shut door does not buy it through itself. The line ends in the slab's middle,
## whatever height that is.
func clear_door(here: Vector3, slab: Vector3, stands: Array[Vector3]) -> bool:
	var middle := slab - Vector3(0.0, HAND, 0.0)
	var fronted := false
	for stand in stands:
		var front := stand - slab
		if Vector2(front.x, front.z).length() > STAND_NEAR:
			continue
		fronted = true
		if clear_mounted(here, middle, front):
			return true
	return not fronted and clear(here, middle, MOUNT_SKIN)
