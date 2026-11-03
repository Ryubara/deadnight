class_name ProjectileState
extends RefCounted
## A thrown or lobbed shot as simulated data: position, velocity, age. The server steps it on its
## fixed tick; clients draw a body that follows its `projectile_spawned` event. Not lag
## compensated: it flies in the present, against the targets as they are now.

var id: int = 0
var shooter_id: int = 0
var def: WeaponDef
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var age: float = 0.0


func _init(
	p_id: int, p_shooter_id: int, p_def: WeaponDef, p_position: Vector3, p_velocity: Vector3
) -> void:
	id = p_id
	shooter_id = p_shooter_id
	def = p_def
	position = p_position
	velocity = p_velocity


## Moves one fixed step. Answers `{}` while it flies, or `{"kind": &"target" | &"world" |
## &"expired", "point": Vector3, "target_id": int, "zone": StringName}` on the step it bursts.
func step(delta: float, targets: Dictionary, world_ray: Callable) -> Dictionary:
	var next_velocity := velocity + Vector3.DOWN * def.projectile_gravity * delta
	var motion := next_velocity * delta
	var length := motion.length()
	if length > 0.0:
		var dir := motion / length
		var wall := -1.0
		if world_ray.is_valid():
			wall = world_ray.call(position, position + motion)
		var limit := length if wall < 0.0 else wall
		var best := {}
		var best_distance := limit
		for id_key in targets:
			var hit := Hitbox.ray_at(
				position, dir, best_distance, targets[id_key], def.projectile_radius
			)
			if not hit.is_empty():
				best_distance = hit["distance"]
				best = {
					"kind": &"target",
					"point": position + dir * best_distance,
					"target_id": id_key,
					"zone": hit["zone"],
				}
		if not best.is_empty():
			return best
		if wall >= 0.0:
			return {"kind": &"world", "point": position + dir * wall}
	position += motion
	velocity = next_velocity
	age += delta
	if age >= def.projectile_lifetime:
		return {"kind": &"expired", "point": position}
	return {}
