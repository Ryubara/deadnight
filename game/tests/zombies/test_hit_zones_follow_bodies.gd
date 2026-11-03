extends GdUnitTestSuite
## The hit zones against the bodies the player sees (#694): a grid of rays is fired at each zombie's
## skinned mesh in each pose it can be in, from eight sides and three heights, through the very
## target and trace the server shoots with (`ZombieBody.hit_target`, `AimResolver.trace_one`).
## Every ray that touches the mesh must register, and on the right part: the head's zone on a
## forehead above all (a crawler's was missed more often than not, its zones standing upright
## where it lies on the ground).

## A grid this fine finds every gap wider than a hand; the finer the slower.
const SPACING := 0.1
## The share of rays that touch the mesh that register, per body: the headliner's spiked crown and
## big hands are the thinnest of its mesh.
const ANY := {&"walker": 0.94, &"crawler": 0.95, &"headliner": 0.9}
## The share of rays that touch the head that register at all, and as the head's zone: a hand in
## front of the face, a crawler's reaching past it, takes some of them.
const HEAD_ANY := {&"walker": 0.93, &"crawler": 0.93, &"headliner": 0.9}
const HEAD_OWN := {&"walker": 0.8, &"crawler": 0.7, &"headliner": 0.35}
## The most registered shots that may miss the mesh: zones follow the bones, they are not a box.
const OFF_THE_MESH := 0.65
## Crawl moments (seconds into the 1.67 s cycle) shot at.
const CRAWL_TIMES: Array[float] = [0.0, 0.42, 0.83, 1.25]

var _def: WeaponDef = WeaponCatalog.get_def(&"pistol")


## A zombie as the night holds it: a real `ZombieBody` with the profile of its type, `mode` and
## `tearing`, standing at the origin facing +Z.
func _body(look: StringName, mode: int, tearing: bool = false, speed: float = 0.0) -> ZombieBody:
	var body := ZombieBody.new()
	body.id = 1
	var profile := ZombieProfile.new()
	profile.look = look
	profile.type = look
	profile.hit_chance = 0.6 if look == &"crawler" else 1.0
	profile.boss = ZombieModels.is_boss(look)
	profile.weak = profile.boss
	profile.emerge = 0.7
	body.profile = profile
	body.mode = mode as ZombieBody.Mode
	body.tearing = tearing
	body.move_speed = speed
	return body


## What the server's trace finds along a ray: the zone of the nearest hit, or empty.
func _shooter(body: ZombieBody) -> Callable:
	var targets := {1: body.hit_target()}
	var def := _def
	return func(origin: Vector3, dir: Vector3) -> StringName:
		var shot := AimResolver.trace_one(def, origin, dir, origin, targets, Callable())
		var hits: Array = shot["hits"]
		return hits[0]["zone"] if not hits.is_empty() else &""


func _grid(
	probe: ZombieMeshProbe, body: ZombieBody, clip: StringName, time: float
) -> ZombieRayGrid:
	probe.pose(clip, time, body.hit_target()["pos"].y)
	var grid := ZombieRayGrid.new()
	grid.elevations = [0.0, 25.0]
	grid.run(probe, _shooter(body), SPACING)
	return grid


func _check(grid: ZombieRayGrid, body: StringName, label: String) -> void:
	(
		assert_float(grid.registered_rate())
		. override_failure_message(
			(
				"%s: shots that touch the mesh register %.1f%% (%s)"
				% [label, grid.registered_rate() * 100.0, grid.summary()]
			)
		)
		. is_greater_equal(ANY[body])
	)
	(
		assert_float(grid.registered_rate(ZombieMeshProbe.Part.HEAD))
		. override_failure_message(
			(
				"%s: head shots register %.1f%% (%s)"
				% [label, grid.registered_rate(ZombieMeshProbe.Part.HEAD) * 100.0, grid.summary()]
			)
		)
		. is_greater_equal(HEAD_ANY[body])
	)
	(
		assert_float(grid.matched_rate(ZombieMeshProbe.Part.HEAD))
		. override_failure_message(
			(
				"%s: head shots count as head %.1f%% (%s)"
				% [label, grid.matched_rate(ZombieMeshProbe.Part.HEAD) * 100.0, grid.summary()]
			)
		)
		. is_greater_equal(HEAD_OWN[body])
	)
	(
		assert_float(grid.spurious_rate())
		. override_failure_message(
			(
				"%s: %.1f%% of registered shots miss the mesh (%s)"
				% [label, grid.spurious_rate() * 100.0, grid.summary()]
			)
		)
		. is_less_equal(OFF_THE_MESH)
	)


