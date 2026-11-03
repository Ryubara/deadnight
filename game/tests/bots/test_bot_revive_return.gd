# Bots come back for a body (Deadnight #673), played on the bots' own beliefs with a clock and
# walking bots, no night around it, so each rule's effect is the only difference between two runs.
#
# Scenario A: a person lies by a pack of 14 (`UNSAFE` for everyone), two bots stand far off, the
# pack goes with a few seconds of the bleed-out clock left. A bot that did not stage is too far
# for the time that is left (`LATE`); the one that staged is raised in time.
# Scenario B: a bot nearer the body is stuck (it asks to go, and its position never changes); the
# bot behind it is not 2 m nearer, so it never takes the claim. The stall rule gives the claim up.
extends GdUnitTestSuite

const DT := 0.1
const BLEED := 45.0
const BODY := Vector3(0.0, 0.0, 0.0)
const PERSON := 1
const WALK := 4.2
const RUN := 5.4
const PACK := 14
const ROUND := 8
## Scenario A: where the bots stand, and when the pack goes (so `BLEED - GONE_AT` is the time left).
const FAR_A := Vector3(46.0, 0.0, -18.0)
const FAR_B := Vector3(44.0, 0.0, -24.0)
const GONE_AT := 34.0
## Scenario B: the stuck bot and the one behind it.
const STUCK_AT := Vector3(5.0, 0.0, 0.0)
const BEHIND_AT := Vector3(11.0, 0.0, 0.0)


func after_test() -> void:
	BotRevive.stage_on = true
	BotRevive.stall_on = true


## One bot of a play: its place, its revive and its hold's seconds so far.
class Walker:
	extends RefCounted
	var id := 0
	var pos := Vector3.ZERO
	var stuck := false
	var revive: BotRevive
	var held := 0.0
	var staged := 0.0
	var closest := INF


## What a play came to: the seconds the person was raised at (-1 for never) and the nearest a bot
## was when the pack went.
class Outcome:
	extends RefCounted
	var raised_at := -1.0
	var nearest_at_gone := INF
	var staged_seconds := 0.0
	var stalls := 0


func _walker(id: int, at: Vector3, team: BotTeam, stuck := false) -> Walker:
	var walker := Walker.new()
	walker.id = id
	walker.pos = at
	walker.stuck = stuck
	walker.revive = BotRevive.new(BotProfile.regular())
	walker.revive.team = team
	walker.revive.rounds = RoundTuning.new()
	return walker


func _beliefs(walker: Walker, walkers: Array[Walker], t: float, pack: bool) -> BotBeliefs:
	var beliefs := BotBeliefs.new()
	beliefs.me = walker.id
	beliefs.now = t
	beliefs.teammates = {
		PERSON:
		{
			"id": PERSON,
			"pos": BODY,
			"downed": true,
			"dead": false,
			"bot": false,
			"health": 0.0,
			"bleed": maxf(BLEED - t, 0.0),
			"reviver": 0,
			"revive": 0.0,
		}
	}
	for other in walkers:
		beliefs.teammates[other.id] = {
			"id": other.id,
			"pos": other.pos,
			"downed": false,
			"dead": false,
			"bot": true,
			"health": 100.0,
		}
	if pack:
		for i in PACK:
			var at := Vector3(2.0 + float(i % 5) * 1.5, 0.0, -3.0 - float(i / 5) * 1.5)
			beliefs.contacts[i] = {
				"id": i,
				"position": at,
				"velocity": Vector3.ZERO,
				"last_seen": t,
				"believed_at": 0.0,
				"mode": ZombieBody.Mode.CHASE,
				"look": ZombieModels.DEFAULT,
			}
	return beliefs


