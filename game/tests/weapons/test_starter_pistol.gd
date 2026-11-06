extends GdUnitTestSuite
## The start weapon is the house pistol (#898) and it takes many shots to kill a walker: the
## maintainer's bar was "at least 3 shots to the head on round 1, 7 to the body, about 8 with leg
## shots only", and the revolver (24 a hit, head x2.5 = 60 on a 50 health walker) one-tapped
## rounds 1 and 2. The table below is the shots to kill per zone per round, through the real
## damage path (`DamageModel`, the rules' walker health), and the end-to-end tests fire the real
## command at a round-one walker and count the shots.

const SHOOTER := WeaponsFixture.SHOOTER
## Rounds the table is held for, and the shots to kill (head, body, limb) a walker takes in each.
## Health is the shipped curve: 50, 58, 82, 142.6 (`RoundTuning.health_for_round`).
const SHOTS := {
	1: [3, 7, 8],
	2: [3, 8, 9],
	5: [5, 11, 13],
	10: [8, 18, 21],
}
const AIM := {
	&"head": Vector3(0, 1.62, 0),
	&"body": Vector3(0, 1.1, 0),
	&"limb": Vector3(0.12, 0.4, 0),
}


## Shots of `def` it takes to empty `health` with hits on `zone` at point blank.
static func shots_to_kill(def: WeaponDef, zone: StringName, health: float) -> int:
	var left := health
	var shots := 0
	while left > 0.0 and shots < 1000:
		left -= DamageModel.damage(def, 0.0, zone)
		shots += 1
	return shots


func test_the_start_weapon_is_the_house_pistol_in_hand_and_in_the_rules() -> void:
	assert_str(WeaponCatalog.START_WEAPON).is_equal("house_pistol")
	assert_array(RulesFixture.start_weapons()).contains_exactly([&"weapon_house_pistol"])
	assert_bool(&"house_pistol" in WeaponCatalog.IDS).is_true()
	assert_str(WeaponCatalog.get_def(&"house_pistol").display_name).is_equal("House Pistol")


func test_the_house_pistol_is_a_light_semi_automatic_9_mm() -> void:
	var def := WeaponCatalog.get_def(&"house_pistol")
	assert_bool(def.is_hitscan()).is_true()
	assert_bool(def.automatic).is_false()
	assert_float(def.damage).is_equal(8.0)
	assert_float(def.zone_multiplier(&"head")).is_equal(2.5)
	assert_float(def.zone_multiplier(&"body")).is_equal(1.0)
	assert_float(def.zone_multiplier(&"limb")).is_equal(0.85)
	assert_int(def.magazine_size).is_equal(15)
	# Lighter than the revolver in every number that makes a hit.
	var revolver := WeaponCatalog.get_def(&"pistol")
	assert_float(def.damage).is_less(revolver.damage)
	assert_float(def.shake_trauma).is_less(revolver.shake_trauma)


func test_the_shots_to_kill_a_walker_per_zone_and_round() -> void:
	var def := WeaponCatalog.get_def(&"house_pistol")
	for round_number: int in SHOTS:
		var health := RulesFixture.round_health(round_number)
		var want: Array = SHOTS[round_number]
		var got := [
			shots_to_kill(def, &"head", health),
			shots_to_kill(def, &"body", health),
			shots_to_kill(def, &"limb", health),
		]
		(
			assert_array(got)
			. override_failure_message(
				(
					"round %d (%.1f health): head, body, limb shots %s, wanted %s"
					% [round_number, health, got, want]
				)
			)
			. is_equal(want)
		)


func test_round_one_is_the_maintainers_bar() -> void:
	var def := WeaponCatalog.get_def(&"house_pistol")
	var health := RulesFixture.round_health(1)
	assert_int(shots_to_kill(def, &"head", health)).is_greater_equal(3)
	assert_int(shots_to_kill(def, &"body", health)).is_equal(7)
	# Legs only: "about 8".
	assert_int(shots_to_kill(def, &"limb", health)).is_equal(8)


