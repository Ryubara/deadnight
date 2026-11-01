# Smoke test: the main scene loads, and its title reads DEADNIGHT.
extends GdUnitTestSuite


func test_main_scene_loads_with_title() -> void:
	var runner := scene_runner("res://main.tscn")
	var title: Label = runner.find_child("Title")
	assert_object(title).is_not_null()
	assert_str(title.text).is_equal("DEADNIGHT")