## Plays the clock: every think each bot runs its revive, walks toward its goal (a bot that is stuck
## does not move), and a bot in `HOLD` at the body counts its seconds; the person is raised when one
## has held for `BotRevive.REVIVE_SECONDS`.
func _play(walkers: Array[Walker], gone_at: float) -> Outcome:
	var outcome := Outcome.new()
	var team: BotTeam = walkers[0].revive.team
	var t := 0.0
	while t < BLEED:
		var pack := t < gone_at
		for walker in walkers:
			var intent := BotIntent.new()
			var me: Dictionary = _beliefs(walker, walkers, t, pack).teammates[walker.id]
			walker.revive.run(
				intent,
				_beliefs(walker, walkers, t, pack),
				me,
				WeaponCatalog.get_def(&"pistol"),
				ROUND,
				DT
			)
			if walker.revive.mode == BotRevive.Mode.STAGE:
				outcome.staged_seconds += DT
			if walker.revive.mode == BotRevive.Mode.HOLD:
				walker.held += DT
				if walker.held >= BotRevive.REVIVE_SECONDS:
					outcome.raised_at = t
					return outcome
			else:
				walker.held = 0.0
			if not walker.stuck and intent.goal != Vector3.INF:
				var to_goal := intent.goal - walker.pos
				to_goal.y = 0.0
				if to_goal.length() > intent.goal_radius:
					var speed := (RUN if intent.run else WALK) * DT
					walker.pos += to_goal.normalized() * minf(speed, to_goal.length())
		if absf(t - gone_at) < DT * 0.5:
			for walker in walkers:
				outcome.nearest_at_gone = minf(outcome.nearest_at_gone, _flat(walker.pos, BODY))
		t += DT
	return outcome


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _scenario_a(stage: bool) -> Outcome:
	BotRevive.stage_on = stage
	var team := BotTeam.new()
	var walkers: Array[Walker] = [_walker(2, FAR_A, team), _walker(3, FAR_B, team)]
	return _play(walkers, GONE_AT)


func _scenario_b(stall: bool) -> Outcome:
	BotRevive.stall_on = stall
	var team := BotTeam.new()
	var walkers: Array[Walker] = [_walker(2, STUCK_AT, team, true), _walker(3, BEHIND_AT, team)]
	return _play(walkers, -1.0)


func test_a_pack_goes_and_a_bot_that_staged_is_there_in_time() -> void:
	var late := _scenario_a(false)
	var staged := _scenario_a(true)
	# Without staging the bots are 40 m and more from the body when the pack goes, and the time left
	# is too short for the walk.
	assert_float(late.nearest_at_gone).is_greater(35.0)
	assert_float(late.raised_at).is_equal(-1.0)
	assert_float(staged.nearest_at_gone).is_less(17.0)
	assert_float(staged.raised_at).is_greater(GONE_AT)
	assert_float(staged.raised_at).is_less(BLEED)
	assert_float(staged.staged_seconds).is_greater(5.0)


func test_a_stuck_claimant_gives_the_claim_up_so_the_bot_behind_it_raises_the_person() -> void:
	var held := _scenario_b(false)
	var freed := _scenario_b(true)
	assert_float(held.raised_at).is_equal(-1.0)
	assert_float(freed.raised_at).is_greater(0.0)
	assert_float(freed.raised_at).is_less(BLEED)


func test_the_two_rules_do_not_change_each_other() -> void:
	# Staging off or stall off changes nothing in the other's scenario.
	BotRevive.stall_on = false
	var staged_without_stall := _scenario_a(true)
	BotRevive.stage_on = false
	var freed_without_stage := _scenario_b(true)
	assert_float(staged_without_stall.raised_at).is_greater(GONE_AT)
	assert_float(freed_without_stage.raised_at).is_greater(0.0)


func test_with_the_pack_never_going_nobody_is_sent_in() -> void:
	BotRevive.stage_on = true
	var team := BotTeam.new()
	var walkers: Array[Walker] = [_walker(2, FAR_A, team), _walker(3, FAR_B, team)]
	var outcome := _play(walkers, 1000.0)
	assert_float(outcome.raised_at).is_equal(-1.0)
