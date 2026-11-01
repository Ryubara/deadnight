# Smoke test: the main scene loads and the game starts on the main menu.
extends GdUnitTestSuite


func test_main_scene_loads_and_shows_the_main_menu() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	await UIRouter.idle
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	runner.invoke("queue_free")
