class_name TestUIRouter
extends GdUnitTestSuite
## UIRouter: queued calls, back, a screen freed mid-transition, a bad source, and the slide pop.
##
## The router is the project autoload. Every test starts from a fresh root screen "root".

const SETTLE_SECONDS := 4.0
## A transition looked at mid-way runs at this share of real speed for this many frames.
const MID_SLIDE_TIME_SCALE := 0.02
const MID_SLIDE_FRAMES := 3
const ALL_KINDS: Array[UITransition.Kind] = [
	UITransition.Kind.FADE,
	UITransition.Kind.SLIDE,
	UITransition.Kind.BURN,
	UITransition.Kind.IRIS,
]


func before_test() -> void:
	UIMotion.reduced = false
	UIRouter.reset(_screen("root"), UITransition.Kind.CUT)
	await _settle()


func after_test() -> void:
	Engine.time_scale = 1.0
	# Leave the router empty: a screen left on it covers the mouse for every suite after this one.
	await RouterFixture.clear(get_tree())


func test_queued_calls_run_in_order() -> void:
	UIRouter.push(_screen("b"), UITransition.Kind.CUT)
	UIRouter.push(_screen("c"), UITransition.Kind.CUT)
	UIRouter.pop()
	UIRouter.replace(_screen("d"), UITransition.Kind.CUT)
	assert_bool(UIRouter.busy).is_true()
	assert_bool(await _settle()).is_true()
	assert_array(_names()).is_equal(["root", "d"])
	assert_str(UIRouter.top().get_meta(&"label")).is_equal("d")


func test_queued_calls_with_transitions_end_on_the_right_stack() -> void:
	UIRouter.push(_screen("b"), UITransition.Kind.FADE)
	UIRouter.push(_screen("c"), UITransition.Kind.SLIDE)
	UIRouter.pop()
	assert_bool(await _settle()).is_true()
	assert_array(_names()).is_equal(["root", "b"])
	assert_bool(UIRouter.top().visible).is_true()
	assert_float(UIRouter.top().modulate.a).is_equal(1.0)


func test_pop_at_the_root_does_nothing() -> void:
	var changes := []
	UIRouter.screen_changed.connect(func(depth: int) -> void: changes.append(depth))
	UIRouter.pop()
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(1)
	assert_array(changes).is_empty()
	assert_bool(UIRouter.top().visible).is_true()


func test_back_pops_when_idle_and_is_ignored_while_busy() -> void:
	UIRouter.push(_screen("b"), UITransition.Kind.FADE)
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(2)
	UIRouter.push(_screen("c"), UITransition.Kind.FADE)
	_press_back()
	assert_bool(await _settle()).is_true()
	assert_array(_names()).is_equal(["root", "b", "c"])
	_press_back()
	assert_bool(await _settle()).is_true()
	assert_array(_names()).is_equal(["root", "b"])


func test_back_at_the_root_is_ignored() -> void:
	_press_back()
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(1)


func test_a_screen_freed_during_a_transition_does_not_stall_the_router() -> void:
	for kind in ALL_KINDS:
		var old := _screen("old")
		UIRouter.reset(old, UITransition.Kind.CUT)
		await _settle()
		UIRouter.push(_screen("next"), kind)
		await await_millis(60)
		old.queue_free()
		assert_bool(await _settle()).override_failure_message("stalled on kind %d" % kind).is_true()
		assert_array(_names()).is_equal(["next"])
		UIRouter.push(_screen("after"), UITransition.Kind.CUT)
		assert_bool(await _settle()).is_true()
		assert_array(_names()).is_equal(["next", "after"])


func test_the_incoming_screen_freed_during_a_transition_keeps_the_old_one() -> void:
	for kind in ALL_KINDS:
		var base := UIRouter.top()
		var incoming := _screen("lost")
		UIRouter.push(incoming, kind)
		await await_millis(60)
		incoming.queue_free()
		assert_bool(await _settle()).override_failure_message("stalled on kind %d" % kind).is_true()
		assert_object(UIRouter.top()).is_same(base)
		assert_bool(base.visible).is_true()
		assert_float(base.modulate.a).is_equal(1.0)
		assert_float(base.position.x).is_equal(0.0)


