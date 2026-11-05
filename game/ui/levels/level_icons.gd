class_name LevelIcons
extends RefCounted
## The level icons: one atlas of each size, a cell per level, a row per tier. Every icon drawn from
## one atlas stays in one batch (the name tags, up to eight at once on the web build).
##
##     var place := Rect2(at, Vector2(24, 24))
##     draw_texture_rect_region(LevelIcons.atlas(), place, LevelIcons.region(level))
##
## A canvas item that shows an icon under its cell size sets `texture_filter = LevelIcons.FILTER`:
## the atlases carry mipmaps for that, and a tag that moves shimmers less with them. Draw all the
## icons of a frame before any words: eight tags are three draw calls so, 24 tag by tag. A level
## past the last one reads as the last. Docs: docs/research/progression.md, "The icon pipeline".

## The levels and the tiers (five levels each) the ladder has.
const LEVELS := 55
const TIERS := 11
const COLUMNS := 5

## Tags and popups, and the plate.
const CELL_SMALL := 64
const CELL_LARGE := 128

const FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## The sources are not imported (the folder has a `.gdignore`): nothing the game ships reads them.
const SVG_FOLDER := "res://assets/ui/levels/"
const SVG_SIZE := 128.0
## Where the strip of progress bulbs starts, as a share of the cell's height: the bulbs are drawn at
## y 120, radius 5.2, stroke 2 in the 128 px source (`tools/level_icons/draw_icons.py`), so their
## top edge is at 120 - 5.2 - 1 = 113.8. The icon's body is everything above it.
const BULBS_TOP := 113.8 / 128.0
const ATLAS_FOLDER := "res://assets/ui/level_atlas/"
const MANIFEST_PATH := ATLAS_FOLDER + "level_icons.json"

## Held for as long as the game shows icons: a texture nothing holds is freed when the function
## that loaded it returns, and the commands drawn with it come out white.
static var _atlases := {}
static var _textures := {}
## level -> where the middle of its body is, as a share of the cell's height (`body_centre`).
static var _bodies := {}


## The tier a level belongs to, 1 to `TIERS`.
static func tier(level: int) -> int:
	return (_clamped(level) - 1) / COLUMNS + 1


## The whole atlas: draw from it with `region`, so that all the icons share a batch.
static func atlas(cell: int = CELL_SMALL) -> Texture2D:
	if not _atlases.has(cell):
		_atlases[cell] = load(atlas_path(cell))
	return _atlases[cell]


## A level's cell in the atlas of that cell size.
static func region(level: int, cell: int = CELL_SMALL) -> Rect2:
	return Rect2(column(level) * cell, row(level) * cell, cell, cell)


## A texture of one level for a `TextureRect`: it is shared, and draws from the atlas.
static func texture(level: int, cell: int = CELL_SMALL) -> AtlasTexture:
	var key := _clamped(level) * 1000 + cell
	if not _textures.has(key):
		var cut := AtlasTexture.new()
		cut.atlas = atlas(cell)
		cut.region = region(level, cell)
		_textures[key] = cut
	return _textures[key]


## Where the middle of a level's icon is, as a share of its cell's height: the middle of its body,
## the ink above the strip of bulbs (`BULBS_TOP`). The art is not centred in its cell (the bulbs
## take the bottom, and the three frames fill the rest by different amounts), so a place that
## sets an icon by its cell's middle sets it off the digits beside it (`LevelTag.icon_top`). The
## rows are in the manifest, which the export writes from the atlas (`body_rows`) and a test
## checks against it; it is read once. A manifest without them (no file) gives a centred icon.
static func body_centre(level: int) -> float:
	var key := _clamped(level)
	if _bodies.is_empty():
		_read_bodies()
	return _bodies.get(key, 0.5)


## The first row and the end of the body of the icon whose cell starts at `origin` in `image` (the
## 64 px atlas): the rows that start above the bulbs' edge and hold ink (alpha of a half or more),
## the last of them cut at the edge itself (a token and a sign rest right on the bulbs).
static func body_rows(image: Image, origin: Vector2i) -> Vector2:
	var first := -1
	var last := -1
	for y in ceili(BULBS_TOP * CELL_SMALL):
		for x in CELL_SMALL:
			if image.get_pixel(origin.x + x, origin.y + y).a >= 0.5:
				if first < 0:
					first = y
				last = y
				break
	if first < 0:
		return Vector2.ZERO
	return Vector2(first, minf(float(last + 1), BULBS_TOP * CELL_SMALL))


static func _read_bodies() -> void:
	_bodies[0] = 0.5
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not manifest is Dictionary:
		return
	for entry: Dictionary in manifest.get("levels", []):
		var rows: Array = entry.get("body", [])
		if rows.size() == 2:
			_bodies[int(entry["level"])] = (float(rows[0]) + float(rows[1])) * 0.5 / CELL_SMALL


## Lets go of the atlases, for the end of a test run.
static func release() -> void:
	_atlases.clear()
	_textures.clear()
	_bodies.clear()


static func column(level: int) -> int:
	return (_clamped(level) - 1) % COLUMNS


static func row(level: int) -> int:
	return tier(level) - 1


static func atlas_path(cell: int) -> String:
	return ATLAS_FOLDER + "level_icons_%d.png" % cell


static func svg_path(level: int) -> String:
	return SVG_FOLDER + "level_%02d.svg" % _clamped(level)


static func _clamped(level: int) -> int:
	return clampi(level, 1, LEVELS)
