# The menu's ambience bed (#926): it starts with the main menu, every screen the menu pushes keeps
# it, it ends when a night loads and comes back with the menu, it is on the Ambience bus with its
# slider, and the sign's flicker (a timer, not an event of the player's) makes no sound.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const SETTINGS := "res://ui/screens/settings_screen.tscn"
const CREDITS := "res://ui/screens/credits_screen.tscn"
const TEST_PATH := "user://menu_ambience_test.cfg"
## The fade takes 60 dB at 30 dB a second out and 20 in: past both.
const FADE_OUT_S := 2.1
const FADE_IN_S := 3.1

var _saved_path: String


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	Audio.stop_beds(true)
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()


func after_test() -> void:
	await RouterFixture.clear(get_tree())
	Audio.stop_beds(true)
	MainMenu.board_factory = Callable()
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Audio.install_ui_hook()


func _show_menu() -> MainMenu:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	return UIRouter.top() as MainMenu


func _push(path: String) -> void:
	UIRouter.push(path, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()


func test_the_bed_is_two_looped_streams_on_the_ambience_bus_that_the_night_already_loads() -> void:
	var night_files := {}
	for id: StringName in [&"bed_crickets", &"bed_projector"]:
		night_files[SoundCatalog.get_def(id).path_for(1)] = true
	assert_int(MenuAmbience.BEDS.size()).is_equal(2)
	# Each is quieter than the night's own bed of its kind.
	var night_trim := {
		&"bed_menu_crickets": SoundCatalog.get_def(&"bed_crickets").volume_db,
		&"bed_menu_projector": SoundCatalog.get_def(&"bed_projector").volume_db,
	}
	for id in MenuAmbience.BEDS:
		var def := SoundCatalog.get_def(id)
		assert_str(def.bus).is_equal("Ambience")
		assert_bool(def.loop).is_true()
		assert_bool(def.deferred).is_false()
		# No file of its own: the same Ogg as the night's bed, under a quieter trim.
		assert_bool(night_files.has(def.path_for(1))).override_failure_message(id).is_true()
		assert_float(def.volume_db).override_failure_message(id).is_less(night_trim[id])


func test_the_bed_starts_with_the_menu_and_fades_in() -> void:
	assert_bool(MenuAmbience.is_playing()).is_false()
	await _show_menu()
	assert_bool(MenuAmbience.is_playing()).is_true()
	for id in MenuAmbience.BEDS:
		assert_float(Audio.bed_fade_db(id)).is_less_equal(AudioService.BED_SILENT_DB + 5.0)
	Audio.advance(FADE_IN_S)
	for id in MenuAmbience.BEDS:
		assert_float(Audio.bed_fade_db(id)).is_equal(0.0)


func test_a_screen_pushed_over_the_menu_keeps_the_bed_and_the_return_does_not_double_it() -> void:
	await _show_menu()
	Audio.advance(FADE_IN_S)
	await _push(SETTINGS)
	assert_bool(MenuAmbience.is_playing()).is_true()
	await _push(CREDITS)
	assert_bool(MenuAmbience.is_playing()).is_true()
	UIRouter.pop()
	await UIRouter.idle
	UIRouter.pop()
	await UIRouter.idle
	await await_idle_frame()
	assert_bool(MenuAmbience.is_playing()).is_true()
	# Coming back turned the running beds up; it did not start them again from silence.
	for id in MenuAmbience.BEDS:
		assert_float(Audio.bed_fade_db(id)).is_equal(0.0)


func test_the_bed_ends_when_a_night_loads_and_comes_back_with_the_menu() -> void:
	await _show_menu()
	Audio.advance(FADE_IN_S)
	await _push(NIGHT)
	Audio.advance(FADE_OUT_S)
	assert_bool(MenuAmbience.is_playing()).is_false()
	for id in MenuAmbience.BEDS:
		assert_bool(Audio.is_bed_running(id)).override_failure_message(id).is_false()
	# Leaving the night at once: its own beds are still fading out and hold their players.
	UIRouter.pop()
	await UIRouter.idle
	await await_idle_frame()
	assert_bool(MenuAmbience.is_playing()).is_true()


func test_the_ambience_slider_is_the_beds_volume_and_zero_is_silence() -> void:
	await _show_menu()
	var bus := AudioServer.get_bus_index(&"Ambience")
	Settings.set_value(SettingsService.VOLUME_AMBIENCE, 0)
	assert_bool(AudioServer.is_bus_mute(bus)).is_true()
	Settings.set_value(SettingsService.VOLUME_AMBIENCE, 80)
	assert_bool(AudioServer.is_bus_mute(bus)).is_false()
	assert_float(AudioServer.get_bus_volume_db(bus)).is_equal_approx(linear_to_db(0.8), 0.01)


func test_the_signs_flicker_makes_no_sound() -> void:
	var sign_node := NeonSign.new()
	add_child(sign_node)
	await await_idle_frame()
	var before := Audio.started
	# Six failures of the tube (4.7 s each) and the whole ignition, a frame at a time.
	for _i in int(NeonSign.FAIL_PERIOD * 6.0 / 0.05):
		sign_node._process(0.05)
	assert_int(Audio.started).is_equal(before)
	sign_node.free()
