# The filter between the frame and the brain (bots plan, phase 1): a view cone, a sight range that
# follows the light, a clear ray, a reaction delay with a floor, a memory that is never shot at, a
# hearing that gives a direction and no position, and a ray budget. Pure data: no world, no clock.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0
const THINK_EVERY := 8
const HERE := Vector3.ZERO
## The floor of a reaction, written out: not read from the code it tests.
const REACTION_FLOOR := 0.20

var _wall_x := 5.0


func _perception(profile: BotProfile = null, lit := true, sight := Callable()) -> BotPerception:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var level := BotLevel.new(sight, func(_point: Vector3) -> bool: return lit, RoundTuning.new())
	return BotPerception.new(profile if profile != null else BotProfile.regular(), level, rng)


## A wall across the whole lot at x = `_wall_x`.
func _wall() -> Callable:
	return func(from: Vector3, to: Vector3) -> float:
		if (from.x - _wall_x) * (to.x - _wall_x) < 0.0:
			return from.distance_to(to) * 0.5
		return -1.0


func _zombie(id: int, at: Vector3, mode := ZombieBody.Mode.CHASE) -> Dictionary:
	return {"id": id, "position": at, "mode": mode, "look": ZombieModels.DEFAULT}


## Looks at `zombies` every tick for `seconds` (a think every `THINK_EVERY` ticks), the bot facing
## `yaw`; returns the clock at the end.
func _watch(
	perception: BotPerception, zombies: Array[Dictionary], seconds: float, yaw := 0.0, from := 0.0
) -> float:
	var now := from
	for i in roundi(seconds / STEP):
		now += STEP
		perception.observe(now, i % THINK_EVERY == 0, {"pos": HERE}, zombies, 1, yaw)
	return now


func test_a_zombie_in_view_is_believed_only_after_its_reaction_delay() -> void:
	var perception := _perception()
	var zombies: Array[Dictionary] = [_zombie(1, Vector3(0, 0, -10))]
	var first_seen := -1.0
	var believed := -1.0
	var now := 0.0
	for i in 120:
		now += STEP
		perception.observe(now, i % THINK_EVERY == 0, {"pos": HERE}, zombies, 1, 0.0)
		var contact := perception.beliefs.contact(1)
		if not contact.is_empty() and first_seen < 0.0:
			first_seen = contact["first_seen"]
		if perception.beliefs.targets(HERE).size() > 0 and believed < 0.0:
			believed = now
	assert_float(first_seen).is_greater_equal(0.0)
	assert_float(believed - first_seen).is_greater_equal(REACTION_FLOOR)


func test_no_reaction_is_under_the_floor_and_the_mean_is_the_profiles() -> void:
	var perception := _perception()
	var total := 0.0
	var count := 2000
	for _i in count:
		var seconds := perception.draw_reaction()
		assert_float(seconds).is_greater_equal(REACTION_FLOOR)
		total += seconds
	assert_float(total / count).is_between(0.31, 0.39)
	# The fastest profile has a mean (0.25) barely over the floor: it is clamped, never under it.
	var quick := _perception(BotProfile.veteran())
	for _i in count:
		assert_float(quick.draw_reaction()).is_greater_equal(REACTION_FLOOR)


func test_a_zombie_behind_a_wall_is_never_believed_and_never_a_target() -> void:
	var perception := _perception(null, true, _wall())
	var zombies: Array[Dictionary] = [_zombie(1, Vector3(8, 0, -2))]
	# Facing the wall (+x is yaw -90 degrees), so it is inside the cone and only the wall hides it.
	_watch(perception, zombies, 10.0, -PI / 2.0)
	assert_bool(perception.beliefs.contacts.is_empty()).is_true()
	assert_array(perception.beliefs.targets(HERE)).is_empty()


