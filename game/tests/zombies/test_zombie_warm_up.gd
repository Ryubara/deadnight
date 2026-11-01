# The zombies' shared library is built when the horde is set up, not when the first zombie
# appears (#245: the first spawns cost a 31 ms frame in the barricades capture).
extends GdUnitTestSuite


func after_test() -> void:
	ZombieRig.release()


func _first_view_ms() -> float:
	var started := Time.get_ticks_usec()
	var view := ZombieView.new()
	add_child(auto_free(view))
	view.setup(ZombieModels.scene(ZombieModels.DEFAULT), 1, 0.0, 0.7, ZombieModels.DEFAULT)
	return (Time.get_ticks_usec() - started) / 1000.0


func test_setting_up_the_horde_builds_the_library() -> void:
	ZombieRig.release()
	assert_object(ZombieRig._library).is_null()
	var horde := ZombieHorde.new()
	add_child(auto_free(horde))
	horde.setup_client(null, 1.0)
	assert_object(ZombieRig._library).is_not_null()
	assert_bool(ZombieRig._library.has_animation(ZombieRig.TEAR_CLIP)).is_true()
	# The first zombie reuses it.
	var built := ZombieRig._library
	_first_view_ms()
	assert_object(ZombieRig._library).is_same(built)


func test_warming_up_moves_the_cost_off_the_first_zombie() -> void:
	ZombieRig.release()
	var cold := _first_view_ms()
	ZombieRig.release()
	var started := Time.get_ticks_usec()
	ZombieRig.warm_up()
	var warm_up := (Time.get_ticks_usec() - started) / 1000.0
	var warm := _first_view_ms()
	print(
		(
			"first zombie: cold %.1f ms, after the warm-up %.1f ms (warm-up %.1f ms)"
			% [cold, warm, warm_up]
		)
	)
	assert_float(warm).is_less(cold)
