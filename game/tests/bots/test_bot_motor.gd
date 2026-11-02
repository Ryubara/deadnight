# The bot's aim (bots plan, phase 1): a reaction delay with a floor, a turn that never beats the
# profile's cap, a shot that always goes where the view points, a trigger that waits for the aim,
# and a seeded stream so the same seed makes the same shots. Pure data on a `BotRig`: the zombies
# are moved by hand, a tick is a step of the night, nothing waits on the clock.
extends GdUnitTestSuite

const STEP := Night.STEP
## Contacts per profile (three profiles: a thousand and two in all).
const CONTACTS := 334
## Ticks a contact is given to be shot at before the test calls it missed.
const GIVE_UP := 300
## Ticks the zombie is gone before the next one comes, so the bot has let go of the last.
const GAP := 10
## 100 milliseconds in ticks.
const WINDOW := 6
## The floor of the first shot after the first clear ray, in ticks: 0.20 s and one tick.
const FLOOR_TICKS := 13

var _profiles: Array[BotProfile] = []
## The long run of contacts for each profile (title to result), made once for the suite.
var _runs: Dictionary = {}


func before() -> void:
	_profiles = [BotProfile.rookie(), BotProfile.regular(), BotProfile.veteran()]
	for profile in _profiles:
		_runs[profile.title] = _contacts(profile, 7, CONTACTS)


func after() -> void:
	_runs.clear()


## One long run of contacts for `profile`: each zombie appears in front of the view, the bot is
## left to shoot it, and the zombie goes. Returns `{latencies, turned, missed, errors}`: ticks from
## appearing to the first shot, the largest angle (radians) the view turned in any 100 ms, how many
## were never shot, and the view's error in degrees at each shot.
func _contacts(profile: BotProfile, bot_seed: int, count: int, hashing := false) -> Dictionary:
	var rig := BotRig.new(profile, bot_seed)
	rig.bot.telemetry.hashing = hashing
	var picker := RandomNumberGenerator.new()
	picker.seed = bot_seed + 1
	var views: Array[Vector3] = []
	var result := {"latencies": [], "turned": 0.0, "missed": 0, "errors": [], "rig": rig}
	rig.run(5)
	for id in range(1, count + 1):
		var around: float = rig.bot.motor.yaw + deg_to_rad(picker.randf_range(-45.0, 45.0))
		var distance := picker.randf_range(8.0, 16.0)
		rig.put_zombie(id, Vector3(-sin(around), 0.0, -cos(around)) * distance)
		var began := rig.tick_count
		var shots := rig.shot_ticks.size()
		# The window of the turn check is made of consecutive steps: a gap between two contacts is
		# not part of one.
		views.clear()
		for _i in GIVE_UP:
			var command := rig.step()
			views.append(BotRig.view_of(command))
			if views.size() > WINDOW:
				result["turned"] = maxf(result["turned"], views[-1 - WINDOW].angle_to(views[-1]))
			if rig.shot_ticks.size() > shots:
				result["errors"].append(rig.bot.motor.error_degrees)
				break
		if rig.shot_ticks.size() > shots:
			result["latencies"].append(rig.shot_ticks[-1] - began)
		else:
			result["missed"] += 1
		rig.zombies.erase(id)
		rig.run(GAP)
	return result


func test_over_a_thousand_contacts_no_first_shot_is_earlier_than_the_floor_and_one_tick() -> void:
	var seen := 0
	for profile in _profiles:
		var result: Dictionary = _runs[profile.title]
		assert_int(result["missed"]).is_less(CONTACTS / 20)
		assert_int(result["latencies"].size()).is_greater(CONTACTS * 9 / 10)
		for ticks: int in result["latencies"]:
			assert_int(ticks).is_greater_equal(FLOOR_TICKS)
		seen += result["latencies"].size() + result["missed"]
	assert_int(seen).is_greater_equal(1000)


func test_a_slower_profile_takes_longer_to_get_its_first_shot() -> void:
	var means: Array[float] = []
	for profile in _profiles:
		var latencies: Array = _runs[profile.title]["latencies"]
		var total := 0.0
		for ticks: int in latencies:
			total += ticks
		means.append(total / latencies.size())
	assert_float(means[0]).is_greater(means[1])
	assert_float(means[1]).is_greater(means[2])


func test_the_view_never_turns_faster_than_the_profiles_cap_in_any_100_ms() -> void:
	for profile in _profiles:
		var result: Dictionary = _runs[profile.title]
		var cap := deg_to_rad(profile.max_aim_speed) * WINDOW * STEP
		assert_float(result["turned"]).is_less_equal(cap + 0.0001)
		# And it does turn: the cap is reached or nearly on the long flicks of the run.
		assert_float(result["turned"]).is_greater(cap * 0.2)