func test_a_zombie_out_of_the_cone_is_not_seen() -> void:
	var perception := _perception()
	var zombies: Array[Dictionary] = [_zombie(1, Vector3(0, 0, 10))]  # Behind: yaw 180.
	_watch(perception, zombies, 3.0, 0.0)
	assert_bool(perception.beliefs.contacts.is_empty()).is_true()
	# Turned around, it is seen.
	_watch(perception, zombies, 1.0, PI)
	assert_bool(perception.beliefs.contacts.has(1)).is_true()


func test_the_cone_has_the_profiles_width() -> void:
	var perception := _perception()
	var inside := Vector3(-sin(deg_to_rad(50.0)), 0, -cos(deg_to_rad(50.0))) * 8.0
	var outside := Vector3(-sin(deg_to_rad(60.0)), 0, -cos(deg_to_rad(60.0))) * 8.0
	var zombies: Array[Dictionary] = [_zombie(1, inside), _zombie(2, outside)]
	_watch(perception, zombies, 0.5)
	assert_bool(perception.beliefs.contacts.has(1)).is_true()
	assert_bool(perception.beliefs.contacts.has(2)).is_false()


func test_sight_range_follows_the_light_and_the_round() -> void:
	var rounds := RoundTuning.new()
	var dark := BotLevel.new(Callable(), func(_p: Vector3) -> bool: return false, rounds)
	var lit := BotLevel.new(Callable(), func(_p: Vector3) -> bool: return true, rounds)
	var far := Vector3(0, 0, -26)
	var ambient := rounds.ambient_for_round(1)
	assert_float(dark.view_range(far, 1)).is_equal_approx(8.0 + 25.0 * ambient, 0.001)
	assert_float(dark.view_range(far, 1)).is_less(26.0)
	assert_float(lit.view_range(far, 1)).is_equal(33.0)
	# The night closes in with the rounds.
	assert_float(dark.view_range(far, 12)).is_less(dark.view_range(far, 1))
	assert_float(dark.view_range(far, 99)).is_equal_approx(8.0 + 25.0 * rounds.ambient_min, 0.001)
	# And the bot only makes out what the range allows.
	var perception := _perception(null, false)
	var zombies: Array[Dictionary] = [
		_zombie(1, Vector3(0, 0, -20)), _zombie(2, Vector3(0, 0, -27))
	]
	_watch(perception, zombies, 0.5)
	assert_bool(perception.beliefs.contacts.has(1)).is_true()
	assert_bool(perception.beliefs.contacts.has(2)).is_false()


func test_a_zombie_out_of_sight_is_remembered_then_forgotten_and_never_shot_at() -> void:
	var perception := _perception()
	var zombies: Array[Dictionary] = [_zombie(1, Vector3(0, 0, -10))]
	var now := _watch(perception, zombies, 1.5)
	assert_int(perception.beliefs.targets(HERE).size()).is_equal(1)
	# It walks behind the bot's back: still believed, no longer a target.
	zombies = [_zombie(1, Vector3(0, 0, 10))]
	now = _watch(perception, zombies, 0.5, 0.0, now)
	assert_int(perception.beliefs.targets(HERE).size()).is_equal(0)
	assert_int(perception.beliefs.remembered().size()).is_equal(1)
	# Then the memory runs out.
	now = _watch(perception, zombies, BotProfile.regular().memory_seconds + 0.5, 0.0, now)
	assert_bool(perception.beliefs.contacts.is_empty()).is_true()


func test_a_remembered_zombie_is_guessed_on_along_its_last_heading() -> void:
	var perception := _perception()
	var zombies: Array[Dictionary] = []
	var now := 0.0
	# It walks toward the bot at 1.5 m/s while seen.
	for i in 120:
		now += STEP
		zombies = [_zombie(1, Vector3(0, 0, -14.0 + 1.5 * now))]
		perception.observe(now, i % THINK_EVERY == 0, {"pos": HERE}, zombies, 1, 0.0)
	var contact := perception.beliefs.contact(1)
	assert_float(contact["velocity"].z).is_between(1.0, 2.0)
	var seen_at: Vector3 = contact["position"]
	# Out of the cone, remembered; the guess carries on and is capped by the memory.
	zombies = [_zombie(1, Vector3(0, 0, 10))]
	now = _watch(perception, zombies, 1.0, 0.0, now)
	var remembered := perception.beliefs.remembered()
	assert_int(remembered.size()).is_equal(1)
	var guess := perception.beliefs.guess(remembered[0], 3.0)
	assert_float(guess.z).is_greater(seen_at.z)


