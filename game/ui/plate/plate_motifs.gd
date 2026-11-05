class_name PlateMotifs
extends RefCounted
## The parts a calling card or an emblem is composed from: a ticket, a reel, a car, a saucer,
## bulbs and so on, each a few flat shapes in a 100 by 100 box (`PlateShapes`), drawn in whatever
## palette the piece asks for. A card places one large; an emblem puts one in a disc.

const NAMES: Array[StringName] = [
	&"ticket",
	&"popcorn",
	&"reel",
	&"cup",
	&"strip",
	&"car",
	&"marquee",
	&"moon",
	&"saucer",
	&"star",
	&"skull",
	&"crosshair",
	&"planks",
	&"can",
	&"grenade",
	&"fist",
	&"crown",
	&"coins",
	&"hammer",
	&"door",
	&"target",
	&"rack",
	&"bolt",
]

## How far in a star's inner corners sit, as a share of its outer radius.
const STAR_INNER := 0.45

const _B := PlateShapes.Role.BASE
const _L := PlateShapes.Role.LIGHT
const _D := PlateShapes.Role.DARK
const _G := PlateShapes.Role.GROUND


static func has(motif: StringName) -> bool:
	return NAMES.has(motif)


## The shapes of a motif, back to front. An unknown name is a ticket.
static func shapes(motif: StringName) -> Array[Dictionary]:
	match motif:
		&"popcorn":
			return _popcorn()
		&"reel":
			return _reel()
		&"cup":
			return _cup()
		&"strip":
			return _strip()
		&"car":
			return _car()
		&"marquee":
			return _marquee()
		&"moon":
			return _moon()
		&"saucer":
			return _saucer()
		&"star":
			return _star(Vector2(50, 52), 46.0)
		&"skull":
			return _skull()
		&"crosshair":
			return _crosshair()
		&"planks":
			return _planks()
		&"can":
			return _can()
		&"grenade":
			return _grenade()
		&"fist":
			return _fist()
		&"crown":
			return _crown()
		&"coins":
			return _coins()
		&"hammer":
			return _hammer()
		&"door":
			return _door()
		&"target":
			return _target()
		&"rack":
			return _rack()
		&"bolt":
			return _bolt()
	return _ticket()


static func _ticket() -> Array[Dictionary]:
	var out: Array[Dictionary] = [PlateShapes.rect(8, 26, 84, 48, _B)]
	out.append(PlateShapes.circle(Vector2(8, 50), 9.0, _G))
	out.append(PlateShapes.circle(Vector2(92, 50), 9.0, _G))
	for i in 5:
		out.append(PlateShapes.rect(64, 31.0 + i * 8.5, 3, 5, _L))
	out.append(PlateShapes.rect(20, 36, 34, 6, _L))
	out.append(PlateShapes.rect(20, 48, 26, 5, _D))
	out.append(PlateShapes.rect(20, 59, 30, 5, _D))
	return out


static func _popcorn() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for puff: Array in [[34, 38, 11], [50, 30, 13], [66, 38, 11], [42, 26, 10], [58, 24, 10]]:
		out.append(PlateShapes.circle(Vector2(puff[0], puff[1]), puff[2], _L))
	out.append(PlateShapes.poly([26, 48, 74, 48, 67, 94, 33, 94], _B))
	for i in 3:
		var x := 34.0 + i * 14.0
		out.append(
			PlateShapes.poly([x, 48, x + 7, 48, x + 5.5 - 1.5 * i, 94, x - 2.5 + 0.5 * i, 94], _L)
		)
	return out


static func _reel() -> Array[Dictionary]:
	var out: Array[Dictionary] = [PlateShapes.circle(Vector2(50, 50), 42.0, _B)]
	for i in 5:
		var angle := TAU * float(i) / 5.0 - PI * 0.5
		var at := Vector2(50, 50) + Vector2(cos(angle), sin(angle)) * 23.0
		out.append(PlateShapes.circle(at, 9.0, _G))
	out.append(PlateShapes.circle(Vector2(50, 50), 9.0, _L))
	out.append(PlateShapes.circle(Vector2(50, 50), 3.5, _D))
	return out


static func _cup() -> Array[Dictionary]:
	return [
		PlateShapes.bar(Vector2(56, 22), Vector2(64, 4), 5.0, _D),
		PlateShapes.poly([30, 30, 70, 30, 64, 92, 36, 92], _B),
		PlateShapes.poly([32, 50, 68, 50, 66, 68, 34, 68], _L),
		PlateShapes.rect(25, 22, 50, 10, _L),
	]


