extends GdUnitTestSuite
## The ray gun (#788): a fast bolt that flies on the server's step and bursts on the first zombie it
## meets, hurting that one and every zombie round the burst by less the farther it stands, and the
## shooter not at all.

const SHOOTER := WeaponsFixture.SHOOTER
const BODY := Vector3(0, 1.1, 0)
const SPAWNED := 3
const FLIGHT_STEPS := 90

var _rules: GameRules
var _server: CombatServer
var _def: WeaponDef
var _places := {}


func before_test() -> void:
	_def = WeaponCatalog.get_def(&"ray_gun")
	_rules = RulesFixture.make_rules(1)
	# Zombies that one burst does not kill, so every hurt one is still there to be read.
	_rules.tuning.rounds.health_base = 1000.0
	_server = WeaponsFixture.make_server(_rules)
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, WeaponsFixture.SPAWN_SECONDS * SPAWNED * 2.0)
	_server.apply(CombatAction.give_weapon(1, &"ray_gun"))
	assert_int(_rules.zombie_ids().size()).is_greater_equal(SPAWNED)


func _step(count: int = 1) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for _i in count:
		events.append_array(_server.apply(CombatAction.targets(WeaponsFixture.list_of(_places))))
		events.append_array(_server.apply(CombatAction.tick(WeaponsFixture.STEP)))
	return events


## Fires at the zombie in front of the shooter and runs until the bolt bursts.
func _shoot() -> Array[Dictionary]:
	_step(2)
	var events := _server.apply(WeaponsFixture.fire_at(1, 1, SHOOTER, BODY, _server.now))
	events.append_array(_step(FLIGHT_STEPS))
	return events


func test_the_bolt_flies_and_bursts_on_the_first_zombie_it_meets() -> void:
	_places = {1: Vector3.ZERO, 2: Vector3(0, 0, -4)}
	var events := _shoot()
	assert_array(WeaponsFixture.of(events, &"projectile_spawned")).has_size(1)
	var burst := WeaponsFixture.of(events, &"projectile_burst")
	assert_array(burst).has_size(1)
	assert_str(String(burst[0]["kind"])).is_equal("target")
	assert_float(burst[0]["radius"]).is_equal(_def.splash_radius)
	assert_int(_server.projectiles_in_flight()).is_equal(0)
	# It stopped on the first zombie: the one behind it, out of the splash, was not touched.
	var hurt := _hurt(events)
	assert_bool(hurt.has(1)).is_true()
	assert_bool(hurt.has(2)).is_false()


func test_the_bolt_is_fast_and_does_not_fall() -> void:
	assert_float(_def.projectile_speed).is_greater(
		WeaponCatalog.get_def(&"flare_gun").projectile_speed
	)
	assert_float(_def.projectile_gravity).is_equal(0.0)


func test_a_zombie_beside_the_burst_takes_splash_that_falls_with_the_distance() -> void:
	_places = {1: Vector3.ZERO, 2: Vector3(1.2, 0, 0), 3: Vector3(2.4, 0, 0)}
	var events := _shoot()
	var point: Vector3 = WeaponsFixture.of(events, &"projectile_burst")[0]["point"]
	var hurt := _hurt(events)
	# The direct hit takes the bolt's damage, not the splash's.
	assert_float(hurt[1]["damage"]).is_equal(DamageModel.damage(_def, 0.0, hurt[1]["zone"]))
	for id in [2, 3]:
		var reach := Hitbox.distance_from(point, _places[id], 0.0)
		assert_bool(hurt.has(id)).override_failure_message("zombie %d in the splash" % id).is_true()
		assert_float(hurt[id]["damage"]).is_equal_approx(DamageModel.splash(_def, reach), 0.001)
	assert_float(hurt[2]["damage"]).is_greater(hurt[3]["damage"])
	assert_float(hurt[3]["damage"]).is_greater(0.0)


func test_a_zombie_past_the_radius_takes_nothing() -> void:
	_places = {1: Vector3.ZERO, 2: Vector3(_def.splash_radius + 2.0, 0, 0)}
	var hurt := _hurt(_shoot())
	assert_bool(hurt.has(1)).is_true()
	assert_bool(hurt.has(2)).is_false()


func test_the_splash_slides_from_full_to_its_least_at_the_radius() -> void:
	assert_float(DamageModel.splash(_def, 0.0)).is_equal(_def.splash_damage)
	assert_float(DamageModel.splash(_def, _def.splash_radius)).is_equal_approx(
		_def.splash_damage * _def.splash_min_fraction, 0.001
	)
	assert_float(DamageModel.splash(_def, _def.splash_radius + 0.01)).is_equal(0.0)
	var half := DamageModel.splash(_def, _def.splash_radius / 2.0)
	assert_float(half).is_between(_def.splash_damage * _def.splash_min_fraction, _def.splash_damage)


func test_the_shooter_is_not_hurt_by_the_splash() -> void:
	# A burst on a zombie at the shooter's feet: the rules' health of the shooter does not move.
	_places = {1: Vector3(0, 0, 7.0)}
	var health := _rules.health_of(1)
	var events := _shoot()
	assert_array(WeaponsFixture.of(events, &"projectile_burst")).has_size(1)
	assert_float(_rules.health_of(1)).is_equal(health)


func test_a_re_cut_ray_gun_hits_and_splashes_harder() -> void:
	var spec := UpgradeTuning.shipped()
	var cut := spec.profile_of(&"ray_gun")
	var re_cut := _def.upgraded(spec)
	assert_float(re_cut.damage).is_equal_approx(_def.damage * cut.damage_multiplier, 0.001)
	assert_float(re_cut.splash_damage).is_equal_approx(
		_def.splash_damage * cut.damage_multiplier, 0.001
	)
	assert_bool(re_cut.has_bolt_colours()).is_true()
	assert_bool(spec.allows(&"ray_gun")).is_true()


## The damage each zombie took from the events, by id.
func _hurt(events: Array[Dictionary]) -> Dictionary:
	var by_id := {}
	for event in WeaponsFixture.of(events, &"damage_dealt"):
		by_id[event["target_id"]] = event
	return by_id
