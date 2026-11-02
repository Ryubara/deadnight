extends GdUnitTestSuite
## A night's challenges reach the HUD's prompt through the real path: the rules' events go to the
## client state, the session counts them, the link turns each advance into a HUD event, and the
## card shows what moved. The player's setting changes what shows, and the two sounds exist.

const DAY := 20401
const SETTINGS_PATH := "user://test_challenge_link_settings.cfg"

var _hud: Hud
var _state: ClientState
var _session: ChallengeSession
var _link: ChallengeHudLink
var _settings: QuietSettings


func before_test() -> void:
	UIMotion.reduced = false
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	_hud = HudFixture.make(host).hud
	var board := ChallengeBoard.open(
		ChallengeFixture.save_path("link"),
		ChallengeFixture.clock_on(DAY),
		ChallengeFixture.small_catalog()
	)
	_session = ChallengeSession.new(board)
	_state = ClientState.new()
	_session.attach(_state)
	_settings = QuietSettings.make(self, SETTINGS_PATH)
	_link = ChallengeHudLink.new(_session, _hud, _settings)


func after_test() -> void:
	_settings.free()
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


func _kills(count: int) -> void:
	var made := ChallengeFixture.night(1)
	_state.apply_events(made["events"])
	var rules: GameRules = made["rules"]
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.skip_break())
	var killed := 0
	while killed < count:
		_state.apply_events(rules.apply(RulesAction.tick(RulesFixture.STEP)))
		for zombie_id in rules.zombie_ids():
			if killed < count:
				killed += 1
				_state.apply_events(RulesFixture.kill(rules, 1, zombie_id, RulesAction.ZONE_BODY))


func _run(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		_hud.challenge.advance(0.05)
		left -= 0.05


func test_kills_in_a_night_show_the_quarter_mark_of_the_daily() -> void:
	_kills(2)
	_run(0.5)
	assert_bool(_hud.challenge.visible).is_true()
	assert_str(_hud.challenge.card.count.text).is_equal("2 / 8")
	assert_str(_hud.challenge.card.words.text).is_equal("Do kills 8")
	assert_that(_hud.challenge.card.holes()).is_equal(Vector2i(1, 4))


func test_a_kill_between_marks_shows_nothing_new() -> void:
	_kills(1)
	_run(1.0)
	assert_bool(_hud.challenge.visible).is_false()


func test_the_advance_event_the_hud_hears_is_plain_data() -> void:
	var heard: Array[Dictionary] = []
	_hud.state.event_applied.connect(
		func(event: Dictionary) -> void:
			if event["type"] == HudChallenge.EVENT:
				heard.append(event)
	)
	_kills(2)
	assert_int(heard.size()).is_greater(0)
	for event in heard:
		for value: Variant in event.values():
			assert_bool(value is Object).is_false()


func test_the_setting_decides_which_prompts_show() -> void:
	assert_int(_hud.challenge.mode).is_equal(HudChallenge.Mode.ALL)
	_settings.set_value(SettingsService.CHALLENGE_PROMPTS, 1)
	assert_int(_hud.challenge.mode).is_equal(HudChallenge.Mode.FINISHED_ONLY)
	_kills(2)
	_run(1.0)
	assert_bool(_hud.challenge.visible).is_false()
	_settings.set_value(SettingsService.CHALLENGE_PROMPTS, 2)
	assert_int(_hud.challenge.mode).is_equal(HudChallenge.Mode.OFF)
	_settings.set_value(SettingsService.CHALLENGE_PROMPTS, 0)
	assert_int(_hud.challenge.mode).is_equal(HudChallenge.Mode.ALL)


func test_the_setting_is_a_known_option_with_a_default_that_shows_everything() -> void:
	assert_int(SettingsService.DEFAULTS[SettingsService.CHALLENGE_PROMPTS]).is_equal(0)
	assert_object(SettingsService.RANGES[SettingsService.CHALLENGE_PROMPTS]).is_equal(Vector2(0, 2))


func test_both_cues_are_sounds_the_game_has() -> void:
	for id in [&"challenge_tick", &"challenge_done"]:
		var def := SoundCatalog.get_def(id)
		assert_object(def).is_not_null()
		(
			assert_bool(ResourceLoader.exists(def.path_for(1)))
			. override_failure_message("missing file for %s" % id)
			. is_true()
		)
