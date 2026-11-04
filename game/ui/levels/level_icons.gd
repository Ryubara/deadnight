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
const ATLAS_FOLDER := "res://assets/ui/level_atlas/"
const MANIFEST_PATH := ATLAS_FOLDER + "level_icons.json"

## Held for as long as the game shows icons: a texture nothing holds is freed when the function
## that loaded it returns, and the commands drawn with it come out white.
static var _atlases := {}
static var _textures := {}


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


## Lets go of the atlases, for the end of a test run.
static func release() -> void:
	_atlases.clear()
	_textures.clear()


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
