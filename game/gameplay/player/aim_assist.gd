class_name AimAssist
extends RefCounted
## What a thumb is helped with, as pure functions of plain data: no nodes, no physics server, so a
## bot and a test can run it against any crowd.
##
## Two helps, both only for touch: **friction** slows the look drag while the crosshair's ray
## passes near a zombie, and **magnetism** turns the view a little toward it while the player aims
## or fires. Both fade with the ray's distance from the aim point (the chest) and grow with the
## strength (0 to 1, the player's setting; 0 is off). A third, **auto-fire**, only answers whether
## the crosshair is on a zombie's hit zone, the same test a shot makes.
##
## `targets` is `[{"position": Vector3, "yaw": float, "scale": float}]`, the zombies as a client
## sees them (`scale`, the size of the hit zones, may be left out for 1). `sight` is
## `(from: Vector3, to: Vector3) -> float`, the distance to the first wall on the segment or -1.0
## (`WorldProbe.distance`); an invalid Callable means an empty world.


## The yaw and pitch (radians, the camera rig's convention) of a direction.
static func view_angles(dir: Vector3) -> Vector2:
	return Vector2(atan2(-dir.x, -dir.z), asin(clampf(dir.y, -1.0, 1.0)))


## How far the ray may pass from an aim point for the assist to act, at the walker's size.
static func capture_radius(strength: float, tuning: AimAssistTuning) -> float:
	return tuning.capture_metres * lerpf(tuning.capture_floor, 1.0, clampf(strength, 0.0, 1.0))


## The zombie the assist helps with, or `{}`: the one whose aim point the ray from `eye` along
## `dir` passes nearest, as a share of the capture, among those in reach, in front and in sight.
## Answers `{point, distance, lateral, closeness}`; `closeness` is 1 on the aim point and 0 at the
## edge of the capture.
static func pick(
	eye: Vector3,
	dir: Vector3,
	targets: Array,
	strength: float,
	tuning: AimAssistTuning,
	sight: Callable = Callable()
) -> Dictionary:
	if strength <= 0.0:
		return {}
	var radius := capture_radius(strength, tuning)
	var best := {}
	var best_share := 1.0
	for target: Dictionary in targets:
		var size: float = target.get("aim_scale", target.get("scale", 1.0))
		var point: Vector3 = target["position"] + Vector3.UP * tuning.aim_height * size
		var to_point := point - eye
		var distance := to_point.length()
		if distance < 0.5 or distance > tuning.reach:
			continue
		if dir.dot(to_point / distance) < tuning.front_cos:
			continue
		var lateral := to_point.cross(dir).length()
		var share := lateral / (radius * maxf(size, 0.6))
		if share >= best_share:
			continue
		if _walled(sight, eye, point, distance):
			continue
		best_share = share
		best = {
			"point": point,
			"distance": distance,
			"lateral": lateral,
			"closeness": 1.0 - share,
		}
	return best


## The factor on the look drag: 1 when nothing is near the ray, down to `1 - friction_max` at the
## middle of a zombie at full strength.
static func friction(found: Dictionary, strength: float, tuning: AimAssistTuning) -> float:
	if found.is_empty():
		return 1.0
	var closeness := smoothstep(0.0, 1.0, found["closeness"])
	return 1.0 - tuning.friction_max * clampf(strength, 0.0, 1.0) * closeness


## The turn, in radians (yaw, pitch added to the rig's), that closes part of the angle from the
## view (`eye` along `dir`) to the picked aim point in `delta` seconds. `own_speed`, how fast the
## player is turning the view themselves (radians per second), fades it out.
static func pull(
	eye: Vector3,
	dir: Vector3,
	found: Dictionary,
	strength: float,
	own_speed: float,
	delta: float,
	tuning: AimAssistTuning
) -> Vector2:
	if found.is_empty():
		return Vector2.ZERO
	var level := clampf(strength, 0.0, 1.0)
	var now := view_angles(dir)
	var wanted := view_angles(((found["point"] as Vector3) - eye).normalized())
	var error := Vector2(angle_difference(now.x, wanted.x), wanted.y - now.y)
	var own := 1.0 - smoothstep(tuning.flick_speed * 0.5, tuning.flick_speed, own_speed)
	var closeness := smoothstep(0.0, 1.0, found["closeness"])
	var share := minf(level * tuning.magnetism_gain * closeness * own * delta, 1.0)
	var step := error * share
	var cap := tuning.magnetism_max_rate * level * delta
	return step.limit_length(cap)


## The share of the shots a thumb misses that the assist wins back at `strength` (0 to 1): what the
## balance simulator adds to a modelled touch player. It is the thumb bot's measurement
## (`test_aim_assist_bot.gd`) in two numbers.
static func accuracy_gain(strength: float, tuning: AimAssistTuning) -> float:
	return tuning.accuracy_gain * pow(clampf(strength, 0.0, 1.0), tuning.accuracy_curve)


## A hit chance `base` with the assist at `strength`: the misses it wins back are added.
static func assisted_accuracy(base: float, strength: float, tuning: AimAssistTuning) -> float:
	return base + (1.0 - base) * accuracy_gain(strength, tuning)


## Whether the ray from `eye` along `dir` is on a zombie's hit zone within `reach` metres, with no
## wall in front of it: the crosshair is on a zombie, as a shot would find it.
static func on_target(
	eye: Vector3, dir: Vector3, targets: Array, reach: float, sight: Callable = Callable()
) -> bool:
	for target: Dictionary in targets:
		var hit := Hitbox.ray(
			eye,
			dir,
			reach,
			target["position"],
			target.get("yaw", 0.0),
			0.0,
			target.get("scale", 1.0),
			false,
			target.get("pose", Hitbox.DEFAULT_SET)
		)
		if hit.is_empty():
			continue
		var distance: float = hit["distance"]
		if not _walled(sight, eye, eye + dir * distance, distance):
			return true
	return false


static func _walled(sight: Callable, from: Vector3, to: Vector3, distance: float) -> bool:
	if not sight.is_valid():
		return false
	var wall: float = sight.call(from, to)
	return wall >= 0.0 and wall < distance - 0.3