func test_no_start_weapon_hit_kills_a_walker_of_rounds_one_to_two_outright() -> void:
	# The revolver's cause (#898): 24 x 2.5 = 60 was over round 1's 50 and round 2's 58 health.
	for id in [&"house_pistol", &"pistol"]:
		var def := WeaponCatalog.get_def(id)
		for round_number in [1, 2]:
			var head := DamageModel.damage(def, 0.0, &"head")
			(
				assert_float(head)
				. override_failure_message(
					"%s head hit %s kills a round %d walker" % [id, head, round_number]
				)
				. is_less(RulesFixture.round_health(round_number))
			)


func test_the_revolver_takes_two_head_shots_on_rounds_one_and_two() -> void:
	var def := WeaponCatalog.get_def(&"pistol")
	for round_number in [1, 2]:
		assert_int(shots_to_kill(def, &"head", RulesFixture.round_health(round_number))).is_equal(2)
	# 28 a hit since the audit of #972 (the revolver was worth less than the free blow): two body shots
	# on round 1, and the head's x1.75 = 49 is still under round 1's 50.
	assert_int(shots_to_kill(def, &"body", RulesFixture.round_health(1))).is_equal(2)


## A round-one walker (health of `round_number`), one pistol shot a fire interval until it dies;
## returns the shots. The cone is closed for the count (a missed shot is not a shot to kill).
func _shots_through_the_server(id: StringName, zone: StringName, round_number: int) -> int:
	var rules := RulesFixture.make_rules(1)
	var seen := RulesFixture.record(rules)
	var defs: Array[WeaponDef] = []
	for def in WeaponsFixture.all_defs():
		var copy := def.duplicate() as WeaponDef
		copy.spread_deg = 0.0
		defs.append(copy)
	var server := CombatServer.new(defs, rules, Callable(), WeaponsFixture.SEED)
	server.apply(CombatAction.give_weapon(1, id))
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.skip_break())
	rules.round_number = round_number
	RulesFixture.run(rules, 2.0)
	var zombie := seen.spawned_ids()[0]
	WeaponsFixture.step(server, {zombie: Vector3.ZERO}, 2)
	var fired := 0
	while server.is_target_alive(zombie) and fired < 60:
		fired += 1
		server.apply(WeaponsFixture.fire_at(1, fired, SHOOTER, AIM[zone], server.now))
		WeaponsFixture.step(server, {zombie: Vector3.ZERO}, 20)
	return fired


func test_the_real_command_kills_a_round_one_walker_in_the_wanted_shots() -> void:
	var want: Array = SHOTS[1]
	assert_int(_shots_through_the_server(&"house_pistol", &"head", 1)).is_equal(want[0])
	assert_int(_shots_through_the_server(&"house_pistol", &"body", 1)).is_equal(want[1])
	assert_int(_shots_through_the_server(&"house_pistol", &"limb", 1)).is_equal(want[2])


func test_the_real_command_also_holds_on_later_rounds() -> void:
	for round_number: int in [2, 5, 10]:
		var want: Array = SHOTS[round_number]
		assert_int(_shots_through_the_server(&"house_pistol", &"head", round_number)).is_equal(
			want[0]
		)
		# A round-ten body needs 18 shots, more than a magazine: the table covers it above.
		if want[1] <= WeaponCatalog.get_def(&"house_pistol").magazine_size:
			assert_int(_shots_through_the_server(&"house_pistol", &"body", round_number)).is_equal(
				want[1]
			)


func test_the_revolver_does_not_one_tap_a_walker_through_the_real_command() -> void:
	for round_number in [1, 2]:
		var head := _shots_through_the_server(&"pistol", &"head", round_number)
		(
			assert_int(head)
			. override_failure_message("revolver head, round %d" % round_number)
			. is_equal(2)
		)
