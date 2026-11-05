extends SceneTree
## Rasterises the level icons' SVGs into the two atlases `LevelIcons` reads and a manifest.
##
##     godot --headless --path game -s res://tools/art/export_level_icons.gd
##
## `tools/level_icons/draw_icons.py` writes the SVGs; this writes `level_icons_64.png`,
## `level_icons_128.png` and `level_icons.json`. The manifest holds a hash of each SVG and of each
## atlas, so `tools/check_level_icons.py` (CI) fails when an SVG changed and the atlases did not,
## with no Godot and no raster to compare across machines. It also writes each icon's body rows
## (`LevelIcons.body_rows`), which the tags use to centre an icon on its digits (#1161). Docs:
## docs/research/progression.md, "The icon pipeline".

const SIZES: Array[int] = [LevelIcons.CELL_SMALL, LevelIcons.CELL_LARGE]


func _init() -> void:
	var failed := _export()
	quit(1 if failed else 0)


func _export() -> bool:
	var sources: Array[Dictionary] = []
	for level in range(1, LevelIcons.LEVELS + 1):
		var svg_path := LevelIcons.svg_path(level)
		var svg := FileAccess.get_file_as_string(svg_path)
		if svg.is_empty():
			push_error("no icon at %s" % svg_path)
			return true
		(
			sources
			. append(
				{
					"level": level,
					"svg": svg_path.get_file(),
					"sha256": FileAccess.get_sha256(svg_path),
					"name": _between(svg, "<title>", "</title>"),
					"tier_name": _between(svg, "<desc>", "</desc>"),
					"text": svg,
				}
			)
		)
	var atlases := {}
	for cell in SIZES:
		var atlas_path := LevelIcons.atlas_path(cell)
		if _write_atlas(sources, cell, atlas_path):
			return true
		atlases[str(cell)] = {
			"file": atlas_path.get_file(),
			"sha256": FileAccess.get_sha256(atlas_path),
		}
	var levels: Array[Dictionary] = []
	var small := Image.load_from_file(
		ProjectSettings.globalize_path(LevelIcons.atlas_path(LevelIcons.CELL_SMALL))
	)
	for source in sources:
		var level: int = source["level"]
		var origin := (
			Vector2i(LevelIcons.column(level), LevelIcons.row(level)) * LevelIcons.CELL_SMALL
		)
		var body := LevelIcons.body_rows(small, origin)
		(
			levels
			. append(
				{
					"level": level,
					"name": source["name"],
					"tier": LevelIcons.tier(level),
					"tier_name": source["tier_name"],
					"svg": source["svg"],
					"sha256": source["sha256"],
					"cell": [LevelIcons.column(level), LevelIcons.row(level)],
					# The body's rows in the 64 px cell, for `LevelIcons.body_centre`.
					"body": [body.x, body.y],
				}
			)
		)
	var manifest := {
		"cells_across": LevelIcons.COLUMNS,
		"cells_down": LevelIcons.TIERS,
		"atlases": atlases,
		"levels": levels,
	}
	var file := FileAccess.open(LevelIcons.MANIFEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ", false) + "\n")
	file.close()
	print("level icons: %d cells at %s px" % [levels.size(), str(SIZES)])
	return false


func _write_atlas(sources: Array[Dictionary], cell: int, atlas_path: String) -> bool:
	var atlas := Image.create_empty(
		cell * LevelIcons.COLUMNS, cell * LevelIcons.TIERS, false, Image.FORMAT_RGBA8
	)
	for source in sources:
		var level: int = source["level"]
		var image := Image.new()
		var text: String = source["text"]
		if image.load_svg_from_string(text, float(cell) / LevelIcons.SVG_SIZE) != OK:
			push_error("level %d does not rasterise" % level)
			return true
		image.convert(Image.FORMAT_RGBA8)
		var size := Rect2i(Vector2i.ZERO, image.get_size())
		atlas.blit_rect(
			image, size, Vector2i(LevelIcons.column(level), LevelIcons.row(level)) * cell
		)
	return atlas.save_png(atlas_path) != OK


func _between(text: String, before: String, after: String) -> String:
	var start := text.find(before) + before.length()
	return text.substr(start, text.find(after) - start)
