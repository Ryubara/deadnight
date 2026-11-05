# The reticle is on screen from the first running frame of a night, however the player got there:
# alone from the menu's Solo, or into a friend's night from the Join screen (#517). The screen hides
# the reticle under every overlay ("Joining", the pause card, the result) and the Resume button was
# the only place that showed it again, so a night joined online ran with no crosshair until a pause
# and a Resume. A headless run skips the loading screen, which a player always sees: it is turned on
# here as in the game. The helicopter drop that opens a person's night (#1057) hides the reticle
# until it ends: the first three tests run a night with no drop due (a window plays it, a headless
# run does not, so the suite said different things in the two), the last four run the drop and
# watch the reticle leave and come back.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"

var _host: NightHost
var _warm_up := false
var _arrival := false


func before_test() -> void:
	_warm_up = NightScreen.warm_up_enabled
	_arrival = NightScreen.arrival_enabled
	# No drop due, as headless always has it (`--noarrival`): the tests that want the drop turn it on.
	NightScreen.arrival_enabled = false
	NightScreen.warm_up_enabled = true


func after_test() -> void:
	NightScreen.warm_up_enabled = _warm_up
	NightScreen.arrival_enabled = _arrival
	NightScreen.join_url = ""
	NightScreen.join_ticket = ""
	await RouterFixture.clear(get_tree())
	if is_instance_valid(_host):
		_host.get_parent().queue_free()
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


func _server() -> NightHost:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	viewport.add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


## Waits for `condition` up to `seconds`, a frame at a time; true if it came.
func _until(condition: Callable, seconds: float = 20.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().process_frame
	return true


func _reticle(screen: NightScreen) -> HudReticle:
	return screen.find_children("*", "HudReticle", true, false)[0] as HudReticle


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func test_a_solo_night_shows_the_reticle_on_the_first_running_frame() -> void:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.IRIS)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	assert_bool(screen.night.running).is_true()
	assert_bool(_reticle(screen).is_visible_in_tree()).is_true()
	assert_bool(WebProbe.snapshot(screen)["reticle"]).is_true()


func test_a_night_joined_online_shows_the_reticle_on_the_first_running_frame() -> void:
	await _server()
	NightScreen.join_url = "ws://127.0.0.1:%d" % _host.listener.port()
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.IRIS)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	var joined := await _until(func() -> bool: return screen.night.running)
	assert_bool(joined).is_true()
	await _frames(2)
	assert_bool(screen.night.is_paused()).is_false()
	(
		assert_bool(_reticle(screen).is_visible_in_tree())
		. override_failure_message("the joined night runs with no reticle on screen")
		. is_true()
	)
	assert_bool(WebProbe.snapshot(screen)["reticle"]).is_true()
	# What the "Joining" card took away besides the reticle comes back with it.
	assert_bool(screen.night.hud.scoreboard_enabled).is_true()
	var touch := screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
	assert_bool(touch.live).is_true()


func test_the_reticle_comes_back_after_a_pause_and_a_resume() -> void:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	screen._pause()
	assert_bool(_reticle(screen).is_visible_in_tree()).is_false()
	screen._resume_night()
	assert_bool(_reticle(screen).is_visible_in_tree()).is_true()


# The three above run a night with no drop due (the player's own switch, `--noarrival`, and what a
# headless run always has). A person's night opens with the helicopter drop (#1057), which a window
# plays and a headless run skips unless it is asked for: the reticle gives way to the show and is
# the player's again when it ends. A windowed run of the three above failed for that reason alone.
func _arrival_night() -> NightScreen:
	NightScreen.arrival_enabled = true
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	return screen


func _assert_the_drop_has_the_reticle_away_and_the_night_gives_it_back(screen: NightScreen) -> void:
	assert_bool(screen.night.is_arriving()).is_true()
	assert_bool(_reticle(screen).is_visible_in_tree()).is_false()
	assert_bool(WebProbe.snapshot(screen)["reticle"]).is_false()
	# A press skips it after the table's `skip_after`; the same end, now.
	screen.night.arrival_show.skip_now()
	assert_bool(screen.night.is_arriving()).is_false()
	assert_bool(_reticle(screen).is_visible_in_tree()).is_true()
	assert_bool(WebProbe.snapshot(screen)["reticle"]).is_true()
	assert_bool(screen.night.hud.scoreboard_enabled).is_true()
	var touch := screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
	assert_bool(touch.live).is_true()


func test_a_solo_night_with_the_drop_shows_the_reticle_when_the_drop_ends() -> void:
	var screen := await _arrival_night()
	_assert_the_drop_has_the_reticle_away_and_the_night_gives_it_back(screen)


func test_a_night_joined_online_with_the_drop_shows_the_reticle_when_the_drop_ends() -> void:
	await _server()
	NightScreen.join_url = "ws://127.0.0.1:%d" % _host.listener.port()
	NightScreen.arrival_enabled = true
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	var joined := await _until(func() -> bool: return screen.night.running)
	assert_bool(joined).is_true()
	await _until(func() -> bool: return screen.night.is_arriving())
	_assert_the_drop_has_the_reticle_away_and_the_night_gives_it_back(screen)


func test_a_resume_under_the_drop_leaves_the_reticle_to_the_drop() -> void:
	var screen := await _arrival_night()
	screen._pause()
	screen._resume_night()
	assert_bool(screen.night.is_arriving()).is_true()
	assert_bool(_reticle(screen).is_visible_in_tree()).is_false()
	screen.night.arrival_show.skip_now()
	assert_bool(_reticle(screen).is_visible_in_tree()).is_true()


func test_a_drop_that_ends_under_the_pause_card_gives_the_reticle_back_on_resume() -> void:
	var screen := await _arrival_night()
	screen._pause()
	screen.night.arrival_show.skip_now()
	assert_bool(_reticle(screen).is_visible_in_tree()).is_false()
	screen._resume_night()
	assert_bool(_reticle(screen).is_visible_in_tree()).is_true()
