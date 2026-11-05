class_name TouchIcons
extends RefCounted
## The pictures on the touch buttons (#1277): every control shows one, no words. They are drawn in
## code, no file, so there is no art to license and they scale and recolour with the button:
## `TouchIcons.add` adds the shapes of one icon to a `HudShapes`, and `TouchControls` flushes all of
## them as ONE canvas command (a polygon or a polyline of its own each would be a draw call each in
## the Compatibility renderer, redrawn whenever a finger moves a stick).
##
## An icon is drawn in a box of [-1, 1] on both axes, scaled to `ICON_SHARE` of the button's radius.
## It is a plain, heavy shape in the button's ink, read at a glance with a thumb over it:
## Fire a bullet, Aim a scope, Jump two chevrons up, Crouch a chevron down onto the floor, Reload a
## circle of arrow, Swap two arrows across, the Grenade a grenade, Side a person with an arrow each
## way, Melee a blade, Ping a pin, Pause two bars, Scoreboard the rows of a table.
## Interact is the one that keeps a word (`TouchControls`); it has a tap mark above it.

## How much of the button's radius the icon's box takes: a little over half, so the rim and the
## shadow keep their ground round it.
const ICON_SHARE := 0.64
## The stroke of a line, in icon units (the box is 2 wide).
const STROKE := 0.2
const THIN := 0.12
const ARC_STEP_DEGREES := 15.0

## The buttons that have an icon, in the order of the controls' table.
const IDS: Array[StringName] = [
	TouchLayout.FIRE,
	TouchLayout.AIM,
	TouchLayout.JUMP,
	TouchLayout.CROUCH,
	TouchLayout.RELOAD,
	TouchLayout.SHOULDER,
	TouchLayout.STRIKE,
	TouchLayout.PING,
	TouchLayout.PAUSE,
	TouchLayout.SCOREBOARD,
	TouchLayout.INTERACT,
]


## True when `id` has an icon.
static func has_icon(id: StringName) -> bool:
	return id in IDS


## Adds the icon of `id` to `shapes`, centred on `centre` for a button of `radius`. `ink` is its
## colour and `ground` the button's fill, for the parts that are a hole in a shape (the pin's eye).
static func add(
	shapes: HudShapes, id: StringName, centre: Vector2, radius: float, ink: Color, ground: Color
) -> void:
	var box := _Box.new(shapes, centre, radius * ICON_SHARE, ink, ground)
	match id:
		TouchLayout.FIRE:
			_fire(box)
		TouchLayout.AIM:
			_aim(box)
		TouchLayout.JUMP:
			_jump(box)
		TouchLayout.CROUCH:
			_crouch(box)
		TouchLayout.RELOAD:
			_reload(box)
		TouchLayout.SHOULDER:
			_shoulder(box)
		TouchLayout.STRIKE:
			_melee(box)
		TouchLayout.PING:
			_ping(box)
		TouchLayout.PAUSE:
			_pause(box)
		TouchLayout.SCOREBOARD:
			_scoreboard(box)
		TouchLayout.INTERACT:
			_tap(box)


static func _fire(box: _Box) -> void:
	# A bullet standing up: the ogive, then the case with its rim.
	(
		box
		. poly(
			[
				Vector2(0.0, -1.0),
				Vector2(0.17, -0.82),
				Vector2(0.3, -0.45),
				Vector2(0.3, -0.05),
				Vector2(-0.3, -0.05),
				Vector2(-0.3, -0.45),
				Vector2(-0.17, -0.82),
			]
		)
	)
	box.rect(Vector2(-0.3, 0.07), Vector2(0.3, 0.72))
	box.rect(Vector2(-0.42, 0.78), Vector2(0.42, 0.95))


static func _aim(box: _Box) -> void:
	box.ring(Vector2.ZERO, 0.58, STROKE)
	box.dot(Vector2.ZERO, 0.14)
	for angle in [0.0, 90.0, 180.0, 270.0]:
		var way := Vector2.RIGHT.rotated(deg_to_rad(angle))
		box.line(way * 0.42, way * 1.0, STROKE)


static func _jump(box: _Box) -> void:
	box.line_path([Vector2(-0.7, 0.05), Vector2(0.0, -0.65), Vector2(0.7, 0.05)], STROKE)
	box.line_path([Vector2(-0.7, 0.7), Vector2(0.0, 0.0), Vector2(0.7, 0.7)], STROKE)


static func _crouch(box: _Box) -> void:
	box.line_path([Vector2(-0.7, -0.75), Vector2(0.0, -0.05), Vector2(0.7, -0.75)], STROKE)
	box.line(Vector2(-0.85, 0.62), Vector2(0.85, 0.62), STROKE)


static func _reload(box: _Box) -> void:
	# Most of a circle, an arrowhead on its end.
	var from := 60.0
	var to := 345.0
	box.arc(Vector2.ZERO, 0.62, from, to, STROKE)
	var end := Vector2.RIGHT.rotated(deg_to_rad(to)) * 0.62
	var along := Vector2.RIGHT.rotated(deg_to_rad(to + 90.0))
	box.arrow_head(end + along * 0.16, along, 0.48)


