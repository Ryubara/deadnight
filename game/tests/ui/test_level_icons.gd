# The 55 level icons (#1060): every level has a cell that is not blank in both atlases, the frames
# go by tier and the bulbs by the level inside it, no two drawings are alike, and the atlases are
# the ones the SVGs make. The tests read the imported atlases, as the game does.
extends GdUnitTestSuite

## Size the drawings are compared at, and the least mean difference of two of them, of 255 a
## channel: below it, two levels are the same drawing or a redraw that changed next to nothing.
const COMPARE_SIZE := 32
const LEAST_DIFFERENCE := 6.0
## The smallest share of a cell a drawing, its frame and its bulbs cover.
const LEAST_COVER := 0.4
## Where the five bulbs sit in a 128 px cell.
const BULB_Y := 120
const BULB_LEFT := 34
const BULB_STEP := 15


func after() -> void:
	LevelIcons.release()


func test_the_atlases_stay_loaded_when_the_caller_lets_go() -> void:
	# `_draw` keeps no reference: a texture freed after it returns draws as a white square.
	LevelIcons.release()
	var id := LevelIcons.atlas(LevelIcons.CELL_LARGE).get_instance_id()
	await get_tree().process_frame
	assert_bool(is_instance_id_valid(id)).is_true()


func test_every_level_has_its_own_region_inside_both_atlases() -> void:
	for cell: int in [LevelIcons.CELL_SMALL, LevelIcons.CELL_LARGE]:
		var atlas := LevelIcons.atlas(cell)
		assert_vector(atlas.get_size()).is_equal(
			Vector2(LevelIcons.COLUMNS * cell, LevelIcons.TIERS * cell)
		)
		var whole := Rect2(Vector2.ZERO, atlas.get_size())
		var seen := {}
		for level in range(1, LevelIcons.LEVELS + 1):
			var region := LevelIcons.region(level, cell)
			assert_vector(region.size).is_equal(Vector2(cell, cell))
			assert_bool(whole.encloses(region)).is_true()
			seen[region] = level
		assert_int(seen.size()).is_equal(LevelIcons.LEVELS)


func test_a_tier_is_five_levels_and_there_are_eleven() -> void:
	assert_int(LevelIcons.tier(1)).is_equal(1)
	assert_int(LevelIcons.tier(5)).is_equal(1)
	assert_int(LevelIcons.tier(6)).is_equal(2)
	assert_int(LevelIcons.tier(50)).is_equal(10)
	assert_int(LevelIcons.tier(51)).is_equal(11)
	assert_int(LevelIcons.tier(55)).is_equal(LevelIcons.TIERS)


func test_a_level_off_the_ladder_reads_as_its_end() -> void:
	assert_int(LevelIcons.tier(0)).is_equal(1)
	assert_int(LevelIcons.tier(90)).is_equal(LevelIcons.TIERS)
	assert_bool(LevelIcons.region(0) == LevelIcons.region(1)).is_true()
	assert_bool(LevelIcons.region(90) == LevelIcons.region(LevelIcons.LEVELS)).is_true()


func test_the_textures_are_shared_and_draw_from_one_atlas() -> void:
	var first := LevelIcons.texture(3)
	assert_object(LevelIcons.texture(3)).is_same(first)
	assert_object(LevelIcons.texture(50).atlas).is_same(first.atlas)
	assert_object(first.atlas).is_same(LevelIcons.atlas())
	assert_bool(LevelIcons.texture(50).region == LevelIcons.region(50)).is_true()
	assert_object(LevelIcons.texture(50, LevelIcons.CELL_LARGE).atlas).is_same(
		LevelIcons.atlas(LevelIcons.CELL_LARGE)
	)


func test_no_atlas_cell_is_blank() -> void:
	for cell: int in [LevelIcons.CELL_SMALL, LevelIcons.CELL_LARGE]:
		var image := _atlas_image(cell)
		for level in range(1, LevelIcons.LEVELS + 1):
			var one := image.get_region(Rect2i(LevelIcons.region(level, cell)))
			(
				assert_float(_cover(one))
				. override_failure_message("level %d at %d px" % [level, cell])
				. is_greater(LEAST_COVER)
			)


