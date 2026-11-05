class_name PlateShapes
extends RefCounted
## The small vocabulary the plate's art is built from: flat polygons in a role colour, in a 100 by
## 100 box. A shape is `{"p": PackedVector2Array, "r": role}`; the roles are the four colours of a
## palette (`PlatePalettes`). Calling cards and emblems are both made of the same parts
## (`PlateMotifs`), so about forty pieces are a week of art and not forty paintings.

## The four colours a palette gives a piece.
enum Role { BASE, LIGHT, DARK, GROUND }

## Corners of a circle: enough to look round at the biggest size a piece is drawn.
const CIRCLE_CORNERS := 24


static func shape(points: PackedVector2Array, role: Role) -> Dictionary:
	return {"p": points, "r": role}


static func rect(x: float, y: float, w: float, h: float, role: Role) -> Dictionary:
	return shape(
		PackedVector2Array(
			[Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]
		),
		role
	)


static func poly(flat: Array, role: Role) -> Dictionary:
	var points := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		points.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return shape(points, role)


static func ellipse(centre: Vector2, radii: Vector2, role: Role) -> Dictionary:
	var points := PackedVector2Array()
	for i in CIRCLE_CORNERS:
		var angle := TAU * float(i) / float(CIRCLE_CORNERS)
		points.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return shape(points, role)


static func circle(centre: Vector2, radius: float, role: Role) -> Dictionary:
	return ellipse(centre, Vector2.ONE * radius, role)


## A slanted bar from `a` to `b`, `width` thick.
static func bar(a: Vector2, b: Vector2, width: float, role: Role) -> Dictionary:
	var side := (b - a).orthogonal().normalized() * width * 0.5
	return shape(PackedVector2Array([a + side, b + side, b - side, a - side]), role)


## `shapes` moved by `offset` and scaled by `factor` about the origin.
static func placed(shapes: Array[Dictionary], offset: Vector2, factor: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in shapes:
		var moved := PackedVector2Array()
		for point in item["p"] as PackedVector2Array:
			moved.append(point * factor + offset)
		out.append({"p": moved, "r": item["r"]})
	return out
