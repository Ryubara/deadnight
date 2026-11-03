# The bots against the balance simulator's skill levels (bots plan, phase 3): a Rookie fights like
# `SimSkill` weak, a Regular like average, a Veteran like strong. Three numbers are read from a
# fight in the real server and held to the level's: the hit rate (shots that land, of the shots
# fired at a zombie 5 to 20 m away: nearer than that a shot lands whatever the aim), the head share
# (of the hits) and the dodge (of the blows that came due on the bot, the share that missed).
#
# The dead are staged (`SeatedNight.stage_the_dead`): each is put once, as soon as it is up, on the
# open ground in front of the bot and walks at it in a straight line, at 2.4 m/s (about round 8).
# The lot's cars, posts and lamps stand where the maintainer put them, but the route of the dead
# is not left to the lot: when they walked the lot to the bot, every pole moved where they came
# into view, and the shares moved with no change to the bots (#783: twenty hand-placed lamps took
# the Regular's head share from 0.80 to 0.97 and halved the shots). Two fights, one bot each with
# the pistol and endless rounds and health, so the numbers are about aim and feet and not about
# ammunition or luck:
#   - the far fight, the dead put 10 to 16 m ahead: the hit rate and the head share;
#   - the near fight, the dead put 4 to 6 m ahead and the bot's trigger held up (the legs alone, as
#     `SeatedNight.hold_fire` makes it), so that they reach the bot and blows come due: the dodge.
#     (In the far fight the bot kills almost every walker before it swings, and a bot that fires
#     at the dead put near kills them before they reach it, whatever the pace: only a bot that
#     does not shoot lives to be struck often enough to read.)
# Each band is the level's number, a tolerance either side: wide enough for the run-to-run
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
const SECONDS := 50
## Where the far fight's dead are put: from `FAR_AHEAD` metres, each further one `FAR_STEP` metres
## beyond the one before.
const FAR_AHEAD := 10.0
const FAR_STEP := 2.0
## The near fight's seeds and seconds, and where its dead are put: from `NEAR_AHEAD` metres, each
## further one `NEAR_STEP` metres beyond the one before.
const NEAR_SEEDS := 8
const NEAR_SECONDS := 30
const NEAR_AHEAD := 4.0
const NEAR_STEP := 0.7
## Metres a second the stream of zombies walks at.
const ZOMBIE_SPEED := 2.4
## Tolerances either side of the level's number.
const HIT_TOLERANCE := 0.12
## The hit rate and the head share follow `SimSkill` (#745: both were measured on the zones that
## follow the bodies, #694, where the chibi head is half the figure and a shot aimed at the chest
## lands on it most of the time). The staged far fight reads them the same on every map: head share
## 0.64 / 0.72 / 0.90 and hit rate 0.41 / 0.64 / 0.76 for the three levels, each inside its band.
const HEAD_TOLERANCE := 0.1
## The dodge is what a bot's feet do against the dead that reach it, and it is read with the
## trigger up (the near fight): the dead pile up round a bot that does not kill them, so this is
## lower than `SimSkill`'s dodge, which is the chance of a plain blow missing a player who also
## shoots (0.17, 0.55, 0.80, read in the old fight on the lot). The three levels stay apart in
## the same order. A change to `SimSkill`'s dodge is a balance change and is not made here.
const DODGE_SHARE := {&"weak": 0.0, &"average": 0.3, &"strong": 0.6}
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


## One bot of `profile` fighting the dead put `ahead` metres in front of it (and `step` metres
## further for each of the next three) for `seconds`, with its trigger up when `fire` is off.
func _fight(
	profile: BotProfile, seed_value: int, seconds: int, ahead: float, step: float, fire: bool
) -> CombatProbe:
	var night := await NightFixture.seat(self, 1, _tuning(), seed_value)
	# The numbers are about the aim of a bot that stands and fights: with no order it would roam.
	profile.follows = false
	night.stage_the_dead = true
	night.stage_near = ahead
	night.stage_step = step
	night.hold_fire = not fire
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


## The far fight over every seed, added up as `{shots, hits, heads}` (the shots and hits of the
## range only).
func _measure_aim(profile: BotProfile) -> Dictionary:
	var sum := {"shots": 0, "hits": 0, "heads": 0}
	for n in _seeds():
		var probe := await _fight(profile, n + 1, _seconds(), FAR_AHEAD, FAR_STEP, true)
		sum["shots"] += probe.range_shots
		sum["hits"] += probe.range_hits
		sum["heads"] += probe.range_heads
	return sum


## The near fight over every seed, added up as `{completed, blows}`.
func _measure_dodge(profile: BotProfile) -> Dictionary:
	var sum := {"completed": 0, "blows": 0}
	for n in NEAR_SEEDS:
		var probe := await _fight(profile, n + 1, NEAR_SECONDS, NEAR_AHEAD, NEAR_STEP, false)
		sum["completed"] += probe.completed
		sum["blows"] += probe.blows
	return sum


func _check(profile: BotProfile, level: StringName) -> void:
	var skill := SimSkill.named(level)
	var sum := await _measure_aim(profile)
	sum.merge(await _measure_dodge(profile))
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
				DODGE_SHARE[level]
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
			"%s dodge %.2f, level %s has %.2f" % [profile.title, dodge, level, DODGE_SHARE[level]]
		)
		. is_between(DODGE_SHARE[level] - DODGE_TOLERANCE, DODGE_SHARE[level] + DODGE_TOLERANCE)
	)


func test_a_rookie_fights_like_the_weak_level() -> void:
	await _check(BotProfile.rookie(), SimSkill.WEAK)


func test_a_regular_fights_like_the_average_level() -> void:
	await _check(BotProfile.regular(), SimSkill.AVERAGE)


func test_a_veteran_fights_like_the_strong_level() -> void:
	await _check(BotProfile.veteran(), SimSkill.STRONG)
