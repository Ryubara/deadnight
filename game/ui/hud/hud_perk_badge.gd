class_name HudPerkBadge
extends Control
## One perk had, as a small square badge: the machine's emblem drawn flat in the machine's own
## glow on a dark ground of its body colour (`PerkMachine.LOOKS`, the soda fountain's heart), so the
## drink that was bought is the picture that is read, with no word to read. A ticket's cut corner
## and hard shadow, like the slot cells beside the ammo card.

enum Glyph { BOTTLE, BULLETS, DRUM, GUNS, CROSS, BOLT, HEART }

## The badge's side, canvas units.
const SIDE := 52.0
const NOTCH := HudStyle.NOTCH * 0.6
## How much darker than the machine's body the ground is, so the glow carries the picture.
const GROUND_DARKEN := 0.5

## The look of each tonic of the default shop: {glyph, ground, glow}.
static var _looks: Dictionary[StringName, Dictionary] = {}

var tonic_id: StringName = &""

var _tokens := UITokens.active()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIDE, SIDE)
	size = Vector2(SIDE, SIDE)


func show_tonic(id: StringName) -> void:
	tonic_id = id
	queue_redraw()


## What a tonic looks like on its badge. A tonic the game has no emblem for gets the plain bottle.
static func look_of(id: StringName) -> Dictionary:
	if _looks.is_empty():
		_build_looks()
	return _looks.get(id, _looks[&""])


## The picture a tonic's badge draws.
static func glyph_of(id: StringName) -> Glyph:
	return look_of(id)["glyph"]


static func _build_looks() -> void:
	var glyphs := {
		&"double_shot": Glyph.BULLETS,
		&"quick_load": Glyph.DRUM,
		&"third_holster": Glyph.GUNS,
		&"swift_rescue": Glyph.CROSS,
		&"reload_shock": Glyph.BOLT,
	}
	for key: StringName in PerkMachine.LOOKS:
		var machine: Dictionary = PerkMachine.LOOKS[key]
		_looks[StringName(machine["item"])] = {
			"glyph": glyphs[key],
			"ground": (machine["body"] as Color).darkened(GROUND_DARKEN),
			"glow": machine["glow"],
		}
	_looks[&"tonic_hearty"] = {
		"glyph": Glyph.HEART,
		"ground": SodaFountain.RED.darkened(GROUND_DARKEN),
		"glow": Color(1.0, 0.62, 0.7),
	}
	_looks[&""] = {
		"glyph": Glyph.BOTTLE,
		"ground": Color(0.2, 0.2, 0.24),
		"glow": SodaFountain.CREAM,
	}


func _draw() -> void:
	var look := look_of(tonic_id)
	var rect := Rect2(Vector2.ZERO, size)
	var outline := HudStyle.ticket_points(rect, NOTCH)
	var shadow := PackedVector2Array()
	for point in outline:
		shadow.append(point + HudStyle.SHADOW * 0.75)
	var ground: Color = look["ground"]
	var glow: Color = look["glow"]
	var edge := outline.duplicate()
	edge.append(outline[0])
	# The frame and the emblem are one command (`HudShapes`), not one for each shape of them.
	var shapes := HudShapes.new()
	shapes.polygon(shadow, _tokens.shadow)
	shapes.polygon(outline, ground)
	shapes.polyline(edge, glow.darkened(0.25), float(_tokens.border))
	_draw_glyph(shapes, look["glyph"], rect.get_center(), size.x, glow, ground)
	shapes.flush(self)
	if look["glyph"] == Glyph.CROSS:
		# A smoothed ring, last: it stays a command of its own.
		draw_arc(rect.get_center(), 0.36 * size.x, 0.0, TAU, 32, glow, 2.5, true)


