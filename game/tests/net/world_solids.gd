class_name WorldSolids
extends RefCounted
## The solid things a player's body can bump into under a node (a world's viewport), one line each,
## sorted: kind, layer and place. A client and a server that play one night must list the same
## lines, or one of them has a wall the other walks through (#748, #760).


## Every static body and colliding CSG shape under `root` whose layer is in `mask`. Bodies that move
## (players, zombies' stand-ins) and areas are not walls.
static func of(root: Node, mask: int) -> Array[String]:
	var found: Array[String] = []
	for node in root.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if body is CharacterBody3D or body is Area3D or body.collision_layer & mask == 0:
			continue
		found.append(_line(body, body.collision_layer))
	for node in root.find_children("*", "CSGShape3D", true, false):
		var csg := node as CSGShape3D
		if csg.use_collision and csg.collision_layer & mask != 0:
			found.append(_line(csg, csg.collision_layer))
	found.sort()
	return found


## What `a` has that `b` has not ("+ line"), and what `b` has that `a` has not ("- line").
static func differences(a: Array[String], b: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var rest := b.duplicate()
	for line in a:
		var at := rest.find(line)
		if at < 0:
			out.append("+ " + line)
		else:
			rest.remove_at(at)
	for line in rest:
		out.append("- " + line)
	return out


static func _line(node: Node3D, layer: int) -> String:
	var at := node.global_position
	return (
		"%s %s layer %d at (%.2f, %.2f, %.2f)"
		% [node.get_class(), node.name, layer, at.x, at.y, at.z]
	)
