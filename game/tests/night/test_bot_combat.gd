# Bots in a fight (bots plan, phase 3), in the real lot with the real server: scenario 10 (a dry
# magazine with nothing in reserve falls back to the crowbar), 12 (the boss's telegraphed blow is
# stepped out of: no hit in 20 trials), 13 (a stampede of runners is met at a choke, not run from)
# and 14 (crawlers are aimed at low). The bands of the balance simulator are in `test_bot_bands.gd`,
# the grenades in `test_bot_grenades.gd`. Ticks are run by hand.
extends GdUnitTestSuite

const STEP := Night.STEP
const TICKS_PER_SECOND := 60
const AVENUE := Vector3(0.0, 0.0, -14.0)
## A bot that is pinned: it does not back off from the boss or anything else, does not walk to
## stay with the people and does not aim at the lamp, so the only way out of a blow is the dodge.
const TRIALS := 20
## Where the boss is put, in metres from the bot, and how fast it walks at the bot (m/s).
const BOSS_DISTANCE := 4.0
const BOSS_SPEED := 0.9
## The bot's health when nothing has touched it.
const FULL_HEALTH := 100.0
## The average player's accuracy (`SimSkill`) and a crawler's hit chance (`ZombieType.hit_chance`):
## the band of the hit rate against crawlers runs from their product to the accuracy, a tenth
## either side. Aimed over their backs, the bot would sit far under it.
const AVERAGE_ACCURACY := 0.65
const CRAWLER_HIT_CHANCE := 0.6


func _home() -> Vector3:
	return Autopilot.HOME


## A night with one bot at `at` (home by default) and one zombie to a round, past the first break.
func _lone(profile: BotProfile, bot_seed: int, at := Vector3.ZERO) -> SeatedNight:
	var night := await NightFixture.seat(self, 1, SeatedNight.one_a_round(), 5)
	night.stand_still = true
	night.seat(1, profile, bot_seed)
	night.server.rules.apply(RulesAction.skip_break())
	night.server.body_of(1).teleport(_home() + at + Vector3(0.0, 0.1, 0.0))
	night.run(5)
	return night


# --- Scenario 10 ---


func test_scenario_10_a_dry_magazine_with_no_reserve_falls_back_to_the_quick_melee() -> void:
	var night := await _lone(BotProfile.regular(), 31)
	var pistol := night.server.combat.state_of(1, &"house_pistol")
	pistol.ammo = 0
	pistol.reserve = 0
	# No melee weapon is carried (#411): the blow every player has is all the bot has left.
	assert_array(night.server.combat.carried(1)).contains_exactly([&"house_pistol"])
	var blows: Array[int] = []
	var kills: Array[int] = []
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"quick_melee" and event["shooter_id"] == 1:
			blows.append(night.server.tick_count)
		elif event["type"] == &"zombie_removed" and event["cause"] == &"killed":
			kills.append(1)
	var zombie := night.drop_zombie(_home() + AVENUE)
	assert_object(zombie).is_not_null()
	for _i in 30 * TICKS_PER_SECOND:
		night.tick()
		if not kills.is_empty():
			break
	assert_int(kills.size()).is_equal(1)
	# It struck with the pistol still in hand, and did not buy back to it: nothing in it.
	assert_array(blows).is_not_empty()
	assert_str(night.frame["players"][1]["weapon"]).is_equal("house_pistol")
	assert_int(night.server.combat.state_of(1, &"house_pistol").ammo).is_equal(0)
	night.on_event = Callable()
	night.dispose()


# --- Scenario 12 ---


## The headliner as the roster makes it, put `BOSS_DISTANCE` metres from the bot at `around` degrees
## off its view, walking at it.
func _put_the_boss(night: SeatedNight, around: float) -> ZombieBody:
	var heading := deg_to_rad(around)
	var at := _home() + Vector3(-sin(heading), 0.0, -cos(heading)) * BOSS_DISTANCE
	var boss := night.drop_zombie(at, BOSS_SPEED)
	var type := night.server.rules.tuning.roster.type_of(&"headliner")
	boss.profile = ZombieProfile.from_type(type, &"headliner", night.server.sim.tuning)
	boss.speed = BOSS_SPEED
	return boss