static func _strip() -> Array[Dictionary]:
	var out: Array[Dictionary] = [PlateShapes.rect(6, 26, 88, 48, _D)]
	for i in 8:
		out.append(PlateShapes.rect(10.0 + i * 11, 29, 6, 5, _G))
		out.append(PlateShapes.rect(10.0 + i * 11, 66, 6, 5, _G))
	out.append(PlateShapes.rect(13, 38, 22, 24, _B))
	out.append(PlateShapes.rect(39, 38, 22, 24, _L))
	out.append(PlateShapes.rect(65, 38, 22, 24, _B))
	return out


static func _car() -> Array[Dictionary]:
	return [
		PlateShapes.poly([4, 70, 8, 54, 30, 50, 40, 34, 66, 34, 78, 50, 94, 56, 96, 70], _B),
		PlateShapes.poly([43, 39, 63, 39, 71, 50, 37, 50], _L),
		PlateShapes.circle(Vector2(27, 72), 11.0, _D),
		PlateShapes.circle(Vector2(27, 72), 4.5, _L),
		PlateShapes.circle(Vector2(75, 72), 11.0, _D),
		PlateShapes.circle(Vector2(75, 72), 4.5, _L),
	]


static func _marquee() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		PlateShapes.rect(46, 60, 8, 30, _D),
		PlateShapes.rect(32, 88, 36, 6, _D),
		PlateShapes.rect(8, 18, 84, 44, _B),
		PlateShapes.rect(15, 26, 70, 28, _D),
		PlateShapes.rect(22, 32, 56, 6, _L),
		PlateShapes.rect(30, 44, 40, 5, _B),
	]
	for i in 10:
		out.append(PlateShapes.circle(Vector2(12.0 + i * 8.5, 22), 2.6, _L))
		out.append(PlateShapes.circle(Vector2(12.0 + i * 8.5, 58), 2.6, _L))
	return out


static func _moon() -> Array[Dictionary]:
	return [
		PlateShapes.circle(Vector2(46, 52), 38.0, _L),
		PlateShapes.circle(Vector2(60, 44), 33.0, _G),
		_star(Vector2(78, 24), 9.0)[0],
		_star(Vector2(70, 74), 6.0)[0],
		_star(Vector2(22, 20), 5.0)[0],
	]


static func _saucer() -> Array[Dictionary]:
	return [
		PlateShapes.ellipse(Vector2(50, 40), Vector2(17, 16), _L),
		PlateShapes.ellipse(Vector2(50, 56), Vector2(42, 13), _B),
		PlateShapes.ellipse(Vector2(50, 54), Vector2(42, 5), _L),
		PlateShapes.circle(Vector2(28, 58), 2.6, _D),
		PlateShapes.circle(Vector2(50, 61), 2.6, _D),
		PlateShapes.circle(Vector2(72, 58), 2.6, _D),
		PlateShapes.poly([36, 70, 64, 70, 74, 94, 26, 94], _L),
	]


## A star of five points, `outer` from `centre` to a point, and a lighter core in front of it.
static func _star(centre: Vector2, outer: float) -> Array[Dictionary]:
	var points := PackedVector2Array()
	for i in 10:
		var angle := TAU * float(i) / 10.0 - PI * 0.5
		var radius := outer if i % 2 == 0 else outer * STAR_INNER
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	var core := PackedVector2Array()
	for point in points:
		core.append(centre + (point - centre) * 0.5)
	return [PlateShapes.shape(points, _B), PlateShapes.shape(core, _L)]


static func _skull() -> Array[Dictionary]:
	return [
		PlateShapes.circle(Vector2(50, 44), 32.0, _L),
		PlateShapes.rect(35, 60, 30, 26, _L),
		PlateShapes.circle(Vector2(37, 44), 9.0, _D),
		PlateShapes.circle(Vector2(63, 44), 9.0, _D),
		PlateShapes.poly([50, 52, 44, 63, 56, 63], _D),
		PlateShapes.rect(41, 74, 3, 12, _D),
		PlateShapes.rect(48.5, 74, 3, 12, _D),
		PlateShapes.rect(56, 74, 3, 12, _D),
	]


static func _crosshair() -> Array[Dictionary]:
	return [
		PlateShapes.circle(Vector2(50, 50), 41.0, _B),
		PlateShapes.circle(Vector2(50, 50), 33.0, _G),
		PlateShapes.rect(48, 4, 4, 92, _B),
		PlateShapes.rect(4, 48, 92, 4, _B),
		PlateShapes.circle(Vector2(50, 50), 6.0, _L),
	]


static func _planks() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		PlateShapes.bar(Vector2(8, 28), Vector2(92, 20), 17.0, _B),
		PlateShapes.bar(Vector2(8, 52), Vector2(92, 48), 17.0, _L),
		PlateShapes.bar(Vector2(8, 76), Vector2(92, 78), 17.0, _B),
	]
	for at: Vector2 in [
		Vector2(14, 27),
		Vector2(86, 21),
		Vector2(14, 52),
		Vector2(86, 48),
		Vector2(14, 76),
		Vector2(86, 78)
	]:
		out.append(PlateShapes.circle(at, 2.6, _D))
	return out


