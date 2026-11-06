class_name ZombieRouteKeep
extends RefCounted
## Whether a zombie goes on along the route it has, and not the one just found (`ZombieSim._repath`
## asks at every repath). Static: it reads the zombie and the two routes and keeps nothing.

## How much longer a new route has to be than what is left of the old one, to be refused while the
## old one still ends near the target.
const FLIP := 6.0
## How much shorter than what is left of the old route a new one that sends the zombie back the way
## it came has to be. It is wider than the walking mesh's search is wrong about two ways round an
## obstacle (3 m at the drive-in's booths, #1347).
const GAIN := 4.0
## A zombie farther than this (metres) from the leg of its route it is walking (the crowd shoved it,
## a blast threw it) has lost the route: it asks for a new one whatever the gain.
const STRAY := 1.0
## The first leg of a route is the first point this far (metres) from the zombie: nearer is its own
## spot on the mesh, not a direction.
const LEG_LEAST := 0.3
## The old route is kept only while it ends within this many metres of the target.
const KEEP := 3.5
## ... and while more than this much of it is left to walk (a nearly walked route is let go).
const ARRIVED := 1.0


## A target that stands where the walking mesh is not (between two parked cars, against a wall) is
## reached at the nearest point of the mesh, and which point that is changes as the target shuffles
## a metre: the way round the other side of the obstacle is 20 m longer, and a dead that turned back
## at every repath walked up and down between the two for ever while the round waited for it (#950).
## A new route that is `FLIP` metres longer than what is left of the old one is not taken while the
## old one still ends within `KEEP` of the target; one that is nearly walked is let go.
##
## The same for two ways of one length round an obstacle (#1347): the mesh's search names one way
## from one side of a diagonal strip and the other from both sides of it, so a slow dead (a crawler
## by the drive-in's ticket booth: 1.2 m/s, 0.3 m between two repaths) walked out of the strip along
## the one and back into it along the other, and stood there for six minutes. A new route that sends
## it back the way it is going (`turns_back`) is not taken unless it is `GAIN` metres shorter than
## what is left of the old one, while the old one still ends near the target and the zombie is on
## it. A route that goes on the same way is taken as ever, so a crowd still spreads. `hold_back`
## false (`ZombieSim.hold_back_routes`, for a test that measures its cost) drops that second rule.
static func keeps(
	zombie: ZombieBody, found: PackedVector3Array, target_pos: Vector3, hold_back := true
) -> bool:
	if zombie.path.is_empty() or found.is_empty():
		return false
	if _flat(zombie.path[-1], target_pos) > KEEP:
		return false
	var left := length_left(zombie)
	if left < ARRIVED:
		return false
	var length := length_of(found)
	if length > left + FLIP:
		return true
	return hold_back and length > left - GAIN and turns_back(zombie, found)


## Whether `found` sends the zombie back the way its route has it going: the first leg of the new
## route points against the leg it walks, and the zombie is still on that leg (a zombie the crowd
## shoved off its route has no way to keep).
static func turns_back(zombie: ZombieBody, found: PackedVector3Array) -> bool:
	var path := zombie.path
	var to_index := mini(zombie.path_index, path.size() - 1)
	var from_index := maxi(to_index - 1, 0)
	var here := Vector2(zombie.position.x, zombie.position.z)
	var from := Vector2(path[from_index].x, path[from_index].z)
	var to := Vector2(path[to_index].x, path[to_index].z)
	if here.distance_to(Geometry2D.get_closest_point_to_segment(here, from, to)) > STRAY:
		return false
	var going := to - here
	if going.length() < LEG_LEAST and to_index + 1 < path.size():
		going = Vector2(path[to_index + 1].x, path[to_index + 1].z) - here
	for point in found:
		var leg := Vector2(point.x, point.z) - here
		if leg.length() >= LEG_LEAST:
			return going.dot(leg) < 0.0
	return false


## Metres of the zombie's path still to walk, from where it stands.
static func length_left(zombie: ZombieBody) -> float:
	var path := zombie.path
	var index := mini(zombie.path_index, path.size() - 1)
	var length := _flat(zombie.position, path[index])
	for i in range(index + 1, path.size()):
		length += _flat(path[i - 1], path[i])
	return length


static func length_of(path: PackedVector3Array) -> float:
	var length := 0.0
	for i in range(1, path.size()):
		length += _flat(path[i - 1], path[i])
	return length


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
