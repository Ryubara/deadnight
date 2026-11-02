# The zombie types in the real night: each type spawns with its own look, hits for its own damage
# after its own windup with its own knockback, and is shot at in hit zones of its own size. A round
# of only one type (a special round) is how a night shows one type at once.
extends GdUnitTestSuite

const WALKER_WINDUP := 0.45
## The simulation steps by 1/30 s: a blow lands within a step or so of its windup.
const STEP_SLACK := 0.05


## Starts a night of round 1 holding only `type_id`; returns {night, id, events}.
func _meet(type_id: StringName, tuning: RulesTuning = null) -> Dictionary:
	var night := await NightFixture.start(
		self, Night.Mode.MANUAL, tuning if tuning != null else NightFixture.only_tuning(type_id)
	)
	var events: Array[Dictionary] = []
	night.state.event_received.connect(func(e: Dictionary) -> void: events.append(e))
	NightFixture.run(night, 5)
	var zombie_id := NightFixture.first_of_type(night, type_id)
	NightFixture.run(night, 3)
	return {"night": night, "id": zombie_id, "events": events}


## Holds zombie `zombie_id` next to the player until it lands a blow; returns the blow the server
## reported and how far into its swing the zombie was.
func _blow(night: Night, zombie_id: int, events: Array[Dictionary]) -> Dictionary:
	var body: ZombieBody = night.server.sim.zombies[zombie_id]
	var into_swing := []
	night.server.director.player_struck.connect(
		func(_p: int, z: int, _d: float) -> void:
			if z == zombie_id:
				into_swing.append(night.server.sim.zombies[z].mode_time)
	)
	body.enter(ZombieBody.Mode.CHASE)
	for _i in 600:
		body.position = night.state.position() + Vector3(0.0, 0.0, 1.0)
		body.velocity = Vector3.ZERO
		NightFixture.run(night, 1)
		if not into_swing.is_empty():
			break
	NightFixture.run(night, 2)
	for event in events:
		if event["type"] == &"player_damaged" and event["zombie_id"] == zombie_id:
			return {"event": event, "into_swing": into_swing[0]}
	return {}


func _expect_type(type_id: StringName) -> void:
	var met := await _meet(type_id)
	var night: Night = met["night"]
	var zombie_id: int = met["id"]
	assert_int(zombie_id).is_greater(0)
	var type := night.server.rules.tuning.roster.type_of(type_id)
	var body: ZombieBody = night.server.sim.zombies[zombie_id]
	# What the rules decided is what the zombie is.
	assert_str(String(body.profile.type)).is_equal(String(type_id))
	assert_bool(body.profile.look in type.looks).is_true()
	assert_float(body.profile.damage).is_equal(type.damage)
	assert_float(body.profile.knockback).is_equal(type.knockback)
	# It is drawn in that look.
	var view := night.view.horde.view_of(zombie_id)
	assert_object(view).is_not_null()
	assert_str(String(view.look)).is_equal(String(body.profile.look))
	assert_str(view.model().scene_file_path).ends_with("zombie_%s.glb" % body.profile.look)
	# Its blow takes its damage after its windup and carries its knockback.
	var windup := type.telegraph_seconds if type.telegraph_seconds > 0.0 else WALKER_WINDUP
	var blow := _blow(night, zombie_id, met["events"])
	assert_bool(blow.is_empty()).is_false()
	assert_float(blow["event"]["damage"]).is_equal(type.damage)
	assert_float(blow["event"]["knockback"]).is_equal(type.knockback)
	assert_str(String(blow["event"]["zombie_type"])).is_equal(String(type_id))
	assert_float(blow["into_swing"]).is_between(windup, windup + STEP_SLACK)
	night.queue_free()


func test_a_walker_hits_for_the_rules_damage_not_a_flat_twenty() -> void:
	await _expect_type(&"walker")
	var tuning := RulesFixture.tuning()
	assert_float(tuning.roster.type_of(&"walker").damage).is_not_equal(20.0)


func test_a_runner_is_drawn_as_a_runner_and_hits_for_its_damage() -> void:
	await _expect_type(&"runner")


func test_a_brute_is_drawn_as_a_brute_and_hits_hard_and_throws_back() -> void:
	await _expect_type(&"brute")
	assert_float(RulesFixture.tuning().roster.type_of(&"brute").knockback).is_greater(0.0)


