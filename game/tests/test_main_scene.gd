# Smoke test: the main scene loads and the game starts on the main menu.
extends GdUnitTestSuite


func after_test() -> void:
	# The scene leaves its main menu on the global router, with its entrance timer still running.
	await RouterFixture.clear(get_tree())


func test_main_scene_loads_and_shows_the_main_menu() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	await UIRouter.idle
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	runner.invoke("queue_free")


# A canvas layer is a canvas pass of its own, empty or not, and the web page keeps the fence sync
# every pass makes until it closes (#883): the game's overlays share the router's layer.
func test_the_game_has_one_canvas_layer_the_routers_with_the_film_on_top() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	await UIRouter.idle
	var layers := get_tree().root.find_children("*", "CanvasLayer", true, false)
	assert_array(layers).contains_exactly([UIRouter])
	assert_object(UIRouter.get_child(-1)).is_instanceof(FilmOverlay)
	(
		assert_array(
			UIRouter.get_children().filter(func(n: Node) -> bool: return n is ControllerHint)
		)
		. has_size(1)
	)
	(
		assert_array(
			UIRouter.get_children().filter(func(n: Node) -> bool: return n is TouchRotatePrompt)
		)
		. has_size(1)
	)
	runner.invoke("queue_free")
	await await_idle_frame()
	# Gone with the scene, so the next one starts from the router alone.
	(
		assert_array(UIRouter.get_children().filter(func(n: Node) -> bool: return n is FilmOverlay))
		. is_empty()
	)
