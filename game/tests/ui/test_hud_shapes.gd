# The HUD's flat shapes are collected in one triangle array and drawn as one canvas command (#948):
# a polygon, a polyline or a circle drawn on its own is a draw call of its own in the Compatibility
# renderer, and breaks the batch of the rects around it. These tests check the geometry the
# collection builds (the pictures are compared pixel by pixel in the `hud_cost` capture) and that
# the labels leave the engine two runs of glyphs, not four.
extends GdUnitTestSuite


func test_a_ticket_polygon_is_four_triangles() -> void:
	var shapes := HudShapes.new()
	shapes.polygon(HudStyle.ticket_points(Rect2(0.0, 0.0, 100.0, 60.0)), Color.RED)
	assert_int(shapes._points.size()).is_equal(6)
	assert_int(shapes._indices.size()).is_equal(12)
	assert_int(shapes._colours.size()).is_equal(6)


func test_a_rect_is_two_triangles() -> void:
	var shapes := HudShapes.new()
	shapes.rect(Rect2(2.0, 3.0, 10.0, 4.0), Color.BLUE)
	assert_int(shapes._points.size()).is_equal(4)
	assert_int(shapes._indices.size()).is_equal(6)
	assert_vector(shapes._points[2]).is_equal(Vector2(12.0, 7.0))


func test_a_closed_line_is_a_quad_a_segment_and_its_seam_is_joined() -> void:
	var outline := HudStyle.ticket_points(Rect2(0.0, 0.0, 100.0, 60.0))
	var closed := outline.duplicate()
	closed.append(outline[0])
	var shapes := HudShapes.new()
	shapes.polyline(closed, Color.GREEN, 3.0)
	# Two points a vertex, two triangles (six indices) a segment.
	assert_int(shapes._points.size()).is_equal(2 * closed.size())
	assert_int(shapes._indices.size()).is_equal(6 * (closed.size() - 1))
	# The first and the last vertex are the same place and are offset the same way.
	assert_vector(shapes._points[0]).is_equal_approx(
		shapes._points[shapes._points.size() - 2], Vector2.ONE * 0.001
	)
	assert_vector(shapes._points[1]).is_equal_approx(
		shapes._points[shapes._points.size() - 1], Vector2.ONE * 0.001
	)


func test_a_corner_is_mitred_so_the_edges_keep_half_the_width() -> void:
	# A right angle: the offset at the corner is half the width times the square root of two,
	# along the diagonal, so the stroke's edges stay 1 unit from the line (as the engine's do, and
	# what a thin line at a small scale needs to cover the same pixels).
	var shapes := HudShapes.new()
	shapes.polyline(
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(10.0, 10.0)]),
		Color.WHITE,
		2.0
	)
	var corner_a: Vector2 = shapes._points[2]
	var corner_b: Vector2 = shapes._points[3]
	assert_float(corner_a.distance_to(Vector2(10.0, 0.0))).is_equal_approx(sqrt(2.0), 0.001)
	assert_float(corner_b.distance_to(Vector2(10.0, 0.0))).is_equal_approx(sqrt(2.0), 0.001)


func test_a_straight_line_is_a_quad_of_its_width() -> void:
	var shapes := HudShapes.new()
	shapes.line(Vector2(0.0, 5.0), Vector2(20.0, 5.0), Color.WHITE, 4.0)
	assert_int(shapes._indices.size()).is_equal(6)
	var low := 99.0
	var high := -99.0
	for point in shapes._points:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	assert_float(high - low).is_equal_approx(4.0, 0.001)


func test_a_circle_is_a_fan() -> void:
	var shapes := HudShapes.new()
	shapes.circle(Vector2(10.0, 10.0), 5.0, Color.WHITE)
	assert_int(shapes._points.size()).is_equal(HudShapes.CIRCLE_SEGMENTS + 1)
	assert_int(shapes._indices.size()).is_equal(3 * HudShapes.CIRCLE_SEGMENTS)
	for i in range(1, shapes._points.size()):
		assert_float(shapes._points[i].distance_to(Vector2(10.0, 10.0))).is_equal_approx(5.0, 0.001)


func test_shapes_keep_their_order_in_one_array() -> void:
	var shapes := HudShapes.new()
	shapes.rect(Rect2(0.0, 0.0, 4.0, 4.0), Color.RED)
	shapes.rect(Rect2(1.0, 1.0, 2.0, 2.0), Color.BLUE)
	# The second rect's triangles index its own vertices, after the first's.
	assert_int(shapes._indices[6]).is_equal(4)
	assert_that(shapes._colours[0]).is_equal(Color.RED)
	assert_that(shapes._colours[4]).is_equal(Color.BLUE)


func test_a_hud_label_draws_its_own_outline_and_leaves_the_engine_none() -> void:
	var label := HudStyle.label("ROUND", HudStyle.SMALL, Color.WHITE)
	auto_free(label)
	assert_int(label.halo_size).is_equal(HudStyle.OUTLINE)
	assert_that(label.halo_colour).is_equal(Color(0.0, 0.0, 0.0, 0.7))
	# The engine's own outline stays off, so it draws the shadow and the letters, one texture.
	assert_int(label.get_theme_constant(&"outline_size")).is_equal(0)


func test_a_label_that_wraps_keeps_its_own_outline_too() -> void:
	var label := HudStyle.wrap(HudStyle.label("A LONG LINE OF WORDS", HudStyle.SMALL, Color.WHITE))
	auto_free(label)
	# The outline follows the engine's line breaks, still drawn by the label: the engine's own stays 0.
	assert_int((label as HudLabel).halo_size).is_equal(HudStyle.OUTLINE)
	assert_int(label.get_theme_constant(&"outline_size")).is_equal(0)
	assert_int(label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)


func test_labels_made_and_freed_leave_no_objects_behind() -> void:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(400.0, 400.0)
	add_child(host)
	await get_tree().process_frame
	var before := Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 100:
		var label := HudStyle.label("ROW %d" % i, HudStyle.SMALL, Color.WHITE)
		host.add_child(label)
		label.size = Vector2(120.0, 28.0)
	for _i in 3:
		await get_tree().process_frame
	for child in host.get_children():
		child.free()
	await get_tree().process_frame
	# Each label made a canvas item for its outline and a line of text; both go with it.
	assert_float(Performance.get_monitor(Performance.OBJECT_COUNT)).is_less_equal(before + 2.0)