func test_a_crawler_is_drawn_as_a_crawler() -> void:
	await _expect_type(&"crawler")


func test_a_crawler_crawls_and_a_walker_walks() -> void:
	var met := await _meet(&"crawler")
	var night: Night = met["night"]
	var crawler := night.server.sim.zombies[met["id"]] as ZombieBody
	crawler.enter(ZombieBody.Mode.CHASE)
	NightFixture.run(night, 3)
	var view := night.view.horde.view_of(met["id"])
	view.advance_animation()
	var playback: AnimationNodeStateMachinePlayback = view.tree.get(ZombieRig.PLAYBACK_PARAMETER)
	assert_str(String(playback.get_current_node())).is_equal(String(ZombieRig.STATE_CRAWL))
	night.queue_free()


func test_the_headliner_hits_for_forty_after_its_telegraph() -> void:
	var met := await _meet(&"headliner", NightFixture.boss_tuning())
	var night: Night = met["night"]
	var zombie_id: int = met["id"]
	assert_int(zombie_id).is_greater(0)
	var type := night.server.rules.tuning.roster.type_of(&"headliner")
	assert_float(type.damage).is_equal(40.0)
	var blow := _blow(night, zombie_id, met["events"])
	assert_bool(blow.is_empty()).is_false()
	assert_float(blow["event"]["damage"]).is_equal(40.0)
	assert_float(blow["event"]["knockback"]).is_equal(4.0)
	# Not after the walker's 0.45 s: after the 1.2 s the player is shown it coming.
	assert_float(blow["into_swing"]).is_between(1.2, 1.2 + STEP_SLACK)
	var full := night.server.rules.tuning.health.max_health
	assert_float(night.server.health_of(1)).is_equal(full - 40.0)
	night.queue_free()


func test_a_boss_night_brings_the_headliner_among_its_escorts() -> void:
	var met := await _meet(&"headliner", NightFixture.boss_tuning())
	var night: Night = met["night"]
	NightFixture.run(night, 600)
	var types := {}
	for event: Dictionary in met["events"]:
		if event["type"] == &"zombie_spawn_requested":
			types[event["zombie_type"]] = true
	assert_bool(types.has(&"headliner")).is_true()
	assert_bool(types.has(&"walker")).is_true()
	# The headliner is drawn in the Projectionist's model.
	var view := night.view.horde.view_of(met["id"])
	assert_str(String(view.look)).is_equal("headliner")
	assert_str(view.model().scene_file_path).ends_with("zombie_boss.glb")
	var special := night.server.rules.special_id()
	assert_bool(special != &"").is_true()
	night.queue_free()


## A crawler is low: a shot over its back misses it, a shot at its body hits, and a walker standing
## in the same place is hit by the high one.
func test_a_crawlers_hit_zones_are_lower_and_smaller() -> void:
	var crawler := await _meet(&"crawler")
	var crawler_night: Night = crawler["night"]
	var high := _shoot_at_height(crawler_night, crawler["id"], 1.3)
	var low := _shoot_at_height(crawler_night, crawler["id"], 0.6)
	assert_bool(high).is_false()
	assert_bool(low).is_true()
	crawler_night.queue_free()
	var walker := await _meet(&"walker")
	var walker_night: Night = walker["night"]
	assert_bool(_shoot_at_height(walker_night, walker["id"], 1.3)).is_true()
	walker_night.queue_free()


## Fires the player's pistol at height `height` over a zombie held six metres off; whether the
## server reported a hit on it.
func _shoot_at_height(night: Night, zombie_id: int, height: float) -> bool:
	var body: ZombieBody = night.server.sim.zombies[zombie_id]
	var spot := night.state.position() + Vector3(0.0, 0.0, -6.0)
	var heard := []
	night.state.event_received.connect(
		func(e: Dictionary) -> void:
			if e["type"] == &"damage_dealt" and e["target_id"] == zombie_id:
				heard.append(e)
	)
	var eye := night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	var command := NightCommand.new()
	command.origin = eye
	command.aim_along(spot + Vector3(0.0, height, 0.0) - eye)
	command.fire = true
	for _i in 4:
		body.enter(ZombieBody.Mode.CHASE)
		body.position = spot
		body.velocity = Vector3.ZERO
		NightFixture.run(night, 20, command)
	NightFixture.run(night, 3)
	return not heard.is_empty()
