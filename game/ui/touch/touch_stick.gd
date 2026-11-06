class_name TouchStick
extends RefCounted
## One finger's move stick, from the touch that made it to the lift that ends it. The ring is drawn
## where the finger landed; a drag to the ring's edge walks at full walking speed, and a drag past
## the edge by `margin` starts a sprint that stays on until this finger lifts: the latch is a
## property of this object, which `TouchControls` keeps with the finger's touch, so it dies with
## the finger and a finger that reuses the index starts a new stick, walking (#1276).
##
## All distances are canvas units; the caller turns CSS pixels into units, so the edge is the
## same movement of the thumb on every phone. The edge is a circle: a drag past it sprints in
## any direction, because the body sprints in every direction (`PlayerSimulation`).

## Where the finger landed: the ring's centre. It moves only once the sprint is on.
var origin: Vector2
## Where the finger is now.
var pos: Vector2
## The sprint is on until the finger lifts.
var latched := false


func _init(point: Vector2) -> void:
	origin = point
	pos = point


## The finger moved to `point`. `radius` is the ring's, `margin` how far past it the sprint
## starts. True on the one move that starts the sprint.
func drag(point: Vector2, radius: float, margin: float) -> bool:
	pos = point
	var offset := pos - origin
	var started := false
	if not latched and offset.length() > radius + margin:
		latched = true
		started = true
	if latched and offset.length() > radius:
		# A latched finger may go anywhere: the ring follows it, one radius behind, so the thumb
		# never runs out of travel.
		origin += offset.normalized() * (offset.length() - radius)
	return started


## The move the finger asks for: a unit circle's worth, 1 at the edge and beyond, 0 inside the
## dead zone (a share of the radius).
func vector(radius: float, deadzone: float) -> Vector2:
	var raw := (pos - origin) / radius
	var length := raw.length()
	if length <= deadzone:
		return Vector2.ZERO
	return raw.normalized() * inverse_lerp(deadzone, 1.0, minf(length, 1.0))


## The knob, held inside the ring.
func knob(radius: float) -> Vector2:
	return origin + (pos - origin).limit_length(radius)