func test_the_bulbs_count_the_level_inside_its_tier() -> void:
	var image := _atlas_image(LevelIcons.CELL_LARGE)
	for level in range(1, LevelIcons.LEVELS + 1):
		var corner := Vector2i(LevelIcons.region(level, LevelIcons.CELL_LARGE).position)
		var lit := 0
		for bulb in 5:
			var at := corner + Vector2i(BULB_LEFT + bulb * BULB_STEP, BULB_Y)
			if image.get_pixelv(at).v > 0.7:
				lit += 1
		assert_int(lit).override_failure_message("level %d" % level).is_equal((level - 1) % 5 + 1)


func test_a_frame_goes_with_its_tier_and_every_tier_has_its_own() -> void:
	var frames := {}
	for level in range(1, LevelIcons.LEVELS + 1):
		var frame := _part(_svg(level), "frame")
		assert_str(frame).is_not_empty()
		var tier := LevelIcons.tier(level)
		if frames.has(tier):
			assert_str(frame).is_equal(frames[tier])
		frames[tier] = frame
	assert_int(frames.size()).is_equal(LevelIcons.TIERS)
	var drawn := {}
	for tier: int in frames:
		drawn[frames[tier]] = tier
	assert_int(drawn.size()).is_equal(LevelIcons.TIERS)


func test_no_two_drawings_are_the_same() -> void:
	var drawings: Array[PackedByteArray] = []
	var seen := {}
	var scale := float(COMPARE_SIZE) / LevelIcons.SVG_SIZE
	for level in range(1, LevelIcons.LEVELS + 1):
		var glyph := _part(_svg(level), "glyph")
		seen[glyph] = level
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128">%s</svg>'
		var shape := Image.new()
		assert_int(shape.load_svg_from_string(svg % glyph, scale)).is_equal(OK)
		shape.convert(Image.FORMAT_RGBA8)
		drawings.append(shape.get_data())
	assert_int(seen.size()).is_equal(LevelIcons.LEVELS)
	var closest := INF
	var pair := Vector2i.ZERO
	for a in drawings.size():
		for b in range(a + 1, drawings.size()):
			var difference := _difference(drawings[a], drawings[b])
			if difference < closest:
				closest = difference
				pair = Vector2i(a + 1, b + 1)
	(
		assert_float(closest)
		. override_failure_message("levels %d and %d differ by %.1f" % [pair.x, pair.y, closest])
		. is_greater(LEAST_DIFFERENCE)
	)


func test_the_sources_are_shapes_a_rasteriser_can_draw() -> void:
	for level in range(1, LevelIcons.LEVELS + 1):
		var svg := _svg(level)
		assert_str(svg).contains('width="128" height="128"')
		assert_bool(svg.contains("<text")).is_false()
		assert_bool(svg.contains("<image")).is_false()


func test_the_atlases_are_the_ones_the_sources_make() -> void:
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(LevelIcons.MANIFEST_PATH)
	)
	var levels: Array = manifest["levels"]
	assert_int(levels.size()).is_equal(LevelIcons.LEVELS)
	for entry: Dictionary in levels:
		var level := int(entry["level"])
		assert_str(entry["sha256"]).is_equal(FileAccess.get_sha256(LevelIcons.svg_path(level)))
		assert_int(int(entry["tier"])).is_equal(LevelIcons.tier(level))
		assert_str(entry["name"]).is_not_empty()
		assert_vector(Vector2(entry["cell"][0], entry["cell"][1])).is_equal(
			LevelIcons.region(level, 1).position
		)
	for cell: String in manifest["atlases"]:
		var atlas: Dictionary = manifest["atlases"][cell]
		assert_str(atlas["sha256"]).is_equal(
			FileAccess.get_sha256(LevelIcons.atlas_path(int(cell)))
		)


func _atlas_image(cell: int) -> Image:
	var image := LevelIcons.atlas(cell).get_image()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _svg(level: int) -> String:
	return FileAccess.get_file_as_string(LevelIcons.svg_path(level))


## The markup of one of the file's `<g id="...">` lines: one line each.
func _part(svg: String, id: String) -> String:
	for text_line in svg.split("\n"):
		if text_line.begins_with('<g id="%s"' % id):
			return text_line
	return ""


func _cover(image: Image) -> float:
	var opaque := 0
	var data := image.get_data()
	for i in range(3, data.size(), 4):
		if data[i] > 128:
			opaque += 1
	return float(opaque) / (image.get_width() * image.get_height())


func _difference(a: PackedByteArray, b: PackedByteArray) -> float:
	var total := 0
	for i in a.size():
		total += absi(a[i] - b[i])
	return float(total) / a.size()
