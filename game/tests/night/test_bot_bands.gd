# The bots against the balance simulator's skill levels (bots plan, phase 3): a Rookie fights like
# `SimSkill` weak, a Regular like average, a Veteran like strong. Three numbers are read from a
# fight in the real server and held to the level's: the hit rate (shots that land, of the shots
# fired at a zombie 5 to 20 m away: nearer than that a shot lands whatever the aim), the head share
# (of the hits) and the dodge (of the blows that came due on the bot, the share that missed).
#
# The fight is a stream of walkers at 2.4 m/s (about round 8) on open ground, one bot with the
# pistol and endless rounds and health, so the numbers are about aim and feet and not about
# ammunition
# or luck. Each band is the level's number, a tolerance either side: wide enough for the run-to-run
# differences of a physics engine (two runs of the same commands are not bit-identical) and for the
# few hundred shots a run has, narrow enough that the three profiles stay apart. The measured
# numbers of a longer run are on the bots research page. More seeds and seconds for a long run:
# `BOTS_BANDS_SEEDS=6 BOTS_BANDS_SECONDS=150`.
extends GdUnitTestSuite

const STEP := Night.STEP
## Seeds, and seconds of play for each.
## Eight: the Veteran's dodge is read from the few dozen blows that come due, and with four seeds a
## change of the navigation mesh moved it from 0.50 to 0.68 (19 blows) where ten seeds read 0.60.
const SEEDS := 8
const SECONDS := 110
## Metres a second the stream of zombies walks at.
const ZOMBIE_SPEED := 2.4
## Tolerances either side of the level's number.
const HIT_TOLERANCE := 0.12
## The head share and the dodge follow `SimSkill` again (#745). Both were re-measured on the zones
## that follow the bodies (#694: the chibi head is half the figure, so a shot aimed at the chest
## lands on it most of the time) and `SimSkill` was set to the middle of what eight seeds read:
## head share 0.64 to 0.72 / 0.78 to 0.84 / 0.81 to 0.88 and dodge 0.15 to 0.21 / 0.47 to 0.68 /
## 0.73 to 0.91 for the three levels, on this machine and on the CI runner (0.66 / 0.82 / 0.81 and
## 0.16 / 0.47 / 0.79). Two runs of the same commands are not bit-identical, and a Veteran's dodge
## is read from a few dozen blows, so the tolerances are the width of that spread; the three
## levels stay apart in the same order.
const HEAD_TOLERANCE := 0.1
const DODGE_TOLERANCE := 0.2


func _seeds() -> int:
	var value := OS.get_environment("BOTS_BANDS_SEEDS")
	return int(value) if value != "" else SEEDS


func _seconds() -> int:
	var value := OS.get_environment("BOTS_BANDS_SECONDS")
	return int(value) if value != "" else SECONDS


func _tuning() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.count_base = 200.0
	tuning.rounds.first_spawn_delay = 0.1
	tuning.health.max_health = 100000.0
	tuning.rounds.speed_base = ZOMBIE_SPEED
	tuning.rounds.speed_step = 0.0
	tuning.rounds.speed_jitter = 0.0
	return tuning


## One bot of `profile` fighting the stream for `seconds`.
func _fight(profile: BotProfile, seed_value: int, seconds: int) -> CombatProbe:
	var night := await NightFixture.seat(self, 1, _tuning(), seed_value)
	# The numbers are about the aim of a bot that stands and fights: with no order it would roam.
	profile.follows = false
	night.seat(1, profile, seed_value)
	night.start_round()
	night.server.body_of(1).teleport(Autopilot.HOME + Vector3(0.0, 0.1, 0.0))
	var probe := CombatProbe.new().watch(night)
	for _i in seconds * 60:
		night.server.combat.weapon_of(1).reserve = 500
		night.tick()
		probe.tick()
	probe.stop()
	night.dispose()
	return probe


## The fight over every seed, added up as `{shots, hits, heads, completed, blows}` (the shots and
## hits of the range only).
func _measure(profile: BotProfile) -> Dictionary:
	var sum := {"shots": 0, "hits": 0, "heads": 0, "completed": 0, "blows": 0}
	for n in _seeds():
		var probe := await _fight(profile, n + 1, _seconds())
		sum["shots"] += probe.range_shots
		sum["hits"] += probe.range_hits
		sum["heads"] += probe.range_heads
		sum["completed"] += probe.completed
		sum["blows"] += probe.blows
	return sum


func _check(profile: BotProfile, level: StringName) -> void:
	var skill := SimSkill.named(level)
	var sum := await _measure(profile)
	var hit := float(sum["hits"]) / float(maxi(sum["shots"], 1))
	var head := float(sum["heads"]) / float(maxi(sum["hits"], 1))
	var dodge := 1.0 - float(sum["blows"]) / float(maxi(sum["completed"], 1))
	print(
		(
			"BANDS %s (%s): shots %d hit %.2f (%.2f) head %.2f (%.2f) blows due %d dodge %.2f (%.2f)"
			% [
				profile.title,
				level,
				sum["shots"],
				hit,
				skill.accuracy,
				head,
				skill.head_rate,
				sum["completed"],
				dodge,
				skill.dodge
			]
		)
	)
	assert_int(sum["shots"]).is_greater(80)
	assert_int(sum["completed"]).is_greater(25)
	(
		assert_float(hit)
		. override_failure_message(
			"%s hit rate %.2f, level %s has %.2f" % [profile.title, hit, level, skill.accuracy]
		)
		. is_between(skill.accuracy - HIT_TOLERANCE, skill.accuracy + HIT_TOLERANCE)
	)
	(
		assert_float(head)
		. override_failure_message(
			"%s head share %.2f, level %s has %.2f" % [profile.title, head, level, skill.head_rate]
		)
		. is_between(skill.head_rate - HEAD_TOLERANCE, skill.head_rate + HEAD_TOLERANCE)
	)
	(
		assert_float(dodge)
		. override_failure_message(
			"%s dodge %.2f, level %s has %.2f" % [profile.title, dodge, level, skill.dodge]
		)
		. is_between(skill.dodge - DODGE_TOLERANCE, skill.dodge + DODGE_TOLERANCE)
	)


func test_a_rookie_fights_like_the_weak_level() -> void:
	await _check(BotProfile.rookie(), SimSkill.WEAK)


func test_a_regular_fights_like_the_average_level() -> void:
	await _check(BotProfile.regular(), SimSkill.AVERAGE)


func test_a_veteran_fights_like_the_strong_level() -> void:
	await _check(BotProfile.veteran(), SimSkill.STRONG)
