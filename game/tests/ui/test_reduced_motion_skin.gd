# Reduced motion reaches the whole skin at once, while the main scene runs: the film overlay
# (flicker, changing grain), the sky and the sign follow `UIMotion.reduced` live.
# A photosensitivity concern.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"

var _was_reduced := false


func before_test() -> void:
	_was_reduced = UIMotion.reduced
	UIMotion.reduced = false


func after_test() -> void:
	UIMotion.reduced = _was_reduced


func _motion_of(node: CanvasItem) -> float:
	return (node.material as ShaderMaterial).get_shader_parameter(&"motion")


func test_the_overlay_and_the_stage_follow_the_setting_live() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	await UIRouter.idle
	var film := UIRouter.get_node("Film") as FilmOverlay
	var menu := UIRouter.top() as MainMenu
	var stage := menu.shell.view.stage
	assert_object(film).is_not_null()
	assert_float(_motion_of(film)).is_equal(1.0)
	assert_bool(stage.animated).is_true()
	UIMotion.reduced = true
	assert_float(_motion_of(film)).is_equal(0.0)
	assert_bool(stage.animated).is_false()
	UIMotion.reduced = false
	assert_float(_motion_of(film)).is_equal(1.0)
	assert_bool(stage.animated).is_true()
	runner.invoke("queue_free")
	# The router is shared by every suite: a menu left on it would answer the next suite's bumpers.
	await RouterFixture.clear(get_tree())


func test_a_skin_built_while_reduced_starts_calm() -> void:
	UIMotion.reduced = true
	var sky: NightSky = auto_free(NightSky.new())
	add_child(sky)
	assert_float(_motion_of(sky)).is_equal(0.0)
	var film: FilmOverlay = auto_free(FilmOverlay.new())
	add_child(film)
	assert_float(_motion_of(film)).is_equal(0.0)


func test_the_sign_is_lit_and_still_when_reduced() -> void:
	var menu: MainMenu = auto_free((load(MENU) as PackedScene).instantiate())
	add_child(menu)
	var sign_node := menu.find_child("Sign", true, false) as NeonSign
	await await_idle_frame()
	assert_bool(sign_node.is_processing()).is_true()
	assert_float(sign_node._level(0)).is_less(1.0)
	UIMotion.reduced = true
	assert_bool(sign_node.is_processing()).is_false()
	for i in sign_node.text.length():
		assert_float(sign_node._level(i)).is_equal(1.0)
	var clock := sign_node.clock
	await await_idle_frame()
	await await_idle_frame()
	assert_float(sign_node.clock).is_equal(clock)
	# Turned off again: it carries on as a lit sign, not from dark.
	UIMotion.reduced = false
	assert_bool(sign_node.is_processing()).is_true()
	assert_float(sign_node._level(0)).is_greater(0.5)


func test_the_change_signal_fires_once_per_change() -> void:
	var seen: Array[bool] = []
	var listener := func(reduced: bool) -> void: seen.append(reduced)
	UIMotion.changed().connect(listener)
	UIMotion.reduced = true
	UIMotion.reduced = true
	UIMotion.reduced = false
	UIMotion.changed().disconnect(listener)
	assert_array(seen).contains_exactly([true, false])
