# No slot in the lot that a body can wedge in (Deadnight #615): between the Concession's east wall
# and the soda fountain's hidden block there was a 0.4 m channel, and a bot that dodged sideways
# sat in it for most of a soak. `LotGaps` reads the greybox's colliders as shapes on the ground and
# finds every pair of faces that face each other for half a metre or more at less than a body's
# width; the lot has none, and the scan is shown to find one when there is one.
extends GdUnitTestSuite

var _lots: Array[Node3D] = []


func after_test() -> void:
	for lot in _lots:
		lot.free()
	_lots.clear()


func _body_width() -> float:
	return PlayerTuning.new().radius * 2.0


func _box(parent: Node3D, node_name: String, centre: Vector3, size: Vector3) -> void:
	var box := CSGBox3D.new()
	box.name = node_name
	box.use_collision = true
	box.size = size
	parent.add_child(box)
	box.position = centre


func _lot_with_two_walls(apart: float) -> Node3D:
	var lot := Node3D.new()
	_lots.append(lot)
	add_child(lot)
	_box(lot, "West", Vector3(0.0, 1.0, 0.0), Vector3(0.4, 2.0, 6.0))
	_box(lot, "East", Vector3(0.4 + apart, 1.0, 0.0), Vector3(0.4, 2.0, 6.0))
	return lot


func test_the_lot_has_no_channel_narrower_than_a_body_between_its_colliders() -> void:
	var lot := load(LotFixture.SCENE).instantiate() as Node3D
	add_child(lot)
	_lots.append(lot)
	var found := LotGaps.channels(lot, _body_width())
	var lines: Array[String] = []
	for channel in found:
		lines.append(
			(
				"%.2f m wide, %.1f m long, at (%.1f, %.1f): %s and %s"
				% [
					channel["width"],
					channel["run"],
					channel["at"].x,
					channel["at"].y,
					channel["a"],
					channel["b"]
				]
			)
		)
	(
		assert_array(lines)
		. override_failure_message("a slot a body can wedge in:\n" + "\n".join(lines))
		. is_empty()
	)


func test_the_scan_finds_two_walls_closer_than_a_body_and_not_two_farther() -> void:
	var tight := LotGaps.channels(_lot_with_two_walls(0.4), _body_width())
	assert_int(tight.size()).is_equal(1)
	assert_float(tight[0]["width"]).is_equal_approx(0.4, 0.001)
	assert_float(tight[0]["run"]).is_equal_approx(6.0, 0.001)
	assert_array(LotGaps.channels(_lot_with_two_walls(1.0), _body_width())).is_empty()


func test_the_scan_ignores_a_seam_a_wall_in_the_way_and_a_roof() -> void:
	assert_array(LotGaps.channels(_lot_with_two_walls(0.1), _body_width())).is_empty()
	var walled := _lot_with_two_walls(1.0)
	_box(walled, "Middle", Vector3(0.7, 1.0, 0.0), Vector3(0.4, 2.0, 6.0))
	# Two 0.3 m channels either side of the middle wall: both found, none through it.
	assert_int(LotGaps.channels(walled, _body_width()).size()).is_equal(2)
	var roofed := Node3D.new()
	_lots.append(roofed)
	add_child(roofed)
	_box(roofed, "West", Vector3(0.0, 1.0, 0.0), Vector3(0.4, 2.0, 6.0))
	_box(roofed, "Roof", Vector3(0.7, 3.9, 0.0), Vector3(0.4, 0.3, 6.0))
	assert_array(LotGaps.channels(roofed, _body_width())).is_empty()