## One trial of the telegraph: a pinned bot with its trigger held, and a boss that comes to it and
## swings. Returns `{valid, hurt, gap}`: whether the swing ran to its blow (a swing a hit staggers
## is no trial), whether the blow hurt the bot, and the metres between them at the blow.
func _telegraph_trial(profile: BotProfile, bot_seed: int, around: float) -> Dictionary:
	profile.retreat_margin = 0.0
	profile.boss_keep = 0.0
	profile.follows = false
	profile.weak_spot_rate = 0.0
	var night := await _lone(profile, bot_seed)
	night.hold_fire = true
	var boss := _put_the_boss(night, around)
	var result := {"valid": false, "hurt": false, "gap": INF}
	for _i in 20 * TICKS_PER_SECOND:
		night.tick()
		if boss.mode == ZombieBody.Mode.STAGGER:
			break
		if boss.mode == ZombieBody.Mode.ATTACK and boss.struck:
			night.run(4)
			var here := night.server.body_of(1).global_position
			result["valid"] = true
			result["gap"] = Vector2(here.x - boss.position.x, here.z - boss.position.z).length()
			result["hurt"] = night.frame["players"][1]["health"] < FULL_HEALTH - 0.5
			break
	night.dispose()
	return result


func test_scenario_12_the_boss_telegraphed_blow_is_stepped_out_of_in_20_trials() -> void:
	# The two profiles that read every telegraph (the rookie reads none, so that four of them lose
	# the first boss night as often as the simulator's weak players: the test below).
	var skills: Array[Callable] = [BotProfile.regular, BotProfile.veteran]
	var angles := [-40.0, -20.0, 0.0, 20.0, 40.0]
	var valid := 0
	var hurt := 0
	var closest := INF
	var tries := 0
	while valid < TRIALS and tries < TRIALS * 3:
		var profile: BotProfile = skills[tries % skills.size()].call()
		var trial := await _telegraph_trial(profile, 100 + tries, angles[tries % angles.size()])
		tries += 1
		if not trial["valid"]:
			continue
		valid += 1
		hurt += 1 if trial["hurt"] else 0
		closest = minf(closest, trial["gap"])
	assert_int(valid).is_equal(TRIALS)
	assert_int(hurt).is_equal(0)
	# It was out of the blow's reach, with room to spare, when the blow came due.
	assert_float(closest).is_greater(BotDodge.REACH + BotDodge.SLACK)


func test_scenario_12_a_rookie_reads_no_telegraph_and_takes_every_blow() -> void:
	var hurt := 0
	var valid := 0
	var angles := [-40.0, -20.0, 0.0, 20.0, 40.0]
	for i in 15:
		var trial := await _telegraph_trial(BotProfile.rookie(), 300 + i, angles[i % angles.size()])
		if trial["valid"]:
			valid += 1
			hurt += 1 if trial["hurt"] else 0
	assert_int(valid).is_greater_equal(12)
	assert_int(hurt).is_equal(valid)


func test_scenario_12_control_a_bot_that_reacts_too_late_takes_the_blow() -> void:
	var hurt := 0
	for i in 3:
		var profile := BotProfile.regular()
		profile.reaction_seconds = 2.5
		var trial := await _telegraph_trial(profile, 200 + i, 0.0)
		assert_bool(trial["valid"]).is_true()
		hurt += 1 if trial["hurt"] else 0
	assert_int(hurt).is_greater_equal(2)


# --- The weak spot ---


func test_the_lens_is_where_the_hit_zones_put_it_and_is_seen_only_from_the_front() -> void:
	var boss := {
		"position": Vector3(0, 0, -8),
		"yaw": 0.0,
		"look": &"headliner",
		"mode": ZombieBody.Mode.CHASE
	}
	var eye := Vector3(0, BotLevel.EYE_HEIGHT, 0)
	var lens := BotMotor.weak_spot(boss, eye)
	# The same place the shot's hit zone is (`Hitbox.WEAK_ZONE`, sized by the boss's height).
	var zone: Dictionary = Hitbox.shapes(boss["position"], boss["yaw"], 1.45, true).back()
	assert_vector(lens).is_equal_approx(zone["a"], Vector3.ONE * 0.01)
	assert_float(zone["r"]).is_greater(0.2)
	# From behind it, or from its side, the lens is not in view.
	boss["yaw"] = PI
	assert_bool(BotMotor.weak_spot(boss, eye) == Vector3.INF).is_true()
	boss["yaw"] = PI / 2.0
	assert_bool(BotMotor.weak_spot(boss, eye) == Vector3.INF).is_true()


