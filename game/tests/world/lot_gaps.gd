class_name LotGaps
extends RefCounted
## Finds the slots a body can wedge in: two colliders of the lot that stand closer than a bot's body
## is wide but do not touch. Read from the greybox's collision boxes and cylinders as shapes on the
## ground plane (x, z), so the scan needs no physics frame. Hidden blocks (the machines') count:
## they collide.

## Colliders lower than this (metres, top above the ground) are floors and kerbs a body steps over.
const MIN_TOP := 0.4
## Colliders whose underside is higher than this are roofs and signs a body walks under.
const MAX_BOTTOM := 1.75
## Sides of the polygon a cylinder is read as.
const CYLINDER_SIDES := 12
## Narrower than this a body cannot get its foot in, so it is a seam, not a slot (metres).
const MIN_WIDTH := 0.24
## Shortest length two faces must run side by side to make a channel (metres).
const MIN_RUN := 0.5
## Area a piece must cover of a channel to count as standing in it (square metres).
const CLEAR_AREA := 0.01
## Largest sine of the angle between two faces that still face each other square.
const PARALLEL := 0.05


## Every channel between two walkable-height boxes under `lot`: two faces that face each other,
## run side by side for at least `MIN_RUN` metres and stand `MIN_WIDTH` to `max_width` apart. Each
## is `{a, b, width, run, at}` (`a` and `b` are paths from `lot`, `at` the middle of the channel on
## the ground plane). Round pieces are left out: a body slides off them.
static func channels(lot: Node3D, max_width: float) -> Array[Dictionary]:
	var pieces := _pieces(lot)
	var found: Array[Dictionary] = []
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			var a: Dictionary = pieces[i]
			var b: Dictionary = pieces[j]
			if not a["boxy"] or not b["boxy"] or _rect_gap(a["rect"], b["rect"]) > max_width:
				continue
			var best := _channel(a["polygon"], b["polygon"], max_width)
			if best.is_empty():
				best = _channel(b["polygon"], a["polygon"], max_width)
			if not best.is_empty() and not _blocked(best["quad"], [a, b], pieces):
				found.append(
					{
						"a": a["name"],
						"b": b["name"],
						"width": best["width"],
						"run": best["run"],
						"at": best["at"]
					}
				)
	return found


## Whether another piece stands in the channel `quad` (a wall between the two faces is not a slot).
static func _blocked(quad: PackedVector2Array, pair: Array, pieces: Array[Dictionary]) -> bool:
	for piece in pieces:
		if pair.has(piece):
			continue
		var inside := Geometry2D.intersect_polygons(quad, piece["polygon"])
		for part in inside:
			if _area(part) > CLEAR_AREA:
				return true
	return false


static func _area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for i in polygon.size():
		total += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(total) * 0.5


## The narrowest channel between a face of `a` and a face of `b` (both convex, counter-clockwise),
## or an empty dictionary.
static func _channel(a: PackedVector2Array, b: PackedVector2Array, max_width: float) -> Dictionary:
	var best := {}
	for i in a.size():
		var a0 := a[i]
		var a1 := a[(i + 1) % a.size()]
		var along := (a1 - a0).normalized()
		var out := Vector2(along.y, -along.x)
		for j in b.size():
			var b0 := b[j]
			var b1 := b[(j + 1) % b.size()]
			var other := (b1 - b0).normalized()
			if absf(along.cross(other)) > PARALLEL or along.dot(other) > 0.0:
				continue
			var width := (b0 - a0).dot(out)
			if width < MIN_WIDTH or width >= max_width:
				continue
			var low := maxf(0.0, minf((b0 - a0).dot(along), (b1 - a0).dot(along)))
			var high := minf((a1 - a0).length(), maxf((b0 - a0).dot(along), (b1 - a0).dot(along)))
			if high - low < MIN_RUN:
				continue
			if best.is_empty() or width < best["width"]:
				best = {
					"width": width,
					"run": high - low,
					"at": a0 + along * (low + high) * 0.5 + out * width * 0.5,
					"quad":
					PackedVector2Array(
						[
							a0 + along * low,
							a0 + along * high,
							a0 + along * high + out * width,
							a0 + along * low + out * width
						]
					)
				}
	return best


static func _pieces(lot: Node3D) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	for node in lot.find_children("*", "CSGShape3D", true, false):
		var shape := node as CSGShape3D
		if not shape.use_collision:
			continue
		var polygon := _polygon(shape)
		if polygon.is_empty():
			continue
		var height := _height(shape)
		var bottom := shape.global_position.y - height * 0.5
		if bottom + height < MIN_TOP or bottom > MAX_BOTTOM:
			continue
		var low := polygon[0]
		var high := polygon[0]
		for point in polygon:
			low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
			high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
		(
			pieces
			. append(
				{
					"name": String(lot.get_path_to(shape)),
					"polygon": polygon,
					"rect": Rect2(low, high - low),
					"boxy": shape is CSGBox3D,
				}
			)
		)
	return pieces


static func _height(shape: CSGShape3D) -> float:
	if shape is CSGBox3D:
		return (shape as CSGBox3D).size.y
	return (shape as CSGCylinder3D).height


## The shape's footprint on the ground plane, convex, in world x and z.
static func _polygon(shape: CSGShape3D) -> PackedVector2Array:
	var corners: Array[Vector3] = []
	if shape is CSGBox3D:
		var h := (shape as CSGBox3D).size * 0.5
		corners = [
			Vector3(-h.x, 0.0, -h.z),
			Vector3(h.x, 0.0, -h.z),
			Vector3(h.x, 0.0, h.z),
			Vector3(-h.x, 0.0, h.z),
		]
	elif shape is CSGCylinder3D:
		var radius := (shape as CSGCylinder3D).radius
		for i in CYLINDER_SIDES:
			var angle := TAU * i / CYLINDER_SIDES
			corners.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	var polygon := PackedVector2Array()
	for corner in corners:
		var world := shape.global_transform * corner
		polygon.append(Vector2(world.x, world.z))
	return polygon


## The gap between two axis-aligned rectangles (0 when they overlap).
static func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dy := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	return Vector2(dx, dy).length()