## The emblem, in a square of side `u` round `c`: `ink` for the picture, `ground` for what is cut
## out of it.
func _draw_glyph(
	shapes: HudShapes, glyph: Glyph, c: Vector2, u: float, ink: Color, ground: Color
) -> void:
	match glyph:
		Glyph.BULLETS:
			for sx in [-0.2, 0.2]:
				var x: float = c.x + sx * u
				shapes.rect(Rect2(x - 0.1 * u, c.y - 0.08 * u, 0.2 * u, 0.34 * u), ink)
				(
					shapes
					. polygon(
						PackedVector2Array(
							[
								Vector2(x - 0.1 * u, c.y - 0.08 * u),
								Vector2(x - 0.07 * u, c.y - 0.24 * u),
								Vector2(x, c.y - 0.34 * u),
								Vector2(x + 0.07 * u, c.y - 0.24 * u),
								Vector2(x + 0.1 * u, c.y - 0.08 * u),
							]
						),
						ink
					)
				)
				shapes.rect(
					Rect2(x - 0.12 * u, c.y + 0.26 * u, 0.24 * u, 0.05 * u), ink.lightened(0.3)
				)
				shapes.line(
					Vector2(x - 0.1 * u, c.y - 0.04 * u),
					Vector2(x + 0.1 * u, c.y - 0.04 * u),
					ground,
					2.0
				)
		Glyph.DRUM:
			shapes.circle(c, 0.34 * u, ink)
			for i in 6:
				var angle := TAU * float(i) / 6.0
				shapes.circle(c + Vector2(cos(angle), sin(angle)) * 0.2 * u, 0.065 * u, ground)
			shapes.circle(c, 0.05 * u, ground)
		Glyph.GUNS:
			for i in 3:
				var y: float = c.y + (float(i) - 1.0) * 0.24 * u
				shapes.rect(Rect2(c.x - 0.32 * u, y - 0.04 * u, 0.62 * u, 0.08 * u), ink)
				(
					shapes
					. polygon(
						PackedVector2Array(
							[
								Vector2(c.x - 0.32 * u, y),
								Vector2(c.x - 0.16 * u, y),
								Vector2(c.x - 0.2 * u, y + 0.15 * u),
								Vector2(c.x - 0.3 * u, y + 0.15 * u),
							]
						),
						ink
					)
				)
		Glyph.CROSS:
			var arm := 0.12 * u
			var reach := 0.24 * u
			shapes.rect(Rect2(c.x - reach, c.y - arm, reach * 2.0, arm * 2.0), ink)
			shapes.rect(Rect2(c.x - arm, c.y - reach, arm * 2.0, reach * 2.0), ink)
		Glyph.BOLT:
			(
				shapes
				. polygon(
					PackedVector2Array(
						[
							Vector2(c.x + 0.08 * u, c.y - 0.38 * u),
							Vector2(c.x - 0.2 * u, c.y + 0.04 * u),
							Vector2(c.x - 0.02 * u, c.y + 0.04 * u),
							Vector2(c.x - 0.1 * u, c.y + 0.38 * u),
							Vector2(c.x + 0.2 * u, c.y - 0.08 * u),
							Vector2(c.x + 0.02 * u, c.y - 0.08 * u),
						]
					),
					ink
				)
			)
		Glyph.HEART:
			var lobe := 0.17 * u
			shapes.circle(c + Vector2(-0.15 * u, -0.1 * u), lobe, ink)
			shapes.circle(c + Vector2(0.15 * u, -0.1 * u), lobe, ink)
			(
				shapes
				. polygon(
					PackedVector2Array(
						[
							c + Vector2(-0.31 * u, -0.04 * u),
							c + Vector2(0.31 * u, -0.04 * u),
							c + Vector2(0.0, 0.34 * u),
						]
					),
					ink
				)
			)
		_:
			shapes.rect(Rect2(c.x - 0.08 * u, c.y - 0.32 * u, 0.16 * u, 0.14 * u), ink)
			shapes.rect(Rect2(c.x - 0.18 * u, c.y - 0.18 * u, 0.36 * u, 0.5 * u), ink)