func test_a_popped_screen_freed_during_the_pop_does_not_stall_the_router() -> void:
	var top := _screen("top")
	UIRouter.push(top, UITransition.Kind.CUT)
	await _settle()
	UIRouter.pop(UITransition.Kind.SLIDE)
	await await_millis(60)
	top.queue_free()
	assert_bool(await _settle()).is_true()
	assert_array(_names()).is_equal(["root"])
	assert_bool(UIRouter.top().visible).is_true()


func test_a_bad_source_is_refused_and_the_router_carries_on() -> void:
	var changes := []
	var errors := []
	UIRouter.screen_changed.connect(func(depth: int) -> void: changes.append(depth))
	UIRouter.error_reported.connect(func(message: String) -> void: errors.append(message))
	var freed := _screen("freed")
	freed.free()
	var stacked := UIRouter.top()
	var parented := _screen("parented")
	add_child(parented)
	var bad: Array = [
		"res://does/not/exist.tscn",
		"res://project.godot",
		42,
		null,
		auto_free(Node.new()),
		&"nope",
		freed,
		stacked,
		parented,
	]
	for source: Variant in bad:
		UIRouter.push(source, UITransition.Kind.FADE)
		assert_bool(await _settle()).is_true()
		assert_array(_names()).is_equal(["root"])
	assert_array(changes).is_empty()
	assert_int(errors.size()).override_failure_message("one error per refused call").is_equal(
		bad.size()
	)
	(
		assert_bool(is_instance_valid(stacked))
		. override_failure_message("a refused screen is not freed")
		. is_true()
	)
	assert_object(parented.get_parent()).is_same(self)
	parented.queue_free()
	UIRouter.push(_screen("good"), UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	assert_array(_names()).is_equal(["root", "good"])


func test_the_same_screen_pushed_twice_is_shown_once() -> void:
	var errors := []
	UIRouter.error_reported.connect(func(message: String) -> void: errors.append(message))
	var card := _screen("card")
	UIRouter.push(card, UITransition.Kind.CUT)
	UIRouter.push(card, UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	assert_array(_names()).is_equal(["root", "card"])
	assert_int(errors.size()).is_equal(1)


func test_freeing_the_top_screen_while_idle_reveals_the_one_below() -> void:
	var base := UIRouter.top()
	var card := _screen("card")
	UIRouter.push(card, UITransition.Kind.FADE)
	assert_bool(await _settle()).is_true()
	assert_bool(base.visible).is_false()
	var changes := []
	UIRouter.screen_changed.connect(func(depth: int) -> void: changes.append(depth))
	card.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(UIRouter.top()).is_same(base)
	assert_bool(base.visible).is_true()
	assert_int(base.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)
	assert_float(base.modulate.a).is_equal(1.0)
	assert_array(changes).is_equal([1])
	# The revealed screen is a live one: the router can leave and return to it.
	UIRouter.push(_screen("again"), UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	assert_array(_names()).is_equal(["root", "again"])


func test_freeing_two_screens_at_once_reveals_the_right_one_once() -> void:
	var base := UIRouter.top()
	var middle := _screen("middle")
	var card := _screen("card")
	UIRouter.push(middle, UITransition.Kind.CUT)
	UIRouter.push(card, UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	var changes := []
	UIRouter.screen_changed.connect(func(depth: int) -> void: changes.append(depth))
	card.queue_free()
	middle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(UIRouter.top()).is_same(base)
	assert_bool(base.visible).is_true()
	assert_array(changes).is_equal([1])


func test_freeing_the_only_screen_leaves_a_reported_empty_stack() -> void:
	var changes := []
	UIRouter.screen_changed.connect(func(depth: int) -> void: changes.append(depth))
	UIRouter.top().queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(UIRouter.depth()).is_equal(0)
	assert_array(changes).is_equal([0])
	UIRouter.push(_screen("next"), UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	assert_array(_names()).is_equal(["next"])


func test_a_pop_that_loses_its_target_is_reported() -> void:
	var base := UIRouter.top()
	UIRouter.push(_screen("card"), UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	var changes := []
	var errors := []
	UIRouter.screen_changed.connect(func(depth: int) -> void: changes.append(depth))
	UIRouter.error_reported.connect(func(message: String) -> void: errors.append(message))
	UIRouter.pop(UITransition.Kind.SLIDE)
	await await_millis(60)
	base.queue_free()
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(0)
	assert_array(errors).is_equal([UIRouter.LOST_POP_TARGET])
	assert_array(changes).is_equal([0])
	UIRouter.push(_screen("next"), UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	assert_array(_names()).is_equal(["next"])


func test_a_pop_whose_target_is_freed_shows_the_next_one_down() -> void:
	var base := UIRouter.top()
	var middle := _screen("middle")
	UIRouter.push(middle, UITransition.Kind.CUT)
	UIRouter.push(_screen("card"), UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	UIRouter.pop(UITransition.Kind.SLIDE)
	await await_millis(60)
	middle.queue_free()
	assert_bool(await _settle()).is_true()
	assert_object(UIRouter.top()).is_same(base)
	assert_bool(base.visible).is_true()
	assert_int(base.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)


func test_a_scene_path_is_loaded() -> void:
	UIRouter.push("res://addons/gds_ui/demo/states_sheet.tscn", UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(2)


func test_a_slide_pop_mirrors_the_push() -> void:
	var below := UIRouter.top()
	var card := _screen("card")
	UIRouter.push(card, UITransition.Kind.SLIDE)
	assert_bool(await _settle()).is_true()
	var width := card.size.x
	assert_float(width).is_greater(0.0)
	# The slide runs in slow motion while it is looked at, and the look waits for frames, not for
	# milliseconds: on a loaded machine a frame can outlast 60 ms, so the look came before the slide
	# had moved or after it had ended (#199).
	Engine.time_scale = MID_SLIDE_TIME_SCALE
	UIRouter.pop()
	for _i in MID_SLIDE_FRAMES:
		await get_tree().process_frame
	# The leaving screen is on top and travelling off to the right.
	assert_int(card.get_index()).is_greater(below.get_index())
	assert_bool(card.position.x > 0.0).is_true()
	# The screen underneath is visible, a third of the way out to the left at most, and dimmed.
	assert_bool(below.visible).is_true()
	assert_bool(below.position.x <= 0.0).is_true()
	assert_bool(below.position.x >= -width * UITokens.active().slide_parallax).is_true()
	assert_bool(below.modulate.r < 1.0).is_true()
	Engine.time_scale = 1.0
	assert_bool(await _settle()).is_true()
	assert_float(below.position.x).is_equal(0.0)
	assert_object(below.modulate).is_equal(Color.WHITE)
	assert_bool(below.visible).is_true()
	assert_bool(is_instance_valid(card)).is_false()


func test_a_slide_push_puts_the_entering_screen_on_top() -> void:
	var below := UIRouter.top()
	var card := _screen("card")
	UIRouter.push(card, UITransition.Kind.SLIDE)
	await await_millis(60)
	assert_int(card.get_index()).is_greater(below.get_index())
	assert_bool(card.position.x > 0.0).is_true()
	assert_bool(below.position.x <= 0.0).is_true()
	assert_bool(await _settle()).is_true()


func _screen(screen_name: String) -> Control:
	var screen := Control.new()
	# The node name is made unique by the tree while an old screen of the same name waits to be freed.
	screen.name = screen_name
	screen.set_meta(&"label", screen_name)
	return screen


func _names() -> Array:
	return UIRouter.screens().map(func(screen: Control) -> String: return screen.get_meta(&"label"))


## Waits until the router has drained its queue; false when it is still busy after the limit.
func _settle() -> bool:
	var waited := 0.0
	while UIRouter.busy and waited < SETTLE_SECONDS:
		await get_tree().process_frame
		waited += get_tree().root.get_process_delta_time()
	return not UIRouter.busy


func _press_back() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	UIRouter.get_viewport().push_input(event)
