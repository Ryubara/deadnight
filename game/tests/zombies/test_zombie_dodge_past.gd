extends GdUnitTestSuite
## What holding a route costs a dead that chases a person who runs past it (#1347). The hold
## (`ZombieSim._keeps_its_route`) keeps the old route against a new one that sends the dead back
## the way it is going, and its gain test is always true when little of the route is left, so a
## person who dodges past a dead 2 to 4 m away might find it walking the wrong way for a while.
##
## On open ground (a path of two points, as the walking mesh gives), a dead chases a person
## standing `GAPS` metres off. The person sidesteps up to `SIDE_MAX` metres and runs past it, to
## behind it, and on, at a person's run speed and at its sprint; or circles it at `CIRCLES`. For
## the hold on and off: the metres the dead walks away from the person while it is within `NEAR`
## (and the seconds that takes). It was 0.00 in every case, with the hold firing in some: to turn
## the dead back by more than a right angle between two repaths (0.25 s) the person has to pass
## within about a metre of it, inside its reach (1.4 m), where it swings and asks for a new route
## after, when the old one is stale.
##
## The control: a dead that never repaths does walk away from the person here, and the numbers
## show it, so a 0.00 is a dead that turned and not a count that cannot see.

const GAPS: Array[float] = [2.0, 3.0, 4.0]
## Metres per second: a crawler, and a walker of a later round.
const SPEEDS: Array[float] = [1.2, 2.0]
const SEEDS: Array[int] = [1, 2, 3]
const SIDE_STEP := 0.3
const SIDE_MAX := 3.0
## Seconds the dead chases the still person before the dodge, so it is on its route.
const SETTLE := 1.0
const RUN_ON := 6.0
## The chase is counted while the person is nearer than this (the far dead repath less often).
const NEAR := 14.0
## Radii (m) and speeds (m/s) of a person who circles the dead: walking, jogging, running.
const CIRCLES: Array[float] = [1.0, 1.5, 2.0, 3.0]
const CIRCLE_SPEEDS: Array[float] = [2.4, 3.6, 4.8]
## What the hold may add to the dead walking away from the person (metres, seconds).
const MAY_ADD_METRES := 0.1
const MAY_ADD_SECONDS := 0.1
## What a dead that never repaths must show for the measure to be trusted.
const CONTROL_LEAST_METRES := 0.5


## An open field: the walking mesh's path across it is the two ends.
class OpenPathing:
	extends ZombiePathing

	func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		return PackedVector3Array([from, to])


## What one chase gave: the metres and seconds the dead walked away from the person.
class Walk:
	extends RefCounted
	var metres := 0.0
	var seconds := 0.0

	func add(step: Vector3, to_person: Vector3) -> void:
		to_person.y = 0.0
		var along := step.dot(to_person.normalized())
		if step.length() > 0.0001 and along < 0.0 and to_person.length() < NEAR:
			metres += -along
			seconds += ZombieSim.STEP


func _dead(speed: float, profile: ZombieProfile, hold: bool, seed: int) -> Array:
	var sim := ZombieFixture.sim(seed)
	sim.pathing = OpenPathing.new()
	sim.hold_back_routes = hold
	var zombie := sim.spawn(900, speed, Vector3.ZERO, 0.0, profile)
	zombie.enter(ZombieBody.Mode.CHASE)
	return [sim, zombie]


## The person stands north of the dead, sidesteps `side` metres east, then runs south past the dead
## and on at `run`. `frozen` is the control: the dead never asks for a new route.
func _dodge(
	gap: float,
	side: float,
	speed: float,
	profile: ZombieProfile,
	hold: bool,
	run: float,
	seed: int,
	frozen := false
) -> Walk:
	var made := _dead(speed, profile, hold, seed)
	var sim: ZombieSim = made[0]
	var zombie: ZombieBody = made[1]
	# The dead closes `speed * SETTLE` while it settles, so the gap at the dodge is `gap`.
	var person := Vector3(0.0, 0.0, -(gap + speed * SETTLE))
	for _i in ceili(SETTLE / ZombieSim.STEP):
		sim.tick(ZombieSim.STEP, {1: person})
	var start_x := person.x
	var walk := Walk.new()
	var behind := false
	var previous := zombie.position
	for _i in ceili((gap + side + RUN_ON * 4.0) / run / ZombieSim.STEP):
		if person.x < start_x + side:
			person.x = minf(person.x + run * ZombieSim.STEP, start_x + side)
		else:
			person.z += run * ZombieSim.STEP
		if frozen:
			zombie.repath_left = 100.0
		sim.tick(ZombieSim.STEP, {1: person})
		var step := zombie.position - previous
		previous = zombie.position
		behind = behind or person.z > zombie.position.z
		if behind:
			walk.add(step, person - zombie.position)
	return walk