## Hits on the headliner by zone, from a pinned bot with a rifle that shoots it as it comes.
func _boss_shoot(weak_rate: float, off_the_lens := false) -> Dictionary:
	var profile := BotProfile.veteran()
	profile.weak_spot_rate = weak_rate
	profile.aims_off_weak_spot = off_the_lens
	profile.retreat_margin = 0.0
	profile.boss_keep = 0.0
	profile.follows = false
	var tuning := NightFixture.special_tuning(&"double_feature")
	tuning.specials.rounds[0].escort_fraction = 0.0
	tuning.health.max_health = 100000.0
	# A boss that outlasts the test, so the hits are many.
	tuning.roster.type_of(&"headliner").health_multiplier = 400.0
	var night := await NightFixture.seat(self, 1, tuning, 61)
	night.stand_still = true
	night.seat(1, profile, 61)
	night.server.rules.apply(RulesAction.grant_points(1, 100000))
	night.server.buy(1, &"weapon_rifle")
	night.start_round()
	night.server.body_of(1).teleport(_home() + Vector3(0.0, 0.1, 0.0))
	var boss: ZombieBody
	for _i in 600:
		night.tick()
		for zombie: ZombieBody in night.server.sim.zombies.values():
			if zombie.profile.boss:
				boss = zombie
		if boss != null:
			break
	assert_object(boss).is_not_null()
	boss.position = _home() + Vector3(0.0, 0.0, -12.0)
	boss.gate_id = &""
	boss.enter(ZombieBody.Mode.CHASE)
	var probe := CombatProbe.new().watch(night)
	for _i in 40 * TICKS_PER_SECOND:
		night.server.combat.weapon_of(1).reserve = 500
		night.tick()
		boss.speed = 0.3
	var zones := probe.zones.duplicate()
	probe.stop()
	night.dispose()
	return zones


func test_the_headliner_is_shot_in_the_lens_at_the_profiles_rate() -> void:
	var never := await _boss_shoot(0.0)
	var always := await _boss_shoot(1.0)
	# The lens sits on the belly, so a shot at the chest can catch it; aimed at, it takes most hits.
	assert_float(_share(never, &"weak")).is_less(0.4)
	assert_float(_share(always, &"weak")).is_greater(0.6)
	assert_float(_share(always, &"weak")).is_greater(_share(never, &"weak") + 0.3)


func test_a_bot_that_aims_off_the_lens_hits_it_only_when_it_means_to() -> void:
	var hips := await _boss_shoot(0.0, true)
	# In the soak a bot standing before the boss hit the lens in 6 of 10 hits aimed at the chest
	# (the lamp counts when the ray passes it, `Hitbox.WEAK_SLACK`); aimed at the hips, in 3 of 10.
	assert_int(hips.size()).is_greater(1)
	assert_float(_share(hips, &"weak")).is_less(0.3)
	assert_bool(BotProfile.rookie().aims_off_weak_spot).is_true()
	assert_bool(BotProfile.regular().aims_off_weak_spot).is_false()


static func _share(zones: Dictionary, zone: StringName) -> float:
	var total := 0
	for count: int in zones.values():
		total += count
	return float(zones.get(zone, 0)) / float(maxi(total, 1))


# --- Phase 1 under combat ---


func test_the_aim_and_fire_distributions_of_phase_1_hold_in_a_boss_fight() -> void:
	# Four bots of the three skills fight the boss night for 40 s; the view of each never turns faster
	# than its profile's cap in any 100 ms, every shot agrees with the view (the server refuses one
	# that does not: `fire_rejected`). The dead are staged in front of the bots (`stage_the_dead`):
	# left to walk the lot from its far spawn spots, they came within range only near the end of the
	# 40 s, by a path that changed a little from one run to the next, so the count of shots swung
	# from 130 to 3 on a slow machine (#596). The reaction floor in the real lot is scenario 1 in
	# `test_bot_night.gd`, which runs on this brain too.
	var tuning := NightFixture.special_tuning(&"double_feature")
	tuning.health.max_health = 100000.0
	var night := await NightFixture.seat(self, 4, tuning, 77)
	var profiles: Array[BotProfile] = [
		BotProfile.rookie(), BotProfile.regular(), BotProfile.veteran(), BotProfile.regular()
	]
	for i in 4:
		night.stand_still = true
		night.seat(i + 1, profiles[i], 77 + i)
	night.recording = true
	night.stage_the_dead = true
	night.gather()
	var rejected: Array[StringName] = []
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"fire_rejected":
			rejected.append(event.get("reason", &""))
	night.start_round()
	night.run(40 * TICKS_PER_SECOND)
	var views := {1: [], 2: [], 3: [], 4: []}
	var shots := 0
	for entry in night.recorded:
		var motion: Dictionary = entry["action"]["motion"]
		views[entry["player_id"]].append(
			Basis.from_euler(Vector3(motion["pitch"], motion["yaw"], 0.0)) * Vector3.FORWARD
		)
		shots += 1 if entry["action"]["fire"] else 0
	for i in 4:
		var cap := deg_to_rad(profiles[i].max_aim_speed) * 0.1
		var turned := 0.0
		var track: Array = views[i + 1]
		for t in range(6, track.size()):
			turned = maxf(turned, track[t - 6].angle_to(track[t]))
		assert_float(turned).is_less_equal(cap + 0.0001)
	assert_array(rejected).is_empty()
	assert_int(shots).is_greater(30)
	night.on_event = Callable()
	night.dispose()


