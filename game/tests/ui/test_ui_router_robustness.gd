class_name TestUIRouterRobustness
extends GdUnitTestSuite
## UIRouter never stays busy, whatever happens to its screens: a reset that loses a screen, a
## screen that frees itself as it enters, and the tree paused mid-transition. (The cases beside
## these, a freed outgoing, incoming or popped screen and a bad source, are in test_ui_router.gd.)

const SETTLE_SECONDS := 4.0
const ALL_KINDS: Array[UITransition.Kind] = [
	UITransition.Kind.CUT,
	UITransition.Kind.FADE,
	UITransition.Kind.SLIDE,
	UITransition.Kind.BURN,
	UITransition.Kind.IRIS,
]


func before_test() -> void:
	UIMotion.reduced = false
	get_tree().paused = false
	UIRouter.reset(_screen("root"), UITransition.Kind.CUT)
	await _settle()


func after_test() -> void:
	get_tree().paused = false
	# Leave the router empty: a screen left on it covers the mouse for every suite after this one.
	await RouterFixture.clear(get_tree())


func test_a_reset_whose_new_screen_is_freed_settles_with_an_empty_stack() -> void:
	var incoming := _screen("incoming")
	UIRouter.reset(incoming, UITransition.Kind.IRIS)
	await await_millis(60)
	incoming.queue_free()
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(0)
	UIRouter.push(_screen("next"), UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(1)


func test_a_reset_whose_old_screens_are_freed_still_shows_the_new_one() -> void:
	UIRouter.push(_screen("b"), UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	var incoming := _screen("incoming")
	UIRouter.reset(incoming, UITransition.Kind.BURN)
	await await_millis(60)
	for screen in UIRouter.screens():
		if screen != incoming:
			screen.queue_free()
	assert_bool(await _settle()).is_true()
	assert_object(UIRouter.top()).is_same(incoming)
	assert_bool(incoming.visible).is_true()


func test_a_screen_that_frees_itself_as_it_enters_does_not_stall_the_router() -> void:
	for kind in ALL_KINDS:
		var screen := _screen("suicide")
		screen.ready.connect(screen.queue_free)
		UIRouter.push(screen, kind)
		assert_bool(await _settle()).override_failure_message("stalled on kind %d" % kind).is_true()
		(
			assert_array(
				UIRouter.screens().map(func(s: Control) -> String: return s.get_meta(&"label"))
			)
			. is_equal(["root"])
		)
		assert_bool(UIRouter.top().visible).is_true()


func test_a_transition_finishes_while_the_tree_is_paused() -> void:
	for kind in ALL_KINDS:
		get_tree().paused = true
		UIRouter.push(_screen("b"), kind)
		var waited := 0.0
		while UIRouter.busy and waited < SETTLE_SECONDS:
			await get_tree().create_timer(0.05, true).timeout
			waited += 0.05
		get_tree().paused = false
		assert_bool(UIRouter.busy).override_failure_message("stalled on kind %d" % kind).is_false()
		UIRouter.pop(UITransition.Kind.CUT)
		assert_bool(await _settle()).is_true()


func _screen(screen_name: String) -> Control:
	var screen := Control.new()
	screen.name = screen_name
	screen.set_meta(&"label", screen_name)
	return screen


func _settle() -> bool:
	var waited := 0.0
	while UIRouter.busy and waited < SETTLE_SECONDS:
		await get_tree().process_frame
		waited += get_tree().root.get_process_delta_time()
	return not UIRouter.busy
