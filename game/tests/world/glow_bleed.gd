class_name GlowBleed
extends RefCounted
## Where a glow or a light of a map shows on the far side of a wall from its lamp (issue #832;
## docs/research/glow-bleed.md). The Compatibility renderer casts no shadow, so every halo, pool
## and  wash is an additive quad that only the depth test hides, and every lamp is an unshadowed
## light:  either one reaches into the next room as soon as its card or its range does.
##
## `bleeding_cards` finds the card points that lie behind a wall seen from the lamp they belong to
## (the segment lamp to point crosses a solid), and the points of a card mounted on a wall that
## hang past the wall's edge (nothing behind them). `bleeding_lights` finds the surfaces a lamp
## lights through a wall: a point on a floor, a roof or a wall's face that the lamp's range and
## cull mask reach, that faces the lamp, with a solid between them.

## A wall box is shrunk by this on every side for the segment test, so a point on a wall's own
## face does  not count as behind it (`SKIN`, for a lit surface) and a card lying on a wall's face
## (1 cm off it) does  not count as inside it (`CARD_SKIN`).
const SKIN := 0.03
const CARD_SKIN := 0.005
## A card point is counted where the card's shader draws at least this share of its brightest.
const SHOWN := 0.05
## How far behind a wall-mounted card a wall must be for the point to count as on the wall.
const BACKED := 1.0
## A card whose centre is this near a wall's face is mounted on that wall.
const MOUNTED := 0.5
## Points across a triangle's edge, and the directions a billboard may face.
const GRID := 14
const BILLBOARD_YAWS := 8
## Receivers of light: the walls, and the ground and floors a lamp lights.
const RECEIVER_PREFIXES: Array[String] = [
	"Floor", "Ground", "Apron", "Plaza", "Alley", "Landing", "Ramp"
]
## A surface counts as lit through a wall where the lamp gives it at least this much (energy times
## the lamp's falloff times the angle to it).
const MIN_LIT := 0.15
## Spacing of the sample points over a box's faces.
const FACE_STEP := 1.0


## The wall boxes under `root` (`GlowClip.SOLID_PREFIXES`).
static func solids(root: Node) -> Array[CSGBox3D]:
	return GlowClip.walls(root)


## The wall the segment `from` to `to` passes through (each box shrunk by `skin`), or null.
static func blocked(walls: Array[CSGBox3D], from: Vector3, to: Vector3, skin := SKIN) -> CSGBox3D:
	for wall in walls:
		var inverse := wall.global_transform.affine_inverse()
		var half := wall.size * 0.5 - Vector3.ONE * skin
		if half.x <= 0.0 or half.y <= 0.0 or half.z <= 0.0:
			continue
		var box := AABB(-half, half * 2.0)
		if box.intersects_segment(inverse * from, inverse * to):
			return wall
	return null