func test_a_zombie_seen_for_less_than_its_reaction_is_never_noticed() -> void:
	var perception := _perception(BotProfile.rookie())
	var zombies: Array[Dictionary] = [_zombie(1, Vector3(0, 0, -10))]
	var now := _watch(perception, zombies, 0.12)
	assert_array(perception.beliefs.targets(HERE)).is_empty()
	zombies = [_zombie(1, Vector3(0, 0, 10))]  # Gone behind the bot before it registered.
	_watch(perception, zombies, 0.5, 0.0, now)
	assert_bool(perception.beliefs.contacts.is_empty()).is_true()


func test_a_zombie_out_of_sight_and_near_is_heard_as_a_direction_not_a_position() -> void:
	_wall_x = 2.0
	var perception := _perception(null, true, _wall())
	var zombies: Array[Dictionary] = [_zombie(1, Vector3(3.0, 0, 0))]
	_watch(perception, zombies, 1.0, -PI / 2.0)
	assert_array(perception.beliefs.contacts.keys()).is_empty()
	assert_int(perception.beliefs.heard.size()).is_equal(1)
	var sound: Dictionary = perception.beliefs.heard[0]
	assert_bool(sound.has("position")).is_false()
	assert_bool(sound.has("id")).is_false()
	# 3 m is outside the very near class (2 m) and inside hearing (4 m).
	assert_str(sound["range_class"]).is_equal("near")
	# The zombie is to the +x side, which is a view yaw of about -90 degrees.
	assert_float(sound["yaw"]).is_between(-PI / 2.0 - 0.8, -PI / 2.0 + 0.8)
	# Farther than hearing: nothing.
	_wall_x = 5.0
	var far := _perception(null, true, _wall())
	var distant: Array[Dictionary] = [_zombie(1, Vector3(9.0, 0, 0))]
	_watch(far, distant, 1.0, -PI / 2.0)
	assert_array(far.beliefs.heard).is_empty()


func test_a_think_casts_at_most_the_budget_of_rays_with_the_whole_crowd_in_view() -> void:
	var perception := _perception()
	var zombies: Array[Dictionary] = []
	for i in 46:
		zombies.append(_zombie(i + 1, Vector3(-12.0 + 0.5 * i, 0, -8.0 - i * 0.3)))
	for i in 40:
		perception.observe(STEP * (i + 1), true, {"pos": HERE}, zombies, 1, 0.0)
		assert_int(perception.rays_last).is_less_equal(BotProfile.regular().rays_per_think)
	assert_int(perception.rays_last).is_greater(0)


func test_a_zombie_going_down_or_coming_out_of_the_ground_is_not_a_contact() -> void:
	var perception := _perception()
	var zombies: Array[Dictionary] = [
		_zombie(1, Vector3(0, 0, -6), ZombieBody.Mode.DYING),
		_zombie(2, Vector3(1, 0, -6), ZombieBody.Mode.EMERGING),
	]
	_watch(perception, zombies, 1.0)
	assert_bool(perception.beliefs.contacts.is_empty()).is_true()
	# One that was a contact is dropped the moment it goes down.
	zombies = [_zombie(3, Vector3(0, 0, -6))]
	var now := _watch(perception, zombies, 1.0)
	assert_bool(perception.beliefs.contacts.has(3)).is_true()
	zombies = [_zombie(3, Vector3(0, 0, -6), ZombieBody.Mode.DYING)]
	_watch(perception, zombies, 0.2, 0.0, now)
	assert_bool(perception.beliefs.contacts.has(3)).is_false()
