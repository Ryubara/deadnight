extends GdUnitTestSuite
## The developer's entry scene (`dev/play_night.tscn`) starts a night with no menu and applies
## the options set in its inspector.

const SCENE := "res://dev/play_night.tscn"
## Physics frames a started night is given before a test gives up on it.
const START_FRAMES := 1800
## Ticks for what the server did on its own to reach the client (an answer rides the next tick).
const CLIENT_TICKS := 2

var _play: PlayNight


func after_test() -> void:
	if _play != null and is_instance_valid(_play) and _play.night != null:
		await NightFixture.settle_bake(_play.night)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The scene with `options` set as the inspector would, added to the tree and started.
func _start(options: Dictionary = {}) -> PlayNight:
	_play = (load(SCENE) as PackedScene).instantiate() as PlayNight
	_play.warm_up = false
	_play.autopilot = true
	for key: String in options:
		_play.set(key, options[key])
	add_child(_play)
	for _i in START_FRAMES:
		if _play.night != null and _play.night.running:
			break
		await get_tree().physics_frame
	return _play


func test_run_with_no_options_it_starts_round_one_at_once() -> void:
	var play := await _start()
	NightFixture.run(play.night, CLIENT_TICKS)
	assert_bool(play.night.running).is_true()
	assert_int(play.night.state.round_number()).is_equal(1)
	assert_int(play.night.state.phase()).is_equal(GameRules.Phase.ACTIVE)
	assert_int(play.night.server.rules.points_of(Night.PLAYER_ID)).is_equal(
		RulesFixture.tuning().economy.start_points
	)


func test_a_person_plays_it_by_default_with_the_real_controls() -> void:
	var play := await _start({"autopilot": false})
	var player := play.night.player()
	player.capture_mouse = false
	player.local_input = false
	assert_bool(play.night.running).is_true()
	assert_int(play.night.mode).is_equal(Night.Mode.HUMAN)
	assert_object(player).is_not_null()


func test_without_skipping_the_intro_the_night_waits_in_its_first_break() -> void:
	var play := await _start({"skip_intro": false})
	NightFixture.run(play.night, CLIENT_TICKS)
	assert_int(play.night.state.phase()).is_equal(GameRules.Phase.BREAK)
	assert_int(play.night.state.round_number()).is_equal(0)


func test_a_later_round_starts_with_that_rounds_zombies() -> void:
	var play := await _start({"start_round": 7})
	NightFixture.run(play.night, CLIENT_TICKS)
	assert_int(play.night.state.round_number()).is_equal(7)
	assert_int(play.hud.state.round_number).is_equal(7)
	assert_int(play.night.state.phase()).is_equal(GameRules.Phase.ACTIVE)
	assert_int(play.night.server.rules.zombies_remaining()).is_equal(RulesFixture.round_count(7))


func test_starting_points_replace_the_tunings_without_editing_the_file() -> void:
	var shipped: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH)
	var before := shipped.economy.start_points
	var play := await _start({"starting_points": 4321})
	assert_int(play.night.server.rules.points_of(Night.PLAYER_ID)).is_equal(4321)
	assert_int(shipped.economy.start_points).is_equal(before)


func test_another_tuning_table_is_the_one_played() -> void:
	var table := RulesFixture.tuning()
	table.economy.start_points = 777
	var play := await _start({"rules_tuning": table})
	assert_int(play.night.server.rules.points_of(Night.PLAYER_ID)).is_equal(777)


func test_god_mode_tops_health_up_after_a_blow() -> void:
	var play := await _start({"god_mode": true})
	var rules := play.night.server.rules
	rules.apply(RulesAction.blow(Night.PLAYER_ID, 60.0))
	assert_float(rules.health_of(Night.PLAYER_ID)).is_less(rules.max_health_of(Night.PLAYER_ID))
	play.night.tick()
	assert_float(rules.health_of(Night.PLAYER_ID)).is_equal(rules.max_health_of(Night.PLAYER_ID))


func test_without_god_mode_a_blow_stays() -> void:
	var play := await _start()
	var rules := play.night.server.rules
	rules.apply(RulesAction.blow(Night.PLAYER_ID, 60.0))
	play.night.tick()
	assert_float(rules.health_of(Night.PLAYER_ID)).is_less(rules.max_health_of(Night.PLAYER_ID))


func test_infinite_ammo_refills_every_carried_gun() -> void:
	var play := await _start({"infinite_ammo": true})
	var gun := play.night.server.combat.state_of(Night.PLAYER_ID, &"pistol")
	gun.ammo = 0
	gun.reserve = 0
	play.night.tick()
	assert_int(gun.ammo).is_equal(gun.def.magazine_size)
	assert_int(gun.reserve).is_equal(gun.def.reserve_max)
