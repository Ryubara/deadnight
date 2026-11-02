extends GdUnitTestSuite
## The quick melee on the server (#411): one blow with whatever is in hand, swept like a melee
## weapon's with its own numbers and its own cooldown, hurting a zombie in reach; the bat and the
## fire axe hit harder than it, so a slot spent on them is worth it.

const CHEST := Vector3(0, 1.1, 0)
const AHEAD := Vector3(0, 0, -1)
const REACH := 1.2
## Every kind of weapon the blow has to work with: the guns, the bat and the axe.
const HELD: Array[StringName] = [&"pistol", &"rifle", &"shotgun", &"baseball_bat", &"fire_axe"]

var _rules: GameRules
var _log: RulesFixture
var _server: CombatServer
var _zombie: int
var _quick: WeaponDef


func before_test() -> void:
	_quick = WeaponCatalog.quick_melee()
	_rules = RulesFixture.make_rules(1)
	_log = RulesFixture.record(_rules)
	_server = WeaponsFixture.make_server(_rules)
	RulesFixture.into_round_one(_rules)
	RulesFixture.run(_rules, 2.0)
	_zombie = _log.spawned_ids()[0]
	_stand(2)


## The zombie stands `REACH` metres ahead of the chest for `steps` steps.
func _stand(steps: int, at: Vector3 = Vector3(0, 0, -REACH)) -> void:
	WeaponsFixture.step(_server, {_zombie: at}, steps)


func _blow(seq: int = 1) -> Array[Dictionary]:
	return _server.apply(CombatAction.quick_melee(1, seq, CHEST, AHEAD, CHEST, _server.now))


func test_the_blow_hurts_a_zombie_in_reach_whatever_is_in_hand() -> void:
	for id in HELD:
		# A fresh night for each, so the zombie is whole every time.
		before_test()
		_server.apply(CombatAction.give_weapon(1, id, id))
		var state := _server.weapon_of(1)
		var ammo := state.ammo
		var reserve := state.reserve
		var events := _blow()
		var hurt := WeaponsFixture.of(events, &"damage_dealt")
		(
			assert_array(hurt)
			. override_failure_message("the blow with the %s did not hurt the zombie" % id)
			. has_size(1)
		)
		assert_float(hurt[0]["damage"]).is_equal(_quick.damage)
		assert_bool(hurt[0]["melee"]).is_true()
		# The weapon in hand is untouched: its rounds are not spent and nothing was fired.
		assert_array(WeaponsFixture.of(events, &"shot_fired")).is_empty()
		assert_int(state.ammo).is_equal(ammo)
		assert_int(state.reserve).is_equal(reserve)


func test_the_blow_needs_no_weapon_at_all() -> void:
	var events := _server.apply(CombatAction.quick_melee(2, 1, CHEST, AHEAD, CHEST, _server.now))
	assert_array(WeaponsFixture.of(events, &"quick_melee")).has_size(1)


func test_it_says_where_the_blow_reached_and_what_it_struck() -> void:
	var swung := WeaponsFixture.of(_blow(), &"quick_melee")[0]
	assert_int(swung["shooter_id"]).is_equal(1)
	assert_array(swung["flesh"]).has_size(1)
	var reach: Vector3 = swung["ends"][0]
	assert_float(reach.distance_to(CHEST)).is_equal_approx(_quick.melee_range, 0.001)


func test_a_zombie_out_of_reach_is_not_hurt() -> void:
	_stand(2, Vector3(0, 0, -(_quick.melee_range + 1.0)))
	var events := _blow()
	assert_array(WeaponsFixture.of(events, &"quick_melee")).has_size(1)
	assert_array(WeaponsFixture.of(events, &"damage_dealt")).is_empty()


func test_a_second_press_inside_the_cooldown_is_refused_and_one_after_it_lands() -> void:
	_blow(1)
	var early := _blow(2)
	assert_array(WeaponsFixture.of(early, &"damage_dealt")).is_empty()
	var refused := WeaponsFixture.of(early, &"fire_rejected")
	assert_array(refused).has_size(1)
	assert_str(String(refused[0]["reason"])).is_equal("cooldown")
	# Almost, but not quite: the wait is the definition's interval.
	_stand(ceili(_quick.fire_interval * 60.0) - 3)
	assert_array(WeaponsFixture.of(_blow(3), &"quick_melee")).is_empty()
	_stand(5)
	assert_array(WeaponsFixture.of(_blow(4), &"quick_melee")).has_size(1)


func test_the_cooldown_is_each_players_own_and_not_the_weapons() -> void:
	_server.apply(CombatAction.give_weapon(1, &"pistol"))
	_server.apply(CombatAction.give_weapon(2, &"pistol"))
	_blow(1)
	var other := _server.apply(CombatAction.quick_melee(2, 1, CHEST, AHEAD, CHEST, _server.now))
	assert_array(WeaponsFixture.of(other, &"quick_melee")).has_size(1)
	# The pistol in the same hand fires at once: the blow did not start its cooldown.
	var shot := _server.apply(
		WeaponsFixture.fire_at(1, 1, CHEST, Vector3(0, 1.1, -REACH), _server.now)
	)
	assert_array(WeaponsFixture.of(shot, &"shot_fired")).has_size(1)


func test_two_blows_kill_a_round_one_zombie_and_pay_the_melee_price() -> void:
	var before := _rules.points_of(1)
	_blow(1)
	_stand(ceili(_quick.fire_interval * 60.0) + 2)
	var events := _blow(2)
	assert_array(WeaponsFixture.of(events, &"target_killed")).has_size(1)
	assert_int(_rules.points_of(1) - before).is_equal(4 + 130)


func test_a_bad_aim_is_refused() -> void:
	var events := _server.apply(CombatAction.quick_melee(1, 1, CHEST, Vector3.ZERO, CHEST, 0.0))
	assert_array(WeaponsFixture.of(events, &"quick_melee")).is_empty()
	assert_str(String(WeaponsFixture.of(events, &"fire_rejected")[0]["reason"])).is_equal("bad_aim")


func test_the_bat_and_the_axe_beat_the_quick_melee_per_blow_and_per_second() -> void:
	var rate := _quick.damage / _quick.fire_interval
	for id in [&"baseball_bat", &"fire_axe"]:
		var strong := WeaponCatalog.get_def(id)
		(
			assert_float(strong.damage / strong.fire_interval)
			. override_failure_message("the %s is not worth a slot over the quick melee" % id)
			. is_greater(rate * 1.5)
		)
	assert_float(WeaponCatalog.get_def(&"fire_axe").damage).is_greater(_quick.damage * 2.0)
	assert_int(WeaponCatalog.get_def(&"baseball_bat").melee_max_targets).is_greater(
		_quick.melee_max_targets
	)


func test_it_is_not_a_weapon_anyone_can_carry_or_buy() -> void:
	assert_array(WeaponCatalog.IDS).not_contains([WeaponCatalog.QUICK_MELEE])
	assert_bool(_quick.is_melee()).is_true()