func test_every_shot_that_touches_a_crawler_registers_in_every_crawl_frame() -> void:
	var probe := ZombieMeshProbe.make(self, &"crawler")
	var body := _body(&"crawler", ZombieBody.Mode.CHASE)
	for time in CRAWL_TIMES:
		_check(_grid(probe, body, &"Crawl", time), &"crawler", "crawl at %.2f s" % time)
	probe.free_model()


func test_a_crawler_is_hit_in_the_poses_it_takes_when_it_strikes_and_staggers() -> void:
	var probe := ZombieMeshProbe.make(self, &"crawler")
	for case: Array in [
		[ZombieBody.Mode.ATTACK, &"Punch", 0.35],
		[ZombieBody.Mode.STAGGER, &"HitReact", 0.25],
	]:
		var body := _body(&"crawler", case[0])
		_check(_grid(probe, body, case[1], case[2]), &"crawler", "crawler %s" % case[1])
	probe.free_model()


func test_every_shot_that_touches_a_walker_registers_walking_running_striking_and_staggering(
) -> void:
	var probe := ZombieMeshProbe.make(self, &"walker")
	probe.use_extra_clips()
	for case: Array in [
		[ZombieBody.Mode.CHASE, false, &"Idle", 0.5],
		[ZombieBody.Mode.CHASE, false, &"Walk", 0.33],
		[ZombieBody.Mode.CHASE, false, &"Walk", 1.0],
		[ZombieBody.Mode.CHASE, false, &"Run", 0.17, 3.5],
		[ZombieBody.Mode.CHASE, false, &"extra/Sprint", 0.33, 6.5],
		[ZombieBody.Mode.ATTACK, false, &"Punch", 0.35],
		[ZombieBody.Mode.ATTACK, true, &"extra/Tear_Boards", 0.5],
		[ZombieBody.Mode.STAGGER, false, &"HitReact", 0.3],
	]:
		var body := _body(&"walker", case[0], case[1], case[4] if case.size() > 4 else 0.0)
		_check(_grid(probe, body, case[2], case[3]), &"walker", "walker %s" % case[2])
	probe.free_model()


func test_the_other_looks_are_hit_on_their_own_bodies_too() -> void:
	for look: StringName in [&"greaser", &"usher", &"farmhand", &"runner", &"brute"]:
		var probe := ZombieMeshProbe.make(self, look)
		var body := _body(look, ZombieBody.Mode.CHASE)
		_check(_grid(probe, body, &"Walk", 0.33), &"walker", String(look))
		probe.free_model()


func test_every_shot_that_touches_the_headliner_registers_in_its_poses() -> void:
	var probe := ZombieMeshProbe.make(self, &"headliner")
	probe.use_extra_clips()
	for case: Array in [
		[ZombieBody.Mode.CHASE, &"Boss_Walk", 0.4],
		[ZombieBody.Mode.ATTACK, &"Boss_Attack", 1.0],
		[ZombieBody.Mode.STAGGER, &"Boss_Stagger", 0.5],
		[ZombieBody.Mode.EMERGING, &"Boss_Roar", 1.2],
	]:
		var body := _body(&"headliner", case[0])
		_check(_grid(probe, body, case[1], case[2]), &"headliner", "headliner %s" % case[1])
	probe.free_model()


func test_a_shot_at_a_crawlers_forehead_is_a_headshot_in_every_crawl_frame() -> void:
	var probe := ZombieMeshProbe.make(self, &"crawler")
	var body := _body(&"crawler", ZombieBody.Mode.CHASE)
	var shooter := _shooter(body)
	var eye := Vector3(0.0, 1.55, 5.0)
	var aimed := 0
	var headshots := 0
	for time in CRAWL_TIMES:
		probe.pose(&"Crawl", time)
		for point in probe.forehead(12):
			var dir := (point - eye).normalized()
			var seen := probe.ray(eye, dir)
			if seen.is_empty() or seen["part"] != ZombieMeshProbe.Part.HEAD:
				continue
			aimed += 1
			if shooter.call(eye, dir) == Hitbox.HEAD:
				headshots += 1
	assert_int(aimed).is_greater(30)
	(
		assert_float(float(headshots) / float(aimed))
		. override_failure_message(
			"%d of %d shots at the forehead were headshots" % [headshots, aimed]
		)
		. is_greater_equal(0.98)
	)
	probe.free_model()
