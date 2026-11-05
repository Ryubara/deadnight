class_name PosterCompose
extends RefCounted
## Composes a poster from the same shared parts as the cards (`PlateShapes`, `PlateMotifs`,
## `PlatePalettes`): a ground, a sunburst, one large picture (the set's motif), a hill, a band for
## the title and a frame of light, in role colours in the poster's own design space, which
## `PosterArt` scales to wherever it sits. Two posters are two palettes and two motifs, not two
## paintings.

## The poster's design size: two panels across and three down, 150 units each.
const SIZE := Vector2(300.0, 450.0)
const PANEL := Vector2(150.0, 150.0)
## Where the sunburst's rays start, and how many there are (every other one is drawn).
const BURST_AT := Vector2(150.0, 205.0)
const BURST_RAYS := 16
const BURST_REACH := 420.0
## The big picture's side and its top left corner.
const MOTIF_SIDE := 230.0
const MOTIF_AT := Vector2(35.0, 82.0)
## The disc of light behind the picture.
const HALO_AT := Vector2(150.0, 197.0)
const HALO_RADIUS := 112.0
## The hill the picture stands on, and the band under it that carries the title.
const HILL_TOP := 318.0
const BAND_TOP := 350.0
## The frame's thickness.
const FRAME := 6.0
## The stars: how many, over the sky above the picture and at its sides.
const STARS := 22


## The shapes of the poster, back to front.
static func shapes(poster_set: PosterSet) -> Array[Dictionary]:
	var out: Array[Dictionary] = [PlateShapes.rect(0, 0, SIZE.x, SIZE.y, PlateShapes.Role.GROUND)]
	var step := TAU / float(BURST_RAYS)
	for i in range(0, BURST_RAYS, 2):
		var a := step * i
		(
			out
			. append(
				(
					PlateShapes
					. shape(
						PackedVector2Array(
							[
								BURST_AT,
								BURST_AT + Vector2(cos(a), sin(a)) * BURST_REACH,
								BURST_AT + Vector2(cos(a + step), sin(a + step)) * BURST_REACH,
							]
						),
						PlateShapes.Role.DARK
					)
				)
			)
		)
	for i in STARS:
		var at := _star_at(i)
		out.append(PlateShapes.circle(at, 1.2 + float(i % 3) * 0.6, PlateShapes.Role.LIGHT))
	out.append(
		PlateShapes.poly(
			[
				0,
				HILL_TOP + 14,
				90,
				HILL_TOP - 4,
				210,
				HILL_TOP + 8,
				300,
				HILL_TOP - 10,
				300,
				SIZE.y,
				0,
				SIZE.y
			],
			PlateShapes.Role.BASE
		)
	)
	# A disc of light behind the picture, like the sun over a drive-in screen.
	out.append(PlateShapes.circle(HALO_AT, HALO_RADIUS, PlateShapes.Role.BASE))
	out.append(PlateShapes.circle(HALO_AT, HALO_RADIUS - 9.0, PlateShapes.Role.GROUND))
	var motif := PlateMotifs.shapes(poster_set.motif)
	out.append_array(PlateShapes.placed(motif, MOTIF_AT, MOTIF_SIDE / 100.0))
	out.append(PlateShapes.rect(0, BAND_TOP, SIZE.x, SIZE.y - BAND_TOP, PlateShapes.Role.DARK))
	out.append(PlateShapes.rect(0, BAND_TOP - 4.0, SIZE.x, 4.0, PlateShapes.Role.LIGHT))
	out.append(PlateShapes.rect(0, 0, SIZE.x, FRAME, PlateShapes.Role.LIGHT))
	out.append(PlateShapes.rect(0, SIZE.y - FRAME, SIZE.x, FRAME, PlateShapes.Role.LIGHT))
	out.append(PlateShapes.rect(0, 0, FRAME, SIZE.y, PlateShapes.Role.LIGHT))
	out.append(PlateShapes.rect(SIZE.x - FRAME, 0, FRAME, SIZE.y, PlateShapes.Role.LIGHT))
	return out


## The rectangle of panel `index` (0 to 5, left to right, top to bottom) in the design space.
static func panel_rect(index: int) -> Rect2:
	var column := index % PosterSet.COLUMNS
	var row := index / PosterSet.COLUMNS
	return Rect2(Vector2(column, row) * PANEL, PANEL)


## The lines of the title and where each is printed: `{text, size, baseline, role}` in the design
## space. The tagline over the picture comes first (the text face), then the poster's lines from the
## top of the band (the display face).
static func print_lines(poster_set: PosterSet) -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{
			"text": "THE DRIVE-IN PRESENTS",
			"size": 15,
			"baseline": 36.0,
			"role": PlateShapes.Role.LIGHT,
			"display": false
		}
	]
	var sizes := [18, 38, 26]
	var baselines := [374.0, 412.0, 440.0]
	var roles := [PlateShapes.Role.LIGHT, PlateShapes.Role.BASE, PlateShapes.Role.LIGHT]
	for i in mini(poster_set.lines.size(), sizes.size()):
		(
			out
			. append(
				{
					"text": poster_set.lines[i],
					"size": sizes[i],
					"baseline": baselines[i],
					"role": roles[i],
					"display": true,
				}
			)
		)
	return out


## A star's place, the same for every poster: spread over the sky and the picture's sides.
static func _star_at(index: int) -> Vector2:
	var x := fposmod(float(index) * 97.0 + 23.0, SIZE.x - 20.0) + 10.0
	var y := fposmod(float(index) * 53.0 + 17.0, HILL_TOP - 60.0) + 14.0
	return Vector2(x, y)