## The glow meshes under `root`: an additive shader, or an additive standard material.
static func glow_cards(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var card := node as MeshInstance3D
		if card.mesh == null or not card.is_visible_in_tree():
			continue
		var material := card.material_override
		if material is ShaderMaterial:
			var shader := (material as ShaderMaterial).shader
			if shader != null and shader.code.contains("blend_add"):
				found.append(card)
		elif material is StandardMaterial3D:
			if (material as StandardMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
				found.append(card)
	return found


## The lamp a card belongs to: the light of its own fixture (a light under the same
## `LightFollower`),  else the card's own centre. A card that follows a lamp elsewhere (a window
## pane, the light under a  door, the projector's lens, a moon shaft) is a window in the wall by
## design, not a glow of the lamp.
static func source_of(card: MeshInstance3D) -> Vector3:
	var node: Node = card
	while node != null:
		if node is LightFollower:
			var light := node.get_node_or_null((node as LightFollower).light_path) as Light3D
			if light != null and node.is_ancestor_of(light) and not light is DirectionalLight3D:
				return light.global_position
			break
		node = node.get_parent()
	return card.global_transform * card.get_aabb().get_center()


## The world points of `card` where it draws a visible light, and whether it turns to the camera.
static func lit_points(card: MeshInstance3D) -> PackedVector3Array:
	var params := _params(card)
	if params.get("billboard", false):
		return _billboard_points(card, params)
	var points := PackedVector3Array()
	var mesh := card.mesh
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = (
			arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		)
		var indices: PackedInt32Array = (
			arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		)
		if indices.is_empty():
			for i in vertices.size():
				indices.append(i)
		for t in range(0, indices.size() - 2, 3):
			for i in GRID + 1:
				for j in GRID + 1 - i:
					var a := float(i) / GRID
					var b := float(j) / GRID
					var c := 1.0 - a - b
					var at := (
						vertices[indices[t]] * a
						+ vertices[indices[t + 1]] * b
						+ vertices[indices[t + 2]] * c
					)
					var uv := Vector2(0.5, 0.5)
					if uvs.size() == vertices.size():
						uv = uvs[indices[t]] * a + uvs[indices[t + 1]] * b + uvs[indices[t + 2]] * c
					var world := card.global_transform * at
					if _shape(uv, params) >= SHOWN and not _clipped(params, world):
						points.append(world)
	return points


static func _params(card: MeshInstance3D) -> Dictionary:
	var params := {}
	var material := card.material_override
	if material is ShaderMaterial:
		for name: String in ["billboard", "card", "edge", "falloff", "fade", "clip_a", "clip_b"]:
			var value: Variant = (material as ShaderMaterial).get_shader_parameter(name)
			if value != null:
				params[name] = value
	return params


## Whether the card's own clip planes (`GlowClip`) cut `point` away, as the shader does.
static func _clipped(params: Dictionary, point: Vector3) -> bool:
	for key: String in ["clip_a", "clip_b"]:
		var plane: Vector4 = params.get(key, Vector4.ZERO)
		var normal := Vector3(plane.x, plane.y, plane.z)
		if normal != Vector3.ZERO and point.dot(normal) > plane.w:
			return true
	return false


## The brightness `glow.gdshader` gives a point of UV, as a share of its brightest (1 for a mesh
## that is not a disc or a card: a haze, a pane).
static func _shape(uv: Vector2, params: Dictionary) -> float:
	if params.is_empty():
		return 1.0
	if params.get("card", false):
		var inside := Vector2(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))
		var soft := Vector2(
			maxf((params["edge"] as Vector2).x, 0.001), maxf((params["edge"] as Vector2).y, 0.001)
		)
		var shape := smoothstep(0.0, soft.x, inside.x) * smoothstep(0.0, soft.y, inside.y)
		return shape * (1.0 - float(params.get("fade", 0.0)) * uv.y)
	if not params.has("falloff"):
		return 1.0
	var r := clampf((uv * 2.0 - Vector2.ONE).length(), 0.0, 1.0)
	return pow(1.0 - r, float(params["falloff"]))


## A billboard turns to face the camera about its centre, so it can lie across any vertical plane
## through the centre: its horizontal half-size reaches in every horizontal direction.
static func _billboard_points(card: MeshInstance3D, params: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array()
	var half := card.mesh.get_aabb().size * 0.5
	var centre := card.global_transform * card.mesh.get_aabb().get_center()
	for yaw in BILLBOARD_YAWS:
		var across := Vector3.RIGHT.rotated(Vector3.UP, TAU * float(yaw) / BILLBOARD_YAWS)
		for i in GRID + 1:
			for j in GRID + 1:
				var sx := float(i) / GRID * 2.0 - 1.0
				var sy := float(j) / GRID * 2.0 - 1.0
				var world := centre + across * (sx * half.x) + Vector3.UP * (sy * half.y)
				if (
					_shape(Vector2(sx, sy) * 0.5 + Vector2(0.5, 0.5), params) >= SHOWN
					and not _clipped(params, world)
				):
					points.append(world)
	return points


## Every card of `root` that shows behind a wall, as "path: how".
static func bleeding_cards(root: Node, only: Array[MeshInstance3D] = []) -> Array[String]:
	var walls := solids(root)
	var found: Array[String] = []
	var cards := only if not only.is_empty() else glow_cards(root)
	for card in cards:
		var from := source_of(card)
		var points := lit_points(card)
		var through := 0
		var by := ""
		for point in points:
			# A point inside a wall's own thickness is hidden by the wall from both sides.
			if _buried(walls, null, point, -CARD_SKIN):
				continue
			var wall := blocked(walls, from, point, CARD_SKIN)
			if wall != null:
				through += 1
				by = String(wall.name)
		if through > 0:
			found.append(
				(
					"%s: %d of %d points lie behind %s"
					% [root.get_path_to(card), through, points.size(), by]
				)
			)
		var hang := _past_the_wall(GlowClip.walls(root, true), card, points)
		if hang > 0:
			found.append(
				(
					"%s: %d of %d points hang past the wall it is mounted on"
					% [root.get_path_to(card), hang, points.size()]
				)
			)
	return found


## A flat card whose centre is on a wall's face (`MOUNTED`): the points with no wall behind them
## (`BACKED`), which show in the air past the wall's edge or its top.
static func _past_the_wall(
	walls: Array[CSGBox3D], card: MeshInstance3D, points: PackedVector3Array
) -> int:
	if _params(card).get("billboard", false) or points.is_empty():
		return 0
	var normal := card.global_basis.z.normalized()
	if absf(normal.y) > 0.1:
		return 0
	var centre := card.global_transform * card.mesh.get_aabb().get_center()
	var back := _wall_behind(walls, centre, normal, MOUNTED)
	if back == Vector3.ZERO:
		back = _wall_behind(walls, centre, -normal, MOUNTED)
	if back == Vector3.ZERO:
		return 0
	var count := 0
	for point in points:
		if _wall_behind(walls, point, back, BACKED) == Vector3.ZERO:
			count += 1
	return count


## `direction` (or its opposite, whichever way a wall is) when a wall's face is within `reach` of
## `from` along it; ZERO when none is.
static func _wall_behind(
	walls: Array[CSGBox3D], from: Vector3, direction: Vector3, reach: float
) -> Vector3:
	for wall in walls:
		var inverse := wall.global_transform.affine_inverse()
		var box := AABB(-wall.size * 0.5, wall.size)
		if box.intersects_segment(
			inverse * from, inverse * (from + direction.normalized() * reach)
		):
			return direction.normalized()
	return Vector3.ZERO


static func receivers(root: Node) -> Array[CSGBox3D]:
	var found := solids(root)
	for node in root.find_children("*", "CSGBox3D", true, false):
		var box := node as CSGBox3D
		if not box.use_collision or not box.is_visible_in_tree() or found.has(box):
			continue
		for prefix in RECEIVER_PREFIXES:
			if String(box.name).begins_with(prefix):
				found.append(box)
				break
	return found


## Points over the faces of a box, as [point, normal] pairs in the world.
static func face_points(box: CSGBox3D) -> Array:
	var points := []
	var half := box.size * 0.5
	for axis in 3:
		for sign in [-1.0, 1.0]:
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var nu := maxi(1, int(ceil(box.size[u] / FACE_STEP)))
			var nv := maxi(1, int(ceil(box.size[v] / FACE_STEP)))
			for i in nu:
				for j in nv:
					var local := Vector3.ZERO
					local[axis] = half[axis] * sign
					local[u] = -half[u] + box.size[u] * (float(i) + 0.5) / nu
					local[v] = -half[v] + box.size[v] * (float(j) + 0.5) / nv
					var normal := Vector3.ZERO
					normal[axis] = sign
					points.append(
						[box.global_transform * local, (box.global_basis * normal).normalized()]
					)
	return points


## Whether a point lies inside a box (grown by `grow`, shrunk when negative): a joint between two
## tiles, not a  surface; a card point in a wall's thickness.
static func _buried(boxes: Array[CSGBox3D], own: CSGBox3D, point: Vector3, grow := SKIN) -> bool:
	for box in boxes:
		if box == own:
			continue
		var local := box.global_transform.affine_inverse() * point
		var half := box.size * 0.5 + Vector3.ONE * grow
		if absf(local.x) < half.x and absf(local.y) < half.y and absf(local.z) < half.z:
			return true
	return false


## How much light `light` gives a point of a surface facing `normal`: 0 beyond its reach.
static func light_at(light: Light3D, point: Vector3, normal: Vector3) -> float:
	var to_light := light.global_position - point
	var distance := to_light.length()
	if distance < 0.001:
		return 0.0
	var facing := normal.dot(to_light / distance)
	if facing <= 0.0:
		return 0.0
	if light is OmniLight3D:
		var omni := light as OmniLight3D
		if distance >= omni.omni_range:
			return 0.0
		return (
			light.light_energy
			* facing
			* pow(1.0 - distance / omni.omni_range, omni.omni_attenuation)
		)
	var spot := light as SpotLight3D
	if distance >= spot.spot_range:
		return 0.0
	var off_axis := rad_to_deg((-spot.global_basis.z).angle_to(-to_light))
	if off_axis >= spot.spot_angle:
		return 0.0
	return (
		light.light_energy * facing * pow(1.0 - distance / spot.spot_range, spot.spot_attenuation)
	)


## Every place a light of `root` lights a surface through a wall: `{"lamp", "surface", "wall",
## "points",  "peak"}` (the lamp's path, the box lit, the wall between, the sample points and the
## most light any of  them gets). Only lights that give at least `MIN_LIT` count, and only
## surfaces on the lamp's cull mask.  `lights` limits the lamps checked (default: every visible
## omni and spot).
static func light_leaks(root: Node, lights: Array[Light3D] = []) -> Array[Dictionary]:
	var walls := solids(root)
	var surfaces := []
	var boxes := receivers(root)
	for box in boxes:
		for entry in face_points(box):
			if not _buried(boxes, box, entry[0]):
				surfaces.append([box, entry[0], entry[1]])
	var lamps := lights
	if lamps.is_empty():
		for node in root.find_children("*", "Light3D", true, false):
			if (node is OmniLight3D or node is SpotLight3D) and (node as Light3D).visible:
				lamps.append(node)
	var found: Array[Dictionary] = []
	for lamp in lamps:
		var leaks := {}
		for entry in surfaces:
			var box: CSGBox3D = entry[0]
			if lamp.light_cull_mask & box.layers == 0:
				continue
			var lit := light_at(lamp, entry[1], entry[2])
			if lit < MIN_LIT:
				continue
			var wall := blocked(walls, lamp.global_position, entry[1])
			if wall == null:
				continue
			var key := "%s|%s" % [box.name, wall.name]
			if not leaks.has(key):
				leaks[key] = {
					"lamp": str(root.get_path_to(lamp)),
					"surface": String(box.name),
					"wall": String(wall.name),
					"points": 0,
					"peak": 0.0,
				}
			leaks[key]["points"] += 1
			leaks[key]["peak"] = maxf(leaks[key]["peak"], lit)
		found.append_array(leaks.values())
	return found


## `light_leaks` as lines of text, "path: lights surface through wall (points, peak)".
static func bleeding_lights(root: Node, lights: Array[Light3D] = []) -> Array[String]:
	var lines: Array[String] = []
	for leak in light_leaks(root, lights):
		lines.append(
			(
				"%s: lights %s through %s (%d points, up to %.2f)"
				% [leak["lamp"], leak["surface"], leak["wall"], leak["points"], leak["peak"]]
			)
		)
	return lines


## The most light each lamp gives a surface through a wall, by the lamp's path.
static func peaks(root: Node, lights: Array[Light3D] = []) -> Dictionary:
	var most := {}
	for leak in light_leaks(root, lights):
		most[leak["lamp"]] = maxf(float(most.get(leak["lamp"], 0.0)), leak["peak"])
	return most