## The person circles the dead (at its current place) at radius `r` and `v`, two laps.
func _circle(
	r: float, v: float, speed: float, profile: ZombieProfile, hold: bool, frozen := false
) -> Walk:
	var made := _dead(speed, profile, hold, SEEDS[0])
	var sim: ZombieSim = made[0]
	var zombie: ZombieBody = made[1]
	var person := Vector3(0.0, 0.0, -(r + 3.0))
	for _i in ceili(SETTLE / ZombieSim.STEP):
		sim.tick(ZombieSim.STEP, {1: person})
	var walk := Walk.new()
	var previous := zombie.position
	var angle := 0.0
	var travelled := 0.0
	while travelled < TAU * r * 2.0:
		angle += v / r * ZombieSim.STEP
		travelled += v * ZombieSim.STEP
		person = zombie.position + Vector3(sin(angle), 0.0, -cos(angle)) * r
		if frozen:
			zombie.repath_left = 100.0
		sim.tick(ZombieSim.STEP, {1: person})
		walk.add(zombie.position - previous, person - zombie.position)
		previous = zombie.position
	return walk


func _profile(speed: float) -> ZombieProfile:
	var tuning := ZombieTuning.shipped()
	if speed < 1.5:
		var type := RulesFixture.tuning().roster.type_of(&"crawler")
		return ZombieProfile.from_type(type, &"crawler", tuning)
	return ZombieProfile.plain(tuning)


func _report(label: String, off: Walk, on: Walk) -> void:
	print(
		(
			"DODGE %s | hold off: %.2f m, %.2f s | on: %.2f m, %.2f s"
			% [label, off.metres, off.seconds, on.metres, on.seconds]
		)
	)
	(
		assert_float(on.metres)
		. override_failure_message(
			(
				"%s: the hold has the dead walk %.2f m away from the person, %.2f m without it"
				% [label, on.metres, off.metres]
			)
		)
		. is_less_equal(off.metres + MAY_ADD_METRES)
	)
	(
		assert_float(on.seconds)
		. override_failure_message(
			(
				"%s: the hold has the dead walk away %.2f s, %.2f s without it"
				% [label, on.seconds, off.seconds]
			)
		)
		. is_less_equal(off.seconds + MAY_ADD_SECONDS)
	)


func test_a_person_who_dodges_past_a_dead_does_not_find_it_walking_away() -> void:
	var sidesteps := roundi(SIDE_MAX / SIDE_STEP) + 1
	for run in [PlayerTuning.new().run_speed, PlayerTuning.new().sprint_speed]:
		for speed in SPEEDS:
			var profile := _profile(speed)
			for gap in GAPS:
				var worst_off := Walk.new()
				var worst_on := Walk.new()
				for step in sidesteps:
					for seed in SEEDS:
						var side := SIDE_STEP * step
						var off := _dodge(gap, side, speed, profile, false, run, seed)
						var on := _dodge(gap, side, speed, profile, true, run, seed)
						if off.metres > worst_off.metres:
							worst_off = off
						if on.metres > worst_on.metres:
							worst_on = on
				_report(
					(
						"run %.1f dead %.1f gap %.0f (worst of %d sidesteps)"
						% [run, speed, gap, sidesteps]
					),
					worst_off,
					worst_on
				)


func test_a_person_who_circles_a_dead_does_not_find_it_walking_away() -> void:
	for speed in SPEEDS:
		var profile := _profile(speed)
		for r in CIRCLES:
			for v in CIRCLE_SPEEDS:
				var off := _circle(r, v, speed, profile, false)
				var on := _circle(r, v, speed, profile, true)
				_report("circle dead %.1f r %.1f v %.1f" % [speed, r, v], off, on)


func test_a_dead_that_never_repaths_is_seen_walking_away() -> void:
	var frozen := _dodge(4.0, 0.3, 2.0, _profile(2.0), true, 4.8, SEEDS[0], true)
	print("DODGE control, no repath: %.2f m, %.2f s" % [frozen.metres, frozen.seconds])
	assert_float(frozen.metres).is_greater_equal(CONTROL_LEAST_METRES)
	var circling := _circle(3.0, 4.8, 2.0, _profile(2.0), true, true)
	print("CIRCLE control, no repath: %.2f m, %.2f s" % [circling.metres, circling.seconds])
	assert_float(circling.metres).is_greater_equal(CONTROL_LEAST_METRES)
