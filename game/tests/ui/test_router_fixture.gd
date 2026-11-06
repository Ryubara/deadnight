class_name TestRouterFixture
extends GdUnitTestSuite
## `RouterFixture.clear` frees no screen before its caller has yielded (#1355).
##
## A test that waits on a signal (`await night.ready_to_play`) resumes inside that signal's emit. If
## its next step is `clear`, a screen freed at once is freed while the night it holds is still
## emitting, and the engine prints "freed or unreferenced while a signal is being emitted from it"
## (three lines in `test_night_tap_targets`), which no check catches since the suite passes. A
## screen still alive when `clear` first gives control back is one the emit can finish with.


func after_test() -> void:
	await RouterFixture.clear(get_tree())


func test_clear_leaves_the_screen_alone_until_its_caller_has_yielded() -> void:
	var screen := Control.new()
	UIRouter.reset(screen, UITransition.Kind.CUT)
	await UIRouter.idle
	assert_object(UIRouter.top()).is_same(screen)
	RouterFixture.clear(get_tree())
	# `clear` has run as far as its first wait: where a caller inside an emit gets control back.
	assert_bool(is_instance_valid(screen)).is_true()
	await RouterFixture.clear(get_tree())
	assert_bool(is_instance_valid(screen)).is_false()
	assert_int(UIRouter.depth()).is_equal(0)
