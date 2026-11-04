class_name DeadBlock
extends RefCounted
## The dead stop the body (#914). A zombie is a circle on the ground (`DeadContactTuning.radius`);
## after the tick's slide, a body that ended inside one is put back on its edge and loses the speed
## it had into it, so it slides round the zombie as it would round a post.
##
## A one-way wall: a body may never get nearer to a zombie than it began the tick, but is not
## pushed out of one it already overlaps (a zombie that walked into it, a frame that moved the
## zombie). So a prediction that disagrees with the server by a few centimetres about where a zombie
## stands never fights the reconciler: neither side ever moves the body away on its own.
##
## It reads the field's positions, the tick's start and the push of the stick, and moves only the
## body: the same step gives the same body on a client and on the server.


## Stops `body` at the dead of `field`. `before` is where the tick began, `intent` the velocity the
## stick asks for (the speed of the stance along the wish), `body_radius` the body's own.
static func apply(
	body: CharacterBody3D,
	field: DeadField,
	before: Vector3,
	intent: Vector3,
	body_radius: float,
	body_height: float
) -> void:
	field.clear_touches()
	var tuning := field.tuning
	if not tuning.enabled or field.ids.is_empty():
		return
	var edge := body_radius + tuning.radius
	var touch := edge + tuning.touch_gap
	var correction := Vector3.ZERO
	var velocity := body.velocity
	var here := body.global_position
	for i in field.ids.size():
		var at := field.positions[i]
		var rise := here.y - at.y
		if rise >= tuning.reach_above or rise <= -minf(tuning.reach_below, body_height):
			continue
		var away := Vector3(here.x - at.x, 0.0, here.z - at.z)
		var distance := away.length()
		if distance >= touch:
			continue
		var normal := _normal(away, distance, field.ids[i], intent)
		var was := Vector2(before.x - at.x, before.z - at.z).length()
		var held := minf(edge, was)
		if distance < held:
			correction += normal * (held - distance)
			field.blocked = true
		var into := -velocity.dot(normal)
		if into > 0.0:
			velocity += normal * into
		field.touch_ids.append(field.ids[i])
		field.touch_normals.append(normal)
		field.touch_pushes.append(maxf(-intent.dot(normal), 0.0))
		field.touch_intents.append(
			intent.normalized() if intent.length_squared() > 0.0001 else -normal
		)
	body.velocity = velocity
	if correction != Vector3.ZERO:
		# Not through a wall: a body between a wall and a zombie stays at the wall.
		body.move_and_collide(correction)


## The flat unit vector from the zombie to the body. Standing on the same spot there is none: the
## body goes back the way the stick pushes it, or by the zombie's id.
static func _normal(away: Vector3, distance: float, zombie_id: int, intent: Vector3) -> Vector3:
	if distance > 0.001:
		return away / distance
	if intent.length_squared() > 0.0001:
		return -intent.normalized()
	var angle := float(zombie_id) * 2.399963
	return Vector3(cos(angle), 0.0, sin(angle))
