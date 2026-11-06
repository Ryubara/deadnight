# A join goes on behind the loading screen, drawn over the rest of the night's screen: it says what
# is being done, and a join that fails shows why, with the way out (#1366).
extends GdUnitTestSuite

## No server listens on this port, so the join fails by itself.
const NOBODY := "ws://127.0.0.1:1"
const WAIT_SECONDS := 40.0

var _warm_up := false


func before() -> void:
	await WindowFixture.make_drawable(get_tree())


func before_test() -> void:
	_warm_up = NightScreen.warm_up_enabled
	NightScreen.warm_up_enabled = true


func after_test() -> void:
	NightScreen.warm_up_enabled = _warm_up
	await RouterFixture.clear(get_tree())
	Audio.stop_all()


func test_a_failed_join_shows_its_card_and_not_the_loading_screen() -> void:
	var screen := await _failed_join()
	assert_bool(screen._overlay.is_visible_in_tree()).is_true()
	assert_str(screen._title.text).is_equal("Could not join")
	assert_bool(screen._note.text.is_empty()).is_false()
	assert_array(_loading_screens(screen)).is_empty()
	assert_bool(screen._quit.is_visible_in_tree()).is_true()


func test_the_bar_says_what_a_join_is_doing() -> void:
	var steps: Array[String] = []
	var screen := await _failed_join(steps)
	assert_object(screen).is_not_null()
	assert_array(steps).contains_exactly(["Building the lot", "Joining the night"])


## A night's screen that tried to join nobody, with the join over. `steps` gets the bar's lines.
func _failed_join(steps: Variant = null) -> NightScreen:
	NightScreen.join_url = NOBODY
	var screen := auto_free(load("res://ui/screens/night_screen.tscn").instantiate()) as NightScreen
	add_child(screen)
	var over := {"done": false}
	screen.night.connect_failed.connect(func(_why: String) -> void: over["done"] = true)
	if steps != null:
		screen.night.loading.connect(func(_part: float, text: String) -> void: steps.append(text))
	screen.screen_enter()
	var began := Time.get_ticks_msec()
	while not over["done"] and (Time.get_ticks_msec() - began) / 1000.0 < WAIT_SECONDS:
		await get_tree().process_frame
	assert_bool(over["done"]).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func _loading_screens(screen: NightScreen) -> Array:
	return screen.get_children().filter(
		func(child: Node) -> bool:
			return child is LoadingOverlay and not child.is_queued_for_deletion()
	)
