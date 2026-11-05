extends GdUnitTestSuite
## The poster read back pixel by pixel (#1073): the light frame is one piece at every number of
## panels uncovered, a covered panel is one flat colour but for its number (nothing of the picture
## or the title shows through), and covering a panel changes nothing in its neighbours (no edge
## crosses a word). Needs a real renderer (a headless run skips): `gds godot -- --path game -s
## res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/ui/test_poster_art_pixels.gd -c
## --ignoreHeadlessMode`. Set `POSTER_SHOTS` to a folder to keep the pictures.

const SKIP_WHY := "reads pixels: needs a renderer, not the headless dummy"
## One pixel to a design unit, so a design rectangle is a pixel rectangle.
const SIDE := Vector2i(300, 450)
## How far two channels may differ and still be the same colour (the 8-bit round trip).
const TOLERANCE := 0.012


## The picture of `poster_set` with `uncovered` panels uncovered, at one pixel per design unit.
func _shoot(poster_set: PosterSet, uncovered: Array[int], name: String) -> Image:
	var port := SubViewport.new()
	port.size = SIDE
	port.transparent_bg = false
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(auto_free(port))
	var art := PosterArt.make(poster_set, float(SIDE.x), uncovered, true)
	port.add_child(art)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := port.get_texture().get_image()
	var folder := OS.get_environment("POSTER_SHOTS")
	if folder != "":
		DirAccess.make_dir_recursive_absolute(folder)
		image.save_png("%s/%s_%s.png" % [folder, poster_set.id, name])
	return image


func _same(a: Color, b: Color) -> bool:
	return (
		absf(a.r - b.r) <= TOLERANCE
		and absf(a.g - b.g) <= TOLERANCE
		and absf(a.b - b.b) <= TOLERANCE
	)


func _frame_faults(image: Image, poster_set: PosterSet, label: String) -> Array[String]:
	var light := PlatePalettes.colour(poster_set.palette, PlateShapes.Role.LIGHT)
	var faults: Array[String] = []
	var mid := int(PosterCompose.FRAME * 0.5)
	for along in range(int(PosterCompose.FRAME), SIDE.x - int(PosterCompose.FRAME)):
		for at in [Vector2i(along, mid), Vector2i(along, SIDE.y - 1 - mid)]:
			if not _same(image.get_pixelv(at), light):
				faults.append(
					"%s: top or bottom frame at %s is %s" % [label, at, image.get_pixelv(at)]
				)
	for along in range(int(PosterCompose.FRAME), SIDE.y - int(PosterCompose.FRAME)):
		for at in [Vector2i(mid, along), Vector2i(SIDE.x - 1 - mid, along)]:
			if not _same(image.get_pixelv(at), light):
				faults.append("%s: side frame at %s is %s" % [label, at, image.get_pixelv(at)])
	return faults


func test_the_frame_is_one_piece_at_every_number_of_panels(
	_do_skip := DisplayServer.get_name() == "headless", _skip_reason := SKIP_WHY
) -> void:
	var faults: Array[String] = []
	for poster_set in PosterSets.shipped().all():
		for shown: Array in [[], [0], [0, 3], [0, 1, 2, 3], [1, 2, 3, 4, 5], [0, 1, 2, 3, 4, 5]]:
			var uncovered: Array[int] = []
			uncovered.assign(shown)
			var image := await _shoot(poster_set, uncovered, "frame_%d" % shown.size())
			faults.append_array(_frame_faults(image, poster_set, "%s %s" % [poster_set.id, shown]))
	assert_array(faults.slice(0, 6)).is_empty()
	assert_int(faults.size()).is_equal(0)


func test_a_covered_panel_is_one_flat_colour_but_for_its_number(
	_do_skip := DisplayServer.get_name() == "headless", _skip_reason := SKIP_WHY
) -> void:
	var faults: Array[String] = []
	for poster_set in PosterSets.shipped().all():
		var none: Array[int] = []
		var image := await _shoot(poster_set, none, "covered")
		for index in PosterSet.PANELS:
			var rect := PosterCompose.panel_rect(index)
			var inner := Rect2i(rect.grow(-8.0))
			# The cover's own edge against the frame and the neighbours is not asked: the middle of
			# the panel is, but for the box the number stands in.
			var number := Rect2i(rect.grow_individual(-45.0, -45.0, -45.0, -45.0))
			var base := image.get_pixelv(inner.position)
			var odd := 0
			var digit := 0
			for y in range(inner.position.y, inner.end.y):
				for x in range(inner.position.x, inner.end.x):
					var colour := image.get_pixel(x, y)
					if number.has_point(Vector2i(x, y)):
						if not _same(colour, base):
							digit += 1
					elif not _same(colour, base):
						odd += 1
			if odd > 0:
				faults.append(
					(
						"%s panel %d: %d pixels of the picture or title show"
						% [poster_set.id, index + 1, odd]
					)
				)
			if digit < 40:
				faults.append(
					(
						"%s panel %d: its number is not drawn (%d pixels)"
						% [poster_set.id, index + 1, digit]
					)
				)
	assert_array(faults).is_empty()


func test_covering_a_panel_changes_nothing_in_its_neighbours(
	_do_skip := DisplayServer.get_name() == "headless", _skip_reason := SKIP_WHY
) -> void:
	var faults: Array[String] = []
	for poster_set in PosterSets.shipped().all():
		var every: Array[int] = [0, 1, 2, 3, 4, 5]
		var full := await _shoot(poster_set, every, "full")
		# Panel 2 (the right of the top row) covered: the tagline's two pieces sit in the two columns,
		# so the left one, "THE DRIVE-IN", is whole beside the cover (a cover edge is a hairline wide).
		var right_covered: Array[int] = [0, 2, 3, 4, 5]
		var image := await _shoot(poster_set, right_covered, "right_covered")
		var left := Rect2i(
			Vector2i(int(PosterCompose.FRAME), int(PosterCompose.FRAME)), Vector2i(139, 144)
		)
		var differing := 0
		for y in range(left.position.y, left.end.y):
			for x in range(left.position.x, left.end.x):
				if not _same(image.get_pixel(x, y), full.get_pixel(x, y)):
					differing += 1
		if differing > 0:
			faults.append(
				"%s: covering panel 2 changed %d pixels of panel 1" % [poster_set.id, differing]
			)
	assert_array(faults).is_empty()


func test_no_word_of_the_tagline_stands_across_two_columns() -> void:
	var font := UITokens.active().font_text
	for poster_set in PosterSets.shipped().all():
		for line: Dictionary in PosterCompose.print_lines(poster_set):
			if line["display"]:
				continue
			var px := HudStyle.fit_size(
				font, line["text"], int(line["size"]), float(line["room"]), 6
			)
			var span := font.get_string_size(line["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			var column := int(float(line["centre"]) / PosterCompose.PANEL.x)
			var left: float = float(line["centre"]) - span * 0.5
			var right: float = float(line["centre"]) + span * 0.5
			assert_float(left).is_greater(float(column) * PosterCompose.PANEL.x)
			assert_float(right).is_less(float(column + 1) * PosterCompose.PANEL.x)
