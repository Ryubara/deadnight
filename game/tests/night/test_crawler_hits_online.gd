extends GdUnitTestSuite
## Shots at a crawler through the server's own hit check (#694): the combat server's trace over
## the targets a night sends it, with a crawler's forehead aimed at in the frames of its crawl,
## from behind the lag the server rewinds by, and in a real night where the server builds the target
## from the zombie it holds.

const SHOOTER := Vector3(0.0, 1.55, 6.0)
const CRAWL_TIMES: Array[float] = [0.0, 0.42, 0.83, 1.25]
## Forehead points shot at per crawl frame.
const POINTS := 3

## A crawler as the night sends it to the combat server.
const CRAWLER := {
	"id": 1, "pos": Vector3.ZERO, "yaw": 0.0, "scale": 1.0, "weak": false, "pose": &"crawler.move"
}


func _server_with(target: Dictionary) -> CombatServer:
	var server := WeaponsFixture.make_server()
	server.apply(CombatAction.give_weapon(1, &"pistol"))
	server.apply(CombatAction.targets([target]))
	server.apply(CombatAction.tick(WeaponsFixture.STEP))
	return server


func _fire(server: CombatServer, to: Vector3, view_time: float = 0.0) -> Array[Dictionary]:
	return server.apply(WeaponsFixture.fire_at(1, 1, SHOOTER, to, view_time))


## The first damage a shot did: its `damage_dealt` event, or an empty dictionary.
func _damage(events: Array[Dictionary]) -> Dictionary:
	var dealt := WeaponsFixture.of(events, &"damage_dealt")
	return dealt[0] if not dealt.is_empty() else {}


func test_the_server_counts_a_shot_at_a_crawlers_forehead_as_a_headshot_in_every_crawl_frame(
) -> void:
	var probe := ZombieMeshProbe.make(self, &"crawler")
	var shots := 0
	for time in CRAWL_TIMES:
		probe.pose(&"Crawl", time)
		var forehead := probe.forehead(POINTS * 4)
		for index in range(0, forehead.size(), forehead.size() / POINTS):
			var point := forehead[index]
			var server := _server_with(CRAWLER)
			var dir := (point - SHOOTER).normalized()
			var seen := probe.ray(SHOOTER, dir)
			if seen.is_empty() or seen["part"] != ZombieMeshProbe.Part.HEAD:
				continue
			shots += 1
			var hit := _damage(_fire(server, point))
			(
				assert_bool(hit.is_empty())
				. override_failure_message(
					"the shot at %s (crawl %.2f s) did no damage" % [point, time]
				)
				. is_false()
			)
			(
				assert_bool(hit["headshot"])
				. override_failure_message(
					"the shot at %s (crawl %.2f s) was a %s hit" % [point, time, hit["zone"]]
				)
				. is_true()
			)
	assert_int(shots).is_greater(6)
	probe.free_model()


func test_the_server_counts_a_shot_at_a_crawler_seen_from_the_side_and_turned_about() -> void:
	var probe := ZombieMeshProbe.make(self, &"crawler")
	probe.pose(&"Crawl", 0.42)
	for yaw in [PI * 0.5, PI, -PI * 0.5]:
		var basis := Basis(Vector3.UP, yaw)
		var target := CRAWLER.duplicate()
		target["yaw"] = yaw
		var point := basis * probe.forehead(12)[5]
		var server := _server_with(target)
		var from := Vector3(0.0, 1.55, 0.0) + basis * Vector3(0.0, 0.0, 6.0)
		var dir := (point - from).normalized()
		var hit := _damage(server.apply(WeaponsFixture.fire_at(1, 1, from, point)))
		(
			assert_bool(hit.is_empty())
			. override_failure_message("a shot at yaw %.2f missed" % yaw)
			. is_false()
		)
		assert_str(String(hit["zone"])).is_equal("head")
		assert_float(dir.length()).is_equal_approx(1.0, 0.001)
	probe.free_model()


func test_a_shot_from_behind_the_lag_hits_where_the_crawler_was_in_its_own_pose() -> void:
	var probe := ZombieMeshProbe.make(self, &"crawler")
	probe.pose(&"Crawl", 0.0)
	var point := probe.forehead(12)[6]
	var server := _server_with(CRAWLER)
	# Held where it was for six ticks, then it crawls a metre away in four more.
	for _i in 6:
		server.apply(CombatAction.targets([CRAWLER]))
		server.apply(CombatAction.tick(WeaponsFixture.STEP))
	var seen_at: float = server.now
	var moved := CRAWLER.duplicate()
	for i in 4:
		moved["pos"] = Vector3(0.0, 0.0, -0.25 * float(i + 1))
		server.apply(CombatAction.targets([moved]))
		server.apply(CombatAction.tick(WeaponsFixture.STEP))
	var hit := _damage(_fire(server, point, seen_at))
	assert_bool(hit.is_empty()).is_false()
	assert_str(String(hit["zone"])).is_equal("head")
	probe.free_model()


func test_a_crawler_in_the_real_night_is_hit_on_the_forehead() -> void:
	var night := await NightFixture.start(
		self, Night.Mode.MANUAL, NightFixture.only_tuning(&"crawler"), 7
	)
	var events: Array[Dictionary] = []
	night.state.event_received.connect(func(e: Dictionary) -> void: events.append(e))
	NightFixture.run(night, 5)
	var id := NightFixture.first_of_type(night, &"crawler")
	assert_int(id).is_greater_equal(0)
	NightFixture.run(night, 3)
	var body: ZombieBody = night.server.sim.zombies[id]
	body.enter(ZombieBody.Mode.CHASE)
	# What the server shoots at is built from the zombie it holds.
	assert_str(String(body.hit_target()["pose"])).is_equal("crawler.move")
	var probe := ZombieMeshProbe.make(self, &"crawler")
	probe.pose(&"Crawl", 0.42)
	var point := probe.forehead(12)[5]
	var eye := night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	var held := night.state.position() + Vector3(0.0, 0.0, -5.0)
	var command := NightCommand.new()
	command.origin = eye
	command.aim_along(held + point - eye)
	command.fire = true
	for _i in 4:
		body.position = held
		body.yaw = 0.0
		body.velocity = Vector3.ZERO
		NightFixture.run(night, 12, command)
	var zones: Array[String] = []
	for event in events:
		if event["type"] == &"damage_dealt" and event.get("target_id", -1) == id:
			zones.append(String(event["zone"]))
	assert_array(zones).is_not_empty()
	assert_str(zones[0]).is_equal("head")
	probe.free_model()
	night.queue_free()
