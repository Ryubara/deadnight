class_name MarkerProjection
extends RefCounted
## Where a point of the world falls on the screen of a camera, as the HUD wants it: a share of the
## screen (0 to 1 each way, outside that when the point is off to a side). A point behind the lens
## is not drawn where the projection mirrors it (that lands near the centre for a point straight
## behind): it goes on the side the point is on, and down, so the pin at the edge says which way to
## turn: straight behind is the bottom edge, behind and to the left is the left edge or the corner.

## How far from the centre (in screens) a point behind the camera is put: outside the screen along
## any direction.
const BEHIND_PUSH := 2.0


## `{"screen": Vector2, "behind": bool}`. `camera` must be in the tree.
static func project(camera: Camera3D, point: Vector3) -> Dictionary:
	var centre := Vector2(0.5, 0.5)
	if camera.is_position_behind(point):
		var local := camera.global_transform.affine_inverse() * point
		var away := Vector2(local.x, absf(local.z))
		return {"screen": centre + away.normalized() * BEHIND_PUSH, "behind": true}
	var size := camera.get_viewport().get_visible_rect().size
	return {"screen": camera.unproject_position(point) / size, "behind": false}