# --- Scenario 13 ---


## A stampede in the real lot against a bot standing in the field, the stampede announced by its
## own name or (the control) under another that no bot has a stance for.
func _stampede(named: StringName, profile: BotProfile, seconds: float) -> Dictionary:
	var tuning := NightFixture.special_tuning(&"stampede")
	tuning.specials.rounds[0].id = named
	tuning.rounds.count_base = 14.0
	tuning.rounds.first_spawn_delay = 0.5
	tuning.rounds.speed_base = 2.0
	var night := await NightFixture.seat(self, 1, tuning, 9)
	night.stand_still = true
	night.seat(1, profile, 9)
	night.recording = true
	night.start_round()
	night.server.body_of(1).teleport(_home() + Vector3(4.0, 0.1, 0.0))
	var probe := CombatProbe.new().watch(night)
	var positions: Array[Vector3] = []
	for _i in int(seconds * TICKS_PER_SECOND):
		night.tick()
		probe.tick()
		positions.append(night.server.body_of(1).global_position)
	var sprints := 0
	for entry in night.recorded:
		if entry["action"]["motion"]["sprint"]:
			sprints += 1
	var stance := BotStance.new(night.level)
	var result := {
		"sprints": sprints,
		"kills": probe.kills,
		"positions": positions,
		"walls": stance.walls_about(positions.back()),
		"ticks": positions.size(),
	}
	probe.stop()
	night.dispose()
	return result


func test_scenario_13_runners_only_a_choke_is_held_and_the_bot_does_not_sprint_away() -> void:
	var profile := BotProfile.regular()
	profile.retreat_margin = 8.0
	var held := await _stampede(BotStance.STAMPEDE, profile, 60.0)
	assert_int(held["sprints"]).is_equal(0)
	assert_int(held["kills"]).is_greater(2)
	# It stands at a place with walls about it, and stays there once it has got there.
	assert_int(held["walls"]).is_greater_equal(BotStance.MIN_WALLS)
	var positions: Array = held["positions"]
	var settled: Vector3 = positions[positions.size() - 1]
	for i in range(10 * TICKS_PER_SECOND, positions.size()):
		var apart := Vector2(positions[i].x - settled.x, positions[i].z - settled.z).length()
		assert_float(apart).is_less(2.0)


func test_scenario_13_control_without_the_stance_the_same_bot_runs() -> void:
	var profile := BotProfile.regular()
	profile.retreat_margin = 8.0
	var loose := await _stampede(&"only_runner", profile, 60.0)
	assert_int(loose["sprints"]).is_greater(0)


# --- Scenario 14 ---


func test_scenario_14_crawlers_only_the_aim_is_low_and_the_hit_rate_is_in_the_band() -> void:
	var tuning := NightFixture.special_tuning(&"crawl_space")
	tuning.rounds.count_base = 80.0
	tuning.rounds.first_spawn_delay = 0.5
	tuning.rounds.speed_base = 3.0
	tuning.health.max_health = 100000.0
	var night := await NightFixture.seat(self, 1, tuning, 14)
	night.stand_still = true
	night.seat(1, BotProfile.regular(), 14)
	night.start_round()
	night.server.body_of(1).teleport(_home() + Vector3(0.0, 0.1, 0.0))
	var probe := CombatProbe.new().watch(night)
	var gaps: Array[float] = []
	for _i in 150 * TICKS_PER_SECOND:
		night.server.combat.weapon_of(1).reserve = 500
		night.tick()
		probe.tick()
		if probe.shots > gaps.size():
			gaps.append(probe.last_aim_gap)
	var rate := probe.hit_rate()
	assert_int(probe.shots).is_greater(20)
	# Lower than the aim at a walker's chest at the same range, by about what a crawler's height is:
	# 0.44 m lower, so 0.07 radians at 6 m. The mean is taken over every shot.
	assert_float(_mean(gaps)).is_less(-0.03)
	# A crawler's zones are its body on the ground, so it is no harder to hit than a walker (the type's
	# `hit_chance` of 0.6 sized an upright set that was never where it lay): the band is a walker's.
	assert_float(rate).is_between(AVERAGE_ACCURACY * CRAWLER_HIT_CHANCE - 0.1, 0.95)
	probe.stop()
	night.dispose()


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / float(maxi(values.size(), 1))
