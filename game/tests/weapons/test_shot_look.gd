extends GdUnitTestSuite
## What a shot looks like to the player: hitscan weapons show a flash and an impact and never a
## visible bullet (no tracer streak); only a weapon whose def asks for one draws a streak; the
## flare gun, the one launcher, still spawns its projectile.

const SHOOTER := WeaponsFixture.SHOOTER
const BODY := Vector3(0, 1.1, 0)
const MUZZLE := Vector3(0.0, 1.5, 4.0)
const NEAR_END := Vector3(0.0, 1.0, -2.0)

var _effects: ShotEffects


func before_test() -> void:
	_effects = auto_free(ShotEffects.new())
	add_child(_effects)


func _def(id: StringName) -> WeaponDef:
	return WeaponCatalog.get_def(id)


## A server with `id` in the player's hands and a zombie at the origin, one shot taken at it;
## returns the events the shot caused.
func _shot_events(id: StringName) -> Array[Dictionary]:
	var server := WeaponsFixture.make_server()
	server.apply(CombatAction.give_weapon(1, id))
	WeaponsFixture.step(server, {1: Vector3.ZERO}, 2)
	return server.apply(WeaponsFixture.fire_at(1, 1, SHOOTER, BODY, server.now))


func _view() -> NightView:
	var view: NightView = auto_free(NightView.new())
	add_child(view)
	view.setup(ClientState.new(), auto_free(Camera3D.new()))
	return view


func test_no_shipped_weapon_draws_a_tracer_by_default() -> void:
	for def in WeaponCatalog.all():
		assert_bool(def.tracer).override_failure_message("%s draws a tracer" % def.id).is_false()


func test_the_hitscan_weapons_are_the_guns_and_the_flare_gun_is_the_projectile() -> void:
	for id: StringName in [&"pistol", &"smg", &"shotgun", &"rifle"]:
		assert_bool(_def(id).is_hitscan()).override_failure_message(String(id)).is_true()
	assert_bool(_def(&"flare_gun").is_projectile()).is_true()


func test_a_hitscan_shot_reaches_the_screen_with_a_flash_and_an_impact_but_no_tracer() -> void:
	for id: StringName in [&"pistol", &"smg", &"shotgun", &"rifle"]:
		var view := _view()
		var fired := WeaponsFixture.of(_shot_events(id), &"shot_fired")[0]
		var range_m := _def(id).max_range
		var landed := 0
		for end: Vector3 in fired["ends"]:
			if fired["muzzle"].distance_to(end) < range_m - ShotEffects.RANGE_SLACK:
				landed += 1
		# A puff on every zombie hit, and a spark, puff and mark where a pellet met something else.
		var flesh: Array = fired["flesh"]
		var walls := 0
		for end: Vector3 in fired["ends"]:
			var on_zombie := flesh.any(func(p: Vector3) -> bool: return p.distance_to(end) < 0.02)
			if (
				fired["muzzle"].distance_to(end) < range_m - ShotEffects.RANGE_SLACK
				and not on_zombie
			):
				walls += 1
		view._on_event(fired)
		assert_int(view.effects.tracers_drawn).override_failure_message(String(id)).is_equal(0)
		var expected := mini(flesh.size() + walls, ImpactFx.MAX_ACTIVE)
		assert_int(view.effects.impacts.active_count()).is_equal(expected)
		if id != &"rifle":  # the rifle's round passes through the zombie and flies on
			assert_int(landed).override_failure_message("%s hit nothing" % id).is_greater(0)


func test_a_miss_into_the_open_still_shows_no_streak() -> void:
	var server := WeaponsFixture.make_server()
	server.apply(CombatAction.give_weapon(1, &"rifle"))
	WeaponsFixture.step(server, {1: Vector3.ZERO}, 2)
	var events := server.apply(
		WeaponsFixture.fire_at(1, 1, SHOOTER, Vector3(8.0, 1.1, 0.0), server.now)
	)
	var view := _view()
	view._on_event(WeaponsFixture.of(events, &"shot_fired")[0])
	assert_int(view.effects.tracers_drawn).is_equal(0)


func test_the_flare_gun_still_spawns_its_projectile_and_the_view_draws_no_streak() -> void:
	var events := _shot_events(&"flare_gun")
	assert_array(WeaponsFixture.of(events, &"projectile_spawned")).has_size(1)
	var view := _view()
	view._on_event(WeaponsFixture.of(events, &"shot_fired")[0])
	assert_int(view.effects.tracers_drawn).is_equal(0)


func test_a_weapon_that_asks_for_a_tracer_gets_one_streak_per_pellet() -> void:
	var def := _def(&"shotgun").duplicate() as WeaponDef
	def.tracer = true
	_effects.shot(def, MUZZLE, [NEAR_END, NEAR_END + Vector3.RIGHT, NEAR_END + Vector3.LEFT])
	assert_int(_effects.tracers_drawn).is_equal(3)


func test_a_projectile_weapon_draws_no_impact_from_the_shot_itself() -> void:
	_effects.shot(_def(&"flare_gun"), MUZZLE, [])
	# Only the flash: the flare's body and its burst come from the flight.
	assert_int(_effects.impacts.active_count()).is_equal(0)
	assert_int(_effects.tracers_drawn).is_equal(0)


func test_a_shot_that_flew_its_whole_range_leaves_no_impact() -> void:
	var def := _def(&"rifle")
	_effects.shot(def, MUZZLE, [MUZZLE + Vector3.FORWARD * def.max_range])
	assert_int(_effects.impacts.active_count()).is_equal(0)


func test_a_swing_shows_no_streak() -> void:
	var events := _shot_events(&"crowbar")
	var view := _view()
	view._on_event(WeaponsFixture.of(events, &"shot_fired")[0])
	assert_int(view.effects.tracers_drawn).is_equal(0)
