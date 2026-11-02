# The name a seat shows: the ticket's name, kept apart from every other seat's.
extends GdUnitTestSuite


func test_a_name_nobody_else_has_stays_as_it_is() -> void:
	assert_str(NightHost.unique_name("Ann", {1: "Bo"}, 2)).is_equal("Ann")
	assert_str(NightHost.unique_name("  Ann  ", {}, 1)).is_equal("Ann")


func test_no_name_is_no_name() -> void:
	assert_str(NightHost.unique_name("", {1: "Bo"}, 2)).is_empty()
	assert_str(NightHost.unique_name("   ", {}, 1)).is_empty()


func test_a_name_somebody_has_gets_the_next_free_number_in_any_case_of_letters() -> void:
	assert_str(NightHost.unique_name("Ann", {1: "Ann"}, 2)).is_equal("Ann (2)")
	assert_str(NightHost.unique_name("ann", {1: "Ann", 2: "Ann (2)"}, 3)).is_equal("ann (3)")
	var taken := {1: "Ann", 2: "Ann (2)", 3: "Ann (3)"}
	assert_str(NightHost.unique_name("Ann", taken, 4)).is_equal("Ann (4)")


func test_a_seat_keeps_its_own_name_and_a_taken_number_is_skipped() -> void:
	# Asking again for the name a seat already has is not a duplicate of itself.
	assert_str(NightHost.unique_name("Ann", {1: "Ann"}, 1)).is_equal("Ann")
	assert_str(NightHost.unique_name("Ann", {1: "Ann", 3: "Ann (2)"}, 2)).is_equal("Ann (3)")


func test_a_long_name_is_cut_so_the_number_is_never_cut_off() -> void:
	var long_name := "W".repeat(40)
	var first := NightHost.unique_name(long_name, {}, 1)
	assert_int(first.length()).is_equal(NightHost.NAME_MAX)
	var second := NightHost.unique_name(long_name, {1: first}, 2)
	assert_int(second.length()).is_equal(NightHost.NAME_MAX)
	assert_bool(second.ends_with(" (2)")).is_true()
