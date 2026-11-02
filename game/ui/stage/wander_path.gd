class_name WanderPath
extends RefCounted
## A closed loop of waypoints walked at a steady speed: where the walker is and which way it faces
## at a time. Pure arithmetic on the clock, so it needs no navigation mesh and no physics, and the
## same time always gives the same place.

var points: Array[Vector3] = []
var speed := 0.8

var _lengths: Array[float] = []
var _total := 0.0


func _init(loop: Array[Vector3], walk_speed: float) -> void:
	points = loop
	speed = walk_speed
	for index in points.size():
		var length := points[index].distance_to(points[(index + 1) % points.size()])
		_lengths.append(length)
		_total += length


## Seconds one lap takes.
func lap_time() -> float:
	return _total / speed


## The place after `seconds` of walking from the first point (laps repeat).
func position_at(seconds: float) -> Vector3:
	var along := fposmod(seconds * speed, _total)
	for index in points.size():
		if along <= _lengths[index]:
			var from := points[index]
			var to := points[(index + 1) % points.size()]
			return from.lerp(to, along / maxf(_lengths[index], 0.0001))
		along -= _lengths[index]
	return points[0]


## The direction (a unit vector on the ground) the walker faces at `seconds`.
func heading_at(seconds: float) -> Vector3:
	var along := fposmod(seconds * speed, _total)
	for index in points.size():
		if along <= _lengths[index]:
			var way := points[(index + 1) % points.size()] - points[index]
			way.y = 0.0
			return way.normalized()
		along -= _lengths[index]
	return Vector3.FORWARD