static func _bolt() -> Array[Dictionary]:
	return [
		PlateShapes.poly([62, 2, 16, 58, 43, 58, 31, 99, 85, 36, 57, 36, 74, 2], _D),
		PlateShapes.poly([60, 6, 22, 56, 47, 56, 36, 92, 79, 39, 53, 39, 68, 6], _B),
		PlateShapes.poly([58, 14, 36, 48, 52, 48], _L),
	]


static func _can() -> Array[Dictionary]:
	return [
		PlateShapes.bar(Vector2(52, 25), Vector2(78, 16), 7.0, _D),
		PlateShapes.rect(20, 42, 8, 32, _D),
		PlateShapes.rect(36, 22, 18, 14, _B),
		PlateShapes.rect(26, 34, 48, 58, _B),
		PlateShapes.rect(33, 50, 34, 26, _L),
		PlateShapes.bar(Vector2(40, 54), Vector2(60, 72), 4.0, _D),
		PlateShapes.bar(Vector2(60, 54), Vector2(40, 72), 4.0, _D),
	]


static func _grenade() -> Array[Dictionary]:
	return [
		PlateShapes.ellipse(Vector2(50, 60), Vector2(27, 31), _B),
		PlateShapes.rect(41, 20, 18, 12, _D),
		PlateShapes.poly([58, 22, 80, 26, 82, 36, 58, 32], _L),
		PlateShapes.circle(Vector2(30, 22), 8.5, _L),
		PlateShapes.circle(Vector2(30, 22), 5.0, _G),
		PlateShapes.rect(26, 56, 48, 3, _D),
		PlateShapes.rect(48.5, 34, 3, 52, _D),
		PlateShapes.rect(30, 72, 40, 3, _D),
	]


static func _fist() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		PlateShapes.rect(30, 78, 40, 15, _D), PlateShapes.rect(26, 40, 48, 42, _B)
	]
	for i in 4:
		out.append(PlateShapes.circle(Vector2(33.0 + i * 11.3, 40), 7.4, _L))
	out.append(PlateShapes.ellipse(Vector2(25, 64), Vector2(8, 13), _L))
	return out


static func _crown() -> Array[Dictionary]:
	return [
		PlateShapes.poly([12, 74, 12, 32, 32, 52, 50, 24, 68, 52, 88, 32, 88, 74], _B),
		PlateShapes.rect(12, 72, 76, 12, _L),
		PlateShapes.circle(Vector2(12, 30), 5.0, _L),
		PlateShapes.circle(Vector2(50, 22), 5.5, _L),
		PlateShapes.circle(Vector2(88, 30), 5.0, _L),
		PlateShapes.circle(Vector2(50, 62), 4.0, _D),
	]


static func _coins() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in 4:
		var y := 78.0 - i * 15.0
		out.append(PlateShapes.ellipse(Vector2(50, y + 6), Vector2(31, 11), _D))
		out.append(PlateShapes.ellipse(Vector2(50, y), Vector2(31, 11), _B))
		out.append(PlateShapes.ellipse(Vector2(50, y), Vector2(19, 6), _L))
	return out


static func _hammer() -> Array[Dictionary]:
	return [
		PlateShapes.bar(Vector2(26, 90), Vector2(60, 40), 11.0, _L),
		PlateShapes.bar(Vector2(44, 26), Vector2(88, 46), 22.0, _B),
		PlateShapes.rect(10, 74, 5, 20, _D),
		PlateShapes.rect(6, 70, 13, 5, _D),
	]


static func _door() -> Array[Dictionary]:
	return [
		PlateShapes.rect(14, 90, 72, 5, _D),
		PlateShapes.rect(24, 8, 52, 84, _B),
		PlateShapes.rect(30, 14, 40, 34, _L),
		PlateShapes.rect(30, 54, 40, 32, _L),
		PlateShapes.circle(Vector2(63, 62), 3.6, _D),
	]


static func _target() -> Array[Dictionary]:
	return [
		PlateShapes.circle(Vector2(50, 50), 42.0, _B),
		PlateShapes.circle(Vector2(50, 50), 33.0, _G),
		PlateShapes.circle(Vector2(50, 50), 25.0, _B),
		PlateShapes.circle(Vector2(50, 50), 16.0, _G),
		PlateShapes.circle(Vector2(50, 50), 8.0, _L),
	]


static func _rack() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		PlateShapes.rect(12, 16, 6, 78, _D), PlateShapes.rect(82, 16, 6, 78, _D)
	]
	for i in 3:
		var y := 32.0 + i * 25.0
		out.append(PlateShapes.rect(12, y + 8, 76, 5, _B))
		out.append(PlateShapes.rect(22, y, 52, 6, _L))
		out.append(PlateShapes.rect(60, y, 6, 12, _L))
	return out