static func _shoulder(box: _Box) -> void:
	# A person from behind, the camera's side moving either way over them.
	box.dot(Vector2(0.0, -0.08), 0.28)
	box.poly([Vector2(-0.52, 0.85), Vector2(-0.4, 0.32), Vector2(0.4, 0.32), Vector2(0.52, 0.85)])
	box.line(Vector2(-0.45, -0.72), Vector2(0.45, -0.72), THIN)
	box.arrow_head(Vector2(-0.95, -0.72), Vector2.LEFT, 0.4)
	box.arrow_head(Vector2(0.95, -0.72), Vector2.RIGHT, 0.4)


static func _melee(box: _Box) -> void:
	# A blade pointing up and to the right: blade, guard, grip, pommel.
	var turn := deg_to_rad(40.0)
	(
		box
		. poly_turned(
			[
				Vector2(0.0, -1.0),
				Vector2(0.2, -0.55),
				Vector2(0.2, 0.0),
				Vector2(-0.2, 0.0),
				Vector2(-0.2, -0.55),
			],
			turn
		)
	)
	box.poly_turned(
		[Vector2(-0.46, 0.04), Vector2(0.46, 0.04), Vector2(0.46, 0.2), Vector2(-0.46, 0.2)], turn
	)
	box.poly_turned(
		[Vector2(-0.1, 0.24), Vector2(0.1, 0.24), Vector2(0.1, 0.72), Vector2(-0.1, 0.72)], turn
	)
	box.dot(Vector2(0.0, 0.84).rotated(turn), 0.14)


static func _ping(box: _Box) -> void:
	# A map pin: a disc over a point, a hole where the eye is.
	box.dot(Vector2(0.0, -0.2), 0.55)
	box.poly([Vector2(-0.5, 0.02), Vector2(0.5, 0.02), Vector2(0.0, 0.98)])
	box.hole(Vector2(0.0, -0.2), 0.2)


static func _pause(box: _Box) -> void:
	box.rect(Vector2(-0.55, -0.7), Vector2(-0.15, 0.7))
	box.rect(Vector2(0.15, -0.7), Vector2(0.55, 0.7))


static func _scoreboard(box: _Box) -> void:
	# Three rows of a table: a dot and a line each.
	for row in 3:
		var y := (float(row) - 1.0) * 0.6
		box.dot(Vector2(-0.7, y), 0.14)
		box.rect(Vector2(-0.4, y - 0.1), Vector2(0.8, y + 0.1))


static func _tap(box: _Box) -> void:
	# A finger's tap mark (the prompt card's own): rings round a dot, up in the button where the
	# verb is not.
	var up := Vector2(0.0, -0.62)
	box.dot(up, 0.18)
	box.ring(up, 0.42, THIN)
	box.ring(up, 0.7, THIN)


## One icon's drawing space: where its [-1, 1] box is on the canvas and what it is drawn in.
class _Box:
	var shapes: HudShapes
	var centre: Vector2
	var scale: float
	var ink: Color
	var ground: Color

	func _init(into: HudShapes, at: Vector2, size: float, colour: Color, fill: Color) -> void:
		shapes = into
		centre = at
		scale = size
		ink = colour
		ground = fill

	func at(point: Vector2) -> Vector2:
		return centre + point * scale

	func poly(points: Array) -> void:
		poly_turned(points, 0.0)

	func poly_turned(points: Array, turn: float) -> void:
		var found := PackedVector2Array()
		for point: Vector2 in points:
			found.append(at(point.rotated(turn)))
		shapes.polygon(found, ink)

	func rect(from: Vector2, to: Vector2) -> void:
		shapes.rect(Rect2(at(from), (to - from) * scale), ink)

	func dot(point: Vector2, radius: float) -> void:
		shapes.circle(at(point), radius * scale, ink)

	func hole(point: Vector2, radius: float) -> void:
		shapes.circle(at(point), radius * scale, ground)

	func line(from: Vector2, to: Vector2, width: float) -> void:
		if from.is_equal_approx(to):
			return
		shapes.line(at(from), at(to), ink, width * scale)

	func line_path(points: Array, width: float) -> void:
		var found := PackedVector2Array()
		for point: Vector2 in points:
			found.append(at(point))
		shapes.polyline(found, ink, width * scale)

	func ring(point: Vector2, radius: float, width: float) -> void:
		arc(point, radius, 0.0, 360.0, width)

	func arc(point: Vector2, radius: float, from: float, to: float, width: float) -> void:
		var found := PackedVector2Array()
		var steps := maxi(int(ceilf(absf(to - from) / ARC_STEP_DEGREES)), 2)
		for step in steps + 1:
			var angle := deg_to_rad(lerpf(from, to, float(step) / float(steps)))
			found.append(at(point + Vector2.RIGHT.rotated(angle) * radius))
		shapes.polyline(found, ink, width * scale)

	## A solid triangle with its point at `tip`, aimed along `way`, `size` long.
	func arrow_head(tip: Vector2, way: Vector2, size: float) -> void:
		var side := way.orthogonal() * size * 0.55
		var back := tip - way * size
		shapes.polygon(PackedVector2Array([at(tip), at(back + side), at(back - side)]), ink)
