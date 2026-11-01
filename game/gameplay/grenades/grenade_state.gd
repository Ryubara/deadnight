class_name GrenadeState
extends RefCounted
## A grenade in flight as simulated data: position, velocity, the fuse left, and whether it rolls
## or rests. The server steps it on the fixed tick; a client steps a copy with the same code and
## the same `GrenadeDef`, so a prediction and the server land in the same place.
##
## The world is a `cast` Callable `(from: Vector3, to: Vector3) -> Dictionary`: `{}` when the
## segment is clear, else `{"distance": float, "normal": Vector3}` (distance from `from`). The
## grenade is a sphere: the segment is lengthened by its radius, so it touches with its surface.
## Nothing here reads a clock, a random number or the scene tree.

const MAX_CONTACTS := 4
## A contact leaves the sphere this far off the surface, so the next cast does not start inside it.
const SKIN := 0.002
## Floor normals this upright (y) count as ground a grenade can land on.
const FLOOR_Y := 0.7

var id: int = 0
var thrower_id: int = 0
var def: GrenadeDef
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var fuse_left: float = 0.0
var age: float = 0.0
var bounces: int = 0
## Resting on a floor (rolling or still); `ground_normal` is that floor's.
var grounded: bool = false
var ground_normal: Vector3 = Vector3.UP
## Still: a rolling grenade that has stopped.
var at_rest: bool = false
## The contacts of the last step: `[{"point": Vector3, "speed": float, "wall": bool}]`.
var contacts: Array[Dictionary] = []


func _init(
	p_id: int,
	p_thrower_id: int,
	p_def: GrenadeDef,
	p_position: Vector3,
	p_velocity: Vector3,
	p_fuse_left: float
) -> void:
	id = p_id
	thrower_id = p_thrower_id
	def = p_def
	position = p_position
	velocity = p_velocity
	fuse_left = p_fuse_left


func is_spent() -> bool:
	return fuse_left <= 0.0


## Moves one fixed step and burns that much fuse.
func step(delta: float, cast: Callable) -> void:
	contacts = []
	fuse_left -= delta
	age += delta
	if at_rest:
		return
	if grounded:
		_roll(delta, cast)
	else:
		velocity += Vector3.DOWN * def.gravity * delta
		_travel(delta, cast)


## Flies for `time_left` seconds at the current velocity, bouncing off whatever is in the way.
## Stops early when the grenade lands.
func _travel(time_left: float, cast: Callable) -> void:
	for _i in MAX_CONTACTS:
		var motion := velocity * time_left
		var length := motion.length()
		if length <= 1e-7:
			return
		var dir := motion / length
		var hit: Dictionary = cast.call(position, position + dir * (length + def.radius))
		if hit.is_empty() or hit["distance"] - def.radius > length:
			position += motion
			return
		var travelled := maxf(hit["distance"] - def.radius, 0.0)
		var normal: Vector3 = hit["normal"]
		position += dir * travelled + normal * SKIN
		time_left *= (length - travelled) / length
		if _bounce(normal):
			return


## Handles one contact. Answers true when the grenade has landed (so the rest of the step is not
## spent in the air).
func _bounce(normal: Vector3) -> bool:
	var normal_speed := velocity.dot(normal)
	if normal_speed >= 0.0:
		return false
	var is_floor := normal.y >= FLOOR_Y
	var tangent := velocity - normal * normal_speed
	bounces += 1
	contacts.append({"point": position, "speed": -normal_speed, "wall": not is_floor})
	if is_floor and -normal_speed < def.rest_speed:
		grounded = true
		ground_normal = normal
		velocity = tangent
		return true
	var keep := def.floor_restitution if is_floor else def.wall_restitution
	velocity = tangent * (1.0 - def.bounce_friction) - normal * normal_speed * keep
	return false


## Rolling on a floor: gravity along the slope, friction against the motion, then feel for the
## floor again (a ledge or a hole drops it back into the air).
func _roll(delta: float, cast: Callable) -> void:
	var gravity := Vector3.DOWN * def.gravity
	var along := gravity - ground_normal * gravity.dot(ground_normal)
	velocity += along * delta
	velocity -= ground_normal * velocity.dot(ground_normal)
	var speed := maxf(velocity.length() - def.roll_deceleration * delta, 0.0)
	velocity = velocity.normalized() * speed if speed > 0.0 else Vector3.ZERO
	if speed < def.stop_speed and along.length() < def.roll_deceleration:
		velocity = Vector3.ZERO
		at_rest = true
		return
	_travel(delta, cast)
	if not grounded:
		return
	var below: Dictionary = cast.call(
		position, position - ground_normal * (def.radius + def.ground_reach)
	)
	if below.is_empty():
		grounded = false
		return
	ground_normal = below["normal"]
	position -= ground_normal * (below["distance"] - def.radius - SKIN)
