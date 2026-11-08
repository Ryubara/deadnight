class_name WeaponFit
extends RefCounted
## How a weapon's size fits the Soldier's hand (Deadnight #460: the maintainer pointed out hands too
## big for some guns), from the model's hand sockets and its triangles, at a `model_scale`:
##
## - `grip`: the handle below the trigger finger (from the `Trigger`'s level down the `Grip`
##   socket's line to the butt) over the Soldier's fingers below the index (middle and pinky,
##   `HAND_BELOW_INDEX`). A real pistol grip is about the three fingers under the trigger finger:
##   1.0. Under 1 the pinky hangs off the butt and the fist swallows the gun.
## - `guard`: the trigger guard's opening in front of the trigger (frame to guard, up and down)
##   over the index finger's thickness (`INDEX_THICKNESS`): under 1 the finger cannot go in.
## - `length`: the length in the game over the Soldier's height (1.4 m).
##
## Docs: docs/design/weapon-hold.md, "The size rule".

## The Soldier's hand in the game (0.8 scale), measured on the skin (`measure_weapon_fit.gd`): from
## the index knuckle's level down to the pinky's underside, and the index finger's thickness.
const HAND_BELOW_INDEX := 0.167
const INDEX_THICKNESS := 0.057
const CHARACTER_SCALE := 0.8
const CHARACTER_HEIGHT := 1.4


## {grip, guard, length} for the model at `model_scale` (a ratio is -1 when the model has no
## such part).
static func measure(model: Node3D, model_scale: float, model_length: float) -> Dictionary:
	var tris := _triangles(model)
	var world := model_scale * CHARACTER_SCALE
	var out := {"grip": -1.0, "guard": -1.0, "length": model_length * world / CHARACTER_HEIGHT}
	var grip: Variant = GripSolver.socket(model, "Grip")
	var trigger: Variant = GripSolver.socket(model, "Trigger")
	if grip == null or trigger == null:
		return out
	var g: Transform3D = grip
	var up := g.basis.y.normalized()
	var top := ((trigger as Transform3D).origin - g.origin).dot(up)
	var butt := top
	for p in tris:
		var along := (p - g.origin).dot(up)
		var off := (p - g.origin - up * along).length()
		if off < 0.06 and along < top:
			butt = minf(butt, along)
	out.grip = (top - butt) * world / HAND_BELOW_INDEX
	# The guard: up and down from just in front of the trigger to the first surface each way.
	var at: Vector3 = (trigger as Transform3D).origin + Vector3(-0.008, 0.0, 0.0)
	var gap := _hit(tris, at, Vector3.UP) + _hit(tris, at, Vector3.DOWN)
	out.guard = gap * world / INDEX_THICKNESS
	return out


static func _triangles(model: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var inverse := model.global_transform.affine_inverse()
	for node in [model] + model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var to_model := inverse * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in indices:
				out.append(to_model * vertices[i])
	return out


## Distance along `direction` from `origin` to the first triangle (a large number when none).
static func _hit(tris: PackedVector3Array, origin: Vector3, direction: Vector3) -> float:
	var best := 10.0
	for t in tris.size() / 3:
		var a := tris[t * 3]
		var e1 := tris[t * 3 + 1] - a
		var e2 := tris[t * 3 + 2] - a
		var p := direction.cross(e2)
		var det := e1.dot(p)
		if absf(det) < 1e-12:
			continue
		var s := origin - a
		var u := s.dot(p) / det
		if u < 0.0 or u > 1.0:
			continue
		var q := s.cross(e1)
		var v := direction.dot(q) / det
		if v < 0.0 or u + v > 1.0:
			continue
		var d := e2.dot(q) / det
		if d > 0.0:
			best = minf(best, d)
	return best
