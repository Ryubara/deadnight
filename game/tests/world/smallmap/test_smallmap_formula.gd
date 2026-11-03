# gdlint: disable=max-public-methods
# The second map's greybox against the hard targets of docs/research/maps/small-map-formula.md
# (rows 1 to 19 and 27 to 29): one test a row, each failing outside its tolerance. The map is
# measured once for the suite (`SmallMapMeasure`); `smallmap_report.gd` prints the same table.
extends GdUnitTestSuite

var _measure: SmallMapMeasure


func before() -> void:
	_measure = SmallMapMeasure.new()
	await _measure.run(self)


func after() -> void:
	_measure = null


func _holds(number: int) -> void:
	var entry := _measure.row(number)
	(
		assert_bool(entry.is_empty())
		. override_failure_message("row %d was not measured" % number)
		. is_false()
	)
	(
		assert_bool(entry.get("ok", false))
		. override_failure_message(
			(
				"row %d (%s): %s, tolerance %s to %s %s. %s"
				% [
					number,
					entry["name"],
					entry["value"],
					entry["lo"],
					entry["hi"],
					entry["unit"],
					entry["detail"]
				]
			)
		)
		. is_true()
	)


func test_row_01_total_floor_is_540_to_660_square_metres() -> void:
	_holds(1)


func test_row_02_the_map_has_two_floors() -> void:
	_holds(2)


func test_row_03_three_rooms_and_the_upstairs_halves_join_without_a_link() -> void:
	_holds(3)


func test_row_04_the_start_room_is_188_to_230_square_metres() -> void:
	_holds(4)


func test_row_05_the_side_room_is_138_to_168_square_metres() -> void:
	_holds(5)


func test_row_06_the_upstairs_is_197_to_241_square_metres_and_the_largest() -> void:
	_holds(6)


func test_row_07_the_side_room_is_long_and_narrow() -> void:
	_holds(7)


func test_row_08_the_start_rooms_counter_makes_a_25_to_36_metre_loop() -> void:
	_holds(8)


func test_row_09_every_ceiling_is_3_to_3_6_metres() -> void:
	_holds(9)


func test_row_10_the_longest_sight_line_is_16_to_24_metres() -> void:
	_holds(10)


func test_row_11_three_paid_links_each_join_two_rooms() -> void:
	_holds(11)


func test_row_12_one_ring_closed_only_by_the_third_link() -> void:
	_holds(12)


func test_row_13_the_rings_lap_is_48_to_72_metres() -> void:
	_holds(13)


func test_row_14_the_side_rooms_racks_make_a_25_to_36_metre_loop() -> void:
	_holds(14)


func test_row_15_windows_are_five_three_and_four() -> void:
	_holds(15)


func test_row_16_directions_to_watch_are_three_three_and_two() -> void:
	_holds(16)


func test_row_17_the_players_start_4_to_7_metres_from_a_window() -> void:
	_holds(17)


func test_row_18_each_spawn_is_5_to_15_metres_out_and_reaches_its_room_only() -> void:
	_holds(18)


func test_row_19_two_stairs_one_from_each_ground_room() -> void:
	_holds(19)


func test_row_27_every_camera_passage_is_wide_enough() -> void:
	_holds(27)


func test_row_28_the_camera_never_ends_in_a_wall_at_a_probe() -> void:
	_holds(28)


func test_row_29_nothing_is_named_after_nacht() -> void:
	_holds(29)
