class_name LotSwitches
extends RefCounted
## The lot's breaker posts (`CircuitSwitch`, under `Switches`): one for each circuit a player can
## switch. It finds them, shows each as the rules' generator has it, and answers the two questions
## the night asks: which post is within a player's reach, and where the bot should stand to use
## one. It decides nothing about the circuits; the rules do (`RulesAction.set_circuit`).

## A post to stand in front of, in metres out from it: close enough to be in `use_reach`.
const STAND_DISTANCE := 1.4

var _posts: Dictionary[StringName, CircuitSwitch] = {}


## Gathers the posts below `root`.
func _init(root: Node) -> void:
	for node in root.find_children("*", "CircuitSwitch", true, false):
		var post := node as CircuitSwitch
		_posts[StringName(post.get_meta(&"circuit"))] = post


## The circuits that have a post.
func circuit_ids() -> Array[StringName]:
	return _posts.keys()


func post(circuit_id: StringName) -> CircuitSwitch:
	return _posts.get(circuit_id)


## Shows every post as `generator` has its circuit.
func show_all(generator: GeneratorState) -> void:
	for circuit_id in _posts:
		_posts[circuit_id].set_on(generator.circuits.get(circuit_id, false))


## Follows a rules event: a circuit switched moves its post.
func follow(event: Dictionary) -> void:
	if event["type"] != &"circuit_changed":
		return
	var found: CircuitSwitch = _posts.get(StringName(event["circuit_id"]))
	if found != null:
		found.set_on(event["on"])


## The post nearest to `point` that lies within `reach` metres (flat) and, when `sight` is given, in
## reach of the hand without a wall between (#831), or null.
func within_reach(point: Vector3, reach: float, sight: UseSight = null) -> CircuitSwitch:
	var best: CircuitSwitch = null
	var best_distance := reach
	for circuit_id in _posts:
		var distance := _flat(point, _posts[circuit_id].global_position)
		if (
			distance <= best_distance
			and (
				sight == null
				or sight.clear_mounted(
					point, _posts[circuit_id].global_position, _posts[circuit_id].global_basis.z
				)
			)
		):
			best_distance = distance
			best = _posts[circuit_id]
	return best


## Where to stand to use the post of `circuit_id`.
func standing_point(circuit_id: StringName) -> Vector3:
	return _posts[circuit_id].standing_point(STAND_DISTANCE)


## The shop door of the area the circuit lights, or empty when it lights none.
func door_of(circuit_id: StringName) -> StringName:
	return _posts[circuit_id].door_id


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
