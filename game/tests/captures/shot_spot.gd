class_name ShotSpot
extends RefCounted
## A place in the night's lot for a capture of a shot: open sky overhead, room round the shoulder
## camera, a long free line to fire along and a wall four to six metres off. Found by looking over
## the ground with rays round the player's start (physics layer 1), so it follows the lot as it
## changes. Used by the shot captures and the muzzle-flash probe.

## Height of the chest above the feet, where the shots start from.
const CHEST := 1.1

var stand := Vector3.ZERO
var free_yaw := 0.0
var wall_yaw := 0.0
var wall_hit := Vector3.ZERO
var wall_distance := 0.0


## The spot nearest `player`, or null when the lot has none.
static func find(player: Node3D) -> ShotSpot:
	var spot := ShotSpot.new()
	var space := player.get_world_3d().direct_space_state
	var origin := player.global_position
	for ring in range(0, 40, 3):
		for step in maxi(1, ring * 2):
			var angle := TAU * float(step) / float(maxi(1, ring * 2))
			var at := Vector3(sin(angle), 0.0, cos(angle)) * float(ring) + origin
			if spot._try(space, at):
				return spot
	return spot


func _try(space: PhysicsDirectSpaceState3D, spot: Vector3) -> bool:
	var down := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 2.0, spot + Vector3.DOWN * 3.0, 1)
	)
	if down.is_empty() or absf(down["normal"].y) < 0.9 or absf(down["position"].y) > 0.15:
		return false
	var feet: Vector3 = down["position"]
	# Under the open sky: not inside a building or under the screen.
	if not (
		space
		. intersect_ray(
			PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.5, feet + Vector3.UP * 12.0, 1)
		)
		. is_empty()
	):
		return false
	var from := feet + Vector3(0.0, CHEST, 0.0)
	var free := -1.0
	var wall := -1.0
	var hit_at := Vector3.ZERO
	var wall_away := 0.0
	for step in 24:
		var yaw := TAU * float(step) / 24.0
		var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, from + dir * 30.0, 1)
		)
		var distance := 30.0 if hit.is_empty() else from.distance_to(hit["position"])
		# Room for the camera behind: the opposite ray is free for 3 m.
		if distance >= 12.0 and free < 0.0:
			free = yaw
		if (
			not hit.is_empty()
			and distance >= 4.0
			and distance <= 6.0
			and absf(hit["normal"].y) < 0.2
		):
			wall = yaw
			hit_at = hit["position"]
			wall_away = distance
	if free < 0.0 or wall < 0.0:
		return false
	for step in 8:
		var back := Vector3(sin(TAU * step / 8.0), 0.0, cos(TAU * step / 8.0))
		if (
			(
				space
				. intersect_ray(PhysicsRayQueryParameters3D.create(from, from + back * 3.2, 1))
				. size()
			)
			> 0
		):
			return false
	stand = feet
	free_yaw = free
	wall_yaw = wall
	wall_hit = hit_at
	wall_distance = wall_away
	return true
