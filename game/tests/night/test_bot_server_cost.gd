# What bots cost a game server (#230, the budget of docs/research/bots.md#server-cost): three bots
# in a night with a crowd in view, the part of the tick that is theirs (hearing the step and
# deciding), timed tick by tick. The mean and the worst tick are reported and held to the budget:
# the bots together under 5% of the 60 Hz tick, and no single tick of theirs above the half
# millisecond a bot may take for one decision, per bot (judged at the 99th percentile of the ticks:
# on a shared machine one tick in a few hundred is lost to the scheduler, whatever the bots do; the
# worst tick is still printed). The budget is a statement about the bots' work, so it grows with
# how slow the machine is at a fixed piece of plain GDScript.
extends GdUnitTestSuite

const STEP := Night.STEP
const BOTS := 3
## Zombies standing on the lot during the measurement: the most a night ever has at four players
## and the figure the budget is written for (docs/design/zombies.md#crowd-budget).
const CROWD := 40
const TICKS := 900
## The tick of a server at 60 Hz, in microseconds, and the share of it the bots may take together.
const TICK_US := 16667.0
const SHARE := 0.05
## The tick of the bots together that 99 in 100 stay under: a think of each at the half millisecond
## of the decision budget.
const WORST_US := 500.0 * BOTS
## What `_reference_us` takes on the machine the budget was set on (best of five).
const REFERENCE_US := 130
const SEED := 4242


func _reference_us() -> int:
	var best := 1 << 30
	for _run in 5:
		var began := Time.get_ticks_usec()
		var table := {}
		for i in CROWD:
			table[i] = {"id": i, "position": Vector3(i, 0.0, -i), "mode": 1}
		var total := 0.0
		for _pass in 20:
			for id in table:
				var entry: Dictionary = table[id]
				var at: Vector3 = entry["position"]
				total += Vector2(at.x, at.z).length() + float(entry["mode"])
		assert_float(total).is_greater(0.0)
		best = mini(best, Time.get_ticks_usec() - began)
	return best


func test_three_bots_with_a_crowd_in_view_cost_under_a_twentieth_of_the_tick() -> void:
	var night := await NightFixture.seat(self, BOTS + 1, SeatedNight.one_a_round(), 5)
	var stand := BotProfile.regular()
	stand.follows = false
	for id in range(2, BOTS + 2):
		night.seat(id, stand, SEED + id)
	night.human(1)
	night.gather()
	night.server.rules.apply(RulesAction.skip_break())
	night.run(5)
	var spread := RandomNumberGenerator.new()
	spread.seed = 9
	var home := Autopilot.HOME
	for id in range(1000, 1000 + CROWD):
		var around := spread.randf_range(-PI, PI)
		var distance := spread.randf_range(5.0, 24.0)
		var zombie := night.server.sim.spawn(
			id, 0.0, home + Vector3(-sin(around), 0.0, -cos(around)) * distance
		)
		zombie.enter(ZombieBody.Mode.CHASE)
	var spent: Array[int] = []
	for _i in TICKS:
		var events := night.server.step(STEP)
		for walker in night.walkers:
			walker.tick()
		var began := Time.get_ticks_usec()
		night.host.hear(events)
		night.host.tick(STEP)
		spent.append(Time.get_ticks_usec() - began)
	assert_int(night.server.sim.zombies.size()).is_greater(10)
	var total := 0
	var worst := 0
	for us in spent:
		total += us
		worst = maxi(worst, us)
	var mean := float(total) / float(spent.size())
	var ranked := spent.duplicate()
	ranked.sort()
	var typical_worst: int = ranked[ranked.size() * 99 / 100]
	var slower := maxf(float(_reference_us()) / float(REFERENCE_US), 1.0)
	print(
		"bot cost: ",
		BOTS,
		" bots, ",
		night.server.sim.zombies.size(),
		" zombies; mean ",
		snappedf(mean, 1.0),
		" us (",
		snappedf(mean / TICK_US * 100.0, 0.1),
		"% of the tick), worst ",
		worst,
		" us, 99th percentile ",
		typical_worst,
		" us; machine ",
		snappedf(slower, 0.01),
		" times the reference"
	)
	(
		assert_float(mean)
		. override_failure_message("the bots' mean tick %.0f us is over the budget" % mean)
		. is_less(TICK_US * SHARE * slower)
	)
	(
		assert_float(float(typical_worst))
		. override_failure_message(
			"the bots' 99th percentile tick %d us is over the budget" % typical_worst
		)
		. is_less(WORST_US * slower)
	)
	night.dispose()
