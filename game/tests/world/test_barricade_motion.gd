# How a breach's boards are drawn going and coming back (docs/design/map.md, Breaches): what is
# solid follows the rules at once, the drawing moves. The motions are Tweens stepped by hand here
# (`custom_step`), never by wall time.
extends GdUnitTestSuite

const BOARD_SCENE := "res://world/drive_in/board.tscn"
const BOARDS := 5
## Long enough for any motion to end (a top board's flight and sink is under a second).
const ALL_OF_IT := 2.0

var _barricade: Barricade


func before_test() -> void:
	# Built as tools/world/build_greybox.py builds a breach: five boards from 0.3 m, 0.6 m apart.
	_barricade = Barricade.new()
	_barricade.set_meta(&"barricade_id", "nw")
	for i in BOARDS:
		var board := (load(BOARD_SCENE) as PackedScene).instantiate() as Node3D
		board.name = "Board%d" % (i + 1)
		board.position = Vector3(0.0, 0.3 + i * 0.6, 0.03 * (-1 if i % 2 else 1))
		_barricade.add_child(board)
	add_child(_barricade)
	auto_free(_barricade)


func _step(seconds: float) -> void:
	for tween in _barricade.motions():
		tween.pause()  # only the steps below move it: the frames between awaits do not
		tween.custom_step(seconds)


func _board(index: int) -> StaticBody3D:
	return _barricade.get_child(index) as StaticBody3D


func test_snapping_moves_nothing() -> void:
	_barricade.set_boards(2, false)
	assert_int(_barricade.boards()).is_equal(2)
	assert_array(_barricade.motions()).is_empty()
	assert_array(_barricade.flying()).is_empty()
	assert_bool(_board(2).visible).is_false()


func test_a_torn_board_stops_nothing_at_once_and_its_copy_flies_out_and_sinks() -> void:
	_barricade.set_boards(4)
	assert_int(_board(4).collision_layer).is_equal(0)
	assert_bool(_board(4).visible).is_false()
	assert_int(_board(3).collision_layer).is_equal(Barricade.BOARD_LAYER)
	var copies := _barricade.flying()
	assert_int(copies.size()).is_equal(1)
	var copy := copies[0]
	var start := copy.position
	assert_vector(start).is_equal_approx(_board(4).position, Vector3.ONE * 0.001)
	var peak := start.y
	for _i in 6:
		_step(0.05)
		peak = maxf(peak, copy.position.y)
	assert_float(peak).is_greater(start.y + 0.2)  # it rises before it falls
	assert_float(copy.position.z).is_less(start.z)  # out of the field (local -Z)
	_step(ALL_OF_IT)
	assert_bool(copy.visible).is_false()
	assert_array(_barricade.flying()).is_empty()
	assert_array(_barricade.motions()).is_empty()


func test_a_torn_board_lands_on_the_ground_outside_before_it_sinks() -> void:
	_barricade.set_boards(4)
	var copy := _barricade.flying()[0]
	var rise := sqrt(2.0 * Barricade.FLING_GRAVITY * Barricade.FLING_RISE)
	var drop := _board(4).position.y - Barricade.LIE_HEIGHT
	var flight := (
		(rise + sqrt(rise * rise + 2.0 * Barricade.FLING_GRAVITY * drop)) / Barricade.FLING_GRAVITY
	)
	_step(flight + 0.001)
	assert_float(copy.position.y).is_equal_approx(Barricade.LIE_HEIGHT, 0.02)
	assert_float(copy.position.z).is_equal_approx(_board(4).position.z - Barricade.FLING_OUT, 0.02)
	# Lying flat: its thin side (local Z, 0.14 m) points up or down.
	assert_float(absf(copy.basis.z.normalized().y)).is_greater(0.95)


func test_a_mended_board_is_solid_at_once_and_its_mesh_ends_in_the_slot() -> void:
	_barricade.set_boards(3, false)
	_barricade.set_boards(4)
	assert_int(_board(3).collision_layer).is_equal(Barricade.BOARD_LAYER)
	assert_bool(_board(3).visible).is_true()
	var mesh := _barricade.board_mesh(3)
	var rest := _barricade.board_mesh_rest(3)
	assert_float(mesh.position.z).is_greater(rest.origin.z + 0.3)  # starts in the field
	assert_bool(mesh.transform.is_equal_approx(rest)).is_false()
	_step(Barricade.MEND_SECONDS * 0.5)
	assert_bool(mesh.transform.is_equal_approx(rest)).is_false()
	_step(ALL_OF_IT)
	assert_bool(mesh.transform.is_equal_approx(rest)).is_true()
	assert_array(_barricade.motions()).is_empty()


func test_a_jump_moves_only_the_last_board_and_the_rest_snap() -> void:
	_barricade.set_boards(1)
	assert_int(_barricade.flying().size()).is_equal(1)
	assert_int(_barricade.motions().size()).is_equal(1)
	for i in range(1, BOARDS):
		assert_int(_board(i).collision_layer).is_equal(0)
	_barricade.finish_motion()
	_barricade.set_boards(5)
	assert_int(_barricade.motions().size()).is_equal(1)
	(
		assert_bool(
			_barricade.board_mesh(1).transform.is_equal_approx(_barricade.board_mesh_rest(1))
		)
		. is_true()
	)
	(
		assert_bool(
			_barricade.board_mesh(4).transform.is_equal_approx(_barricade.board_mesh_rest(4))
		)
		. is_false()
	)


func test_a_burst_of_tears_stays_within_the_pool() -> void:
	for round_trip in 3:
		for count in range(BOARDS - 1, -1, -1):
			_barricade.set_boards(count)
		_barricade.set_boards(BOARDS, false)
	assert_int(_barricade.flying().size()).is_less_equal(Barricade.FLYING_MAX)
	var copies := 0
	for child in _barricade.get_children():
		if child is MeshInstance3D:
			copies += 1
	assert_int(copies).is_less_equal(Barricade.FLYING_MAX)
	_step(ALL_OF_IT)
	assert_array(_barricade.flying()).is_empty()


func test_a_board_torn_mid_mend_drops_its_mend_and_flies_from_its_slot() -> void:
	_barricade.set_boards(4, false)
	_barricade.set_boards(5)
	_step(Barricade.MEND_SECONDS * 0.3)
	_barricade.set_boards(4)
	(
		assert_bool(
			_barricade.board_mesh(4).transform.is_equal_approx(_barricade.board_mesh_rest(4))
		)
		. is_true()
	)
	assert_int(_barricade.flying().size()).is_equal(1)
	assert_int(_barricade.motions().size()).is_equal(1)
