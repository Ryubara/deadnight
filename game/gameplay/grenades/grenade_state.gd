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

## The keys of `to_dict`, each with the type it must have.
const SNAPSHOT_KEYS := {
	"id": TYPE_INT,
	"thrower_id": TYPE_INT,
	"position": TYPE_VECTOR3,
	"velocity": TYPE_VECTOR3,
	"fuse_left": TYPE_FLOAT,
	"age": TYPE_FLOAT,
	"bounces": TYPE_INT,
	"grounded": TYPE_BOOL,
	"ground_normal": TYPE_VECTOR3,
	"at_rest": TYPE_BOOL,
}

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
## The contacts of the last step: `[{"point": Vector3, "speed": float, "wall": bool, "zombie_id":
## int}]` (`zombie_id` is -1 for the world).
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


## Everything that makes this grenade fly on exactly as it would have (the def is not in it).
func to_dict() -> Dictionary:
	return {
		"id": id,
		"thrower_id": thrower_id,
		"position": position,
		"velocity": velocity,
		"fuse_left": fuse_left,
		"age": age,
		"bounces": bounces,
		"grounded": grounded,
		"ground_normal": ground_normal,
		"at_rest": at_rest,
	}


## A grenade from `to_dict` data that has every key of `SNAPSHOT_KEYS` with its type.
static func from_dict(p_def: GrenadeDef, data: Dictionary) -> GrenadeState:
	var restored := GrenadeState.new(
		data["id"], data["thrower_id"], p_def, data["position"], data["velocity"], data["fuse_left"]
	)
	restored.age = data["age"]
	restored.bounces = data["bounces"]
	restored.grounded = data["grounded"]
	restored.ground_normal = data["ground_normal"]
	restored.at_rest = data["at_rest"]
	return restored


func is_spent() -> bool:
	return fuse_left <= 0.0


## Moves one fixed step and burns that much fuse. `bodies` is the zombies in the way, a Callable
## of the same shape as `cast` whose hits also carry `away` and `zombie_id` (`ZombieBump`); the
## server has it, a client's copy flies without it and is told where a zombie stopped it.
func step(delta: float, cast: Callable, bodies: Callable = Callable()) -> void:
	contacts = []
	fuse_left -= delta
	age += delta
	if at_rest:
		return
	if grounded:
		_roll(delta, cast, bodies)
	else:
		velocity += Vector3.DOWN * def.gravity * delta
		_travel(delta, cast, bodies)


## Flies for `time_left` seconds at the current velocity, bouncing off whatever is in the way.
## Stops early when the grenade lands.
func _travel(time_left: float, cast: Callable, bodies: Callable) -> void:
	for _i in MAX_CONTACTS:
		var motion := velocity * time_left
		var length := motion.length()
		if length <= 1e-7:
			return
		var dir := motion / length
		var to := position + dir * (length + def.radius)
		var hit: Dictionary = cast.call(position, to)
		if bodies.is_valid():
			var bumped: Dictionary = bodies.call(position, to)
			if not bumped.is_empty() and (hit.is_empty() or bumped["distance"] < hit["distance"]):
				hit = bumped
		if hit.is_empty() or hit["distance"] - def.radius > length:
			position += motion
			return
		var travelled := maxf(hit["distance"] - def.radius, 0.0)
		var normal: Vector3 = hit["normal"]
		position += dir * travelled + normal * SKIN
		time_left *= (length - travelled) / length
		if _bounce(normal, hit):
			return


## Handles one contact. Answers true when the grenade has landed (so the rest of the step is not
## spent in the air).
func _bounce(normal: Vector3, hit: Dictionary) -> bool:
	var normal_speed := velocity.dot(normal)
	if normal_speed >= 0.0:
		return false
	var tangent := velocity - normal * normal_speed
	bounces += 1
	if hit.has("zombie_id"):
		(
			contacts
			. append(
				{
					"point": position,
					"speed": -normal_speed,
					"wall": false,
					"zombie_id": hit["zombie_id"],
				}
			)
		)
		velocity = (
			tangent * def.zombie_slide
			- normal * normal_speed * def.zombie_restitution
			+ (hit["away"] as Vector3) * def.zombie_shove
		)
		return false
	var is_floor := normal.y >= FLOOR_Y
	contacts.append(
		{"point": position, "speed": -normal_speed, "wall": not is_floor, "zombie_id": -1}
	)
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
func _roll(delta: float, cast: Callable, bodies: Callable) -> void:
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
	_travel(delta, cast, bodies)
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
