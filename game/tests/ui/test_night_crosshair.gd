# The reticle is on screen from the first running frame of a night, however the player got there:
# alone from the menu's Solo, or into a friend's night from the Join screen (#517). The screen hides
# the reticle under every overlay ("Joining", the pause card, the result) and the Resume button was
# the only place that showed it again, so a night joined online ran with no crosshair until a pause
# and a Resume. A headless run skips the loading screen, which a player always sees: it is turned on
# here as in the game.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"

var _host: NightHost
var _warm_up := false


func before_test() -> void:
	_warm_up = NightScreen.warm_up_enabled
	NightScreen.warm_up_enabled = true


func after_test() -> void:
	NightScreen.warm_up_enabled = _warm_up
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