func test_the_shot_always_goes_where_the_view_points() -> void:
	var rig := BotRig.new(BotProfile.regular(), 5)
	rig.put_zombie(1, Vector3(3, 0, -12))
	rig.put_zombie(2, Vector3(-4, 0, -9))
	for _i in 240:
		var command := rig.step()
		var view := BotRig.view_of(command)
		assert_float(rad_to_deg(view.angle_to(command.dir))).is_less(0.01)
		assert_float(command.dir.length()).is_equal_approx(1.0, 0.001)
	assert_int(rig.shot_ticks.size()).is_greater(0)


func test_the_trigger_waits_for_the_view_to_come_onto_the_target() -> void:
	var rig := BotRig.new(BotProfile.rookie(), 9)
	rig.put_zombie(1, Vector3(-8, 0, -8))  # 45 degrees off the view: it has to turn first.
	var fired_off := 0
	# A rookie fires when it is roughly on (`fire_slop` times the cone, and a panic shot at the most
	# `PANIC_DEGREES`), not before.
	var limit := maxf(BotMotor.CONE_MAX * rig.profile.fire_slop, BotMotor.PANIC_DEGREES)
	for _i in 200:
		var command := rig.step()
		if command.fire and rig.bot.motor.error_degrees > limit:
			fired_off += 1
	assert_int(fired_off).is_equal(0)
	assert_int(rig.shot_ticks.size()).is_greater(0)


func test_the_same_seed_makes_the_same_shots_and_another_seed_does_not() -> void:
	var a := _contacts(BotProfile.regular(), 31, 60, true)["rig"] as BotRig
	var b := _contacts(BotProfile.regular(), 31, 60, true)["rig"] as BotRig
	var c := _contacts(BotProfile.regular(), 32, 60, true)["rig"] as BotRig
	assert_array(a.shot_ticks).is_equal(b.shot_ticks)
	assert_int(a.bot.telemetry.command_hash).is_equal(b.bot.telemetry.command_hash)
	assert_bool(a.shot_ticks == c.shot_ticks).is_false()
	assert_bool(a.bot.telemetry.command_hash == c.bot.telemetry.command_hash).is_false()


func test_with_nothing_in_sight_it_stands_and_does_not_fire() -> void:
	var rig := BotRig.new()
	for _i in 300:
		var command := rig.step()
		assert_bool(command.fire).is_false()
		assert_vector(command.motion.move).is_equal(Vector2.ZERO)


func test_it_backs_away_from_a_zombie_inside_its_margin_and_not_from_one_outside() -> void:
	var profile := BotProfile.regular()
	profile.retreat_margin = 7.0
	var rig := BotRig.new(profile, 4)
	rig.put_zombie(1, Vector3(0, 0, -15))
	rig.run(60)
	assert_vector(rig.sent.back()["motion"]["move"]).is_equal(Vector2.ZERO)
	rig.zombies[1].position = Vector3(0, 0, -4)
	rig.run(60)
	var motion: Dictionary = rig.sent.back()["motion"]
	assert_float(Vector2(motion["move"]).length()).is_greater(0.5)
	assert_bool(motion["sprint"]).is_true()


func test_a_blow_from_the_side_turns_the_view_toward_it() -> void:
	var rig := BotRig.new(BotProfile.regular(), 6)
	rig.run(30)
	# Clockwise from -z seen from above: 1 radian is to the right, a view yaw of -1.
	rig.step([{"type": &"player_hurt", "player_id": BotRig.ME, "damage": 8.0, "bearing": 1.0}])
	rig.run(90)
	assert_float(absf(angle_difference(rig.bot.motor.yaw, -1.0))).is_less(0.1)


func test_the_head_is_aimed_at_with_the_profiles_rate_only_when_slow_and_near() -> void:
	var heads := 0
	var count := 250
	var rig := BotRig.new(BotProfile.veteran(), 12)
	rig.shooting = false
	for id in range(1, count + 1):
		rig.put_zombie(id, Vector3(0, 0, -8))
		rig.run(60)
		# From the eye (1.55 m) the head (1.6 m) is level, the chest (1.1 m) is 3 degrees below.
		if rig.bot.motor.pitch > -0.03:
			heads += 1
		rig.zombies.erase(id)
		rig.run(GAP)
	# The veteran aims at the head of three in four (the rate that makes three in ten of its hits
	# land there; see `test_bot_bands.gd`).
	assert_float(float(heads) / count).is_between(0.6, 0.9)
