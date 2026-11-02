# The headliner in the real night: its weak spot is a hit zone the weapons reach, it pays the rules'
# multiplier and staggers the boss, and its health shows on the HUD's boss bar.
extends GdUnitTestSuite

## Metres between the player and the held boss.
const RANGE := 6.0


## A boss night in round 1; returns {night, id, events}. The boss is on the lot and standing.
func _boss_night(hud: Hud = null) -> Dictionary:
	var night := await NightFixture.start(
		self, Night.Mode.MANUAL, NightFixture.boss_tuning(), 7, hud
	)
	var events: Array[Dictionary] = []
	night.state.event_received.connect(func(e: Dictionary) -> void: events.append(e))
	NightFixture.run(night, 5)
	var boss_id := NightFixture.first_of_type(night, &"headliner")
	NightFixture.run(night, 3)
	var body: ZombieBody = night.server.sim.zombies[boss_id]
	body.enter(ZombieBody.Mode.CHASE)
	return {"night": night, "id": boss_id, "events": events}


## Holds the boss `RANGE` metres in front of the player, facing them, and fires four shots at the
## point `height` metres up and `forward` metres ahead of its feet (in its own frame).
func _shoot_boss(night: Night, boss_id: int, height: float, forward: float) -> void:
	var body: ZombieBody = night.server.sim.zombies[boss_id]
	var command := _aim_at(night, height, forward)
	for _i in 4:
		_hold(night, body)
		NightFixture.run(night, 12, command)
	NightFixture.run(night, 3)


## Where the boss is held: in front of the player, facing them.
func _hold(night: Night, body: ZombieBody) -> void:
	body.position = night.state.position() + Vector3(0.0, 0.0, -RANGE)
	body.yaw = 0.0
	body.velocity = Vector3.ZERO


## A held trigger at the point `height` up and `forward` ahead of the held boss's feet.
func _aim_at(night: Night, height: float, forward: float) -> NightCommand:
	var aim := night.state.position() + Vector3(0.0, height, forward - RANGE)
	var eye := night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	var command := NightCommand.new()
	command.origin = eye
	command.aim_along(aim - eye)
	command.fire = true
	return command


func _of(events: Array[Dictionary], type: StringName, boss_id: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in events:
		if event["type"] == type and event.get("target_id", event.get("zombie_id", -1)) == boss_id:
			found.append(event)
	return found


func test_the_boss_is_shot_at_through_a_weak_zone() -> void:
	var met := await _boss_night()
	var night: Night = met["night"]
	var profile: ZombieProfile = night.server.sim.zombies[met["id"]].profile
	assert_bool(profile.weak).is_true()
	var lamp := Hitbox.WEAK_ZONE["a"] as Vector3
	var scale := profile.hit_scale()
	_shoot_boss(night, met["id"], lamp.y * scale, lamp.z * scale)
	var hits := _of(met["events"], &"damage_dealt", met["id"])
	assert_bool(hits.is_empty()).is_false()
	assert_str(String(hits[0]["zone"])).is_equal("weak")
	night.queue_free()


func test_a_shot_at_its_knees_is_a_body_hit() -> void:
	var met := await _boss_night()
	var night: Night = met["night"]
	var scale: float = night.server.sim.zombies[met["id"]].profile.hit_scale()
	# Its knees: well below the lamp.
	_shoot_boss(night, met["id"], 0.5 * scale, 0.0)
	var hits := _of(met["events"], &"damage_dealt", met["id"])
	assert_bool(hits.is_empty()).is_false()
	for hit in hits:
		assert_str(String(hit["zone"])).is_not_equal("weak")
	night.queue_free()


func test_a_weak_spot_hit_pays_the_rules_multiplier_and_staggers_the_boss() -> void:
	var met := await _boss_night()
	var night: Night = met["night"]
	var profile: ZombieProfile = night.server.sim.zombies[met["id"]].profile
	var lamp := Hitbox.WEAK_ZONE["a"] as Vector3
	var multiplier := night.server.rules.tuning.roster.type_of(&"headliner").weak_multiplier
	var staggered := false
	var body: ZombieBody = night.server.sim.zombies[met["id"]]
	var command := _aim_at(night, lamp.y * profile.hit_scale(), lamp.z * profile.hit_scale())
	for _i in 60:
		_hold(night, body)
		NightFixture.run(night, 1, command)
		staggered = staggered or body.mode == ZombieBody.Mode.STAGGER
		if staggered:
			break
	NightFixture.run(night, 3)
	assert_bool(staggered).is_true()
	var damaged := _of(met["events"], &"zombie_damaged", met["id"])
	var weak_hits := damaged.filter(
		func(e: Dictionary) -> bool: return e["zone"] == RulesAction.ZONE_WEAK
	)
	assert_bool(weak_hits.is_empty()).is_false()
	# The weapon's own damage (a pistol, no zone multiplier for the lamp) times the type's.
	var dealt := _of(met["events"], &"damage_dealt", met["id"])
	assert_float(weak_hits[0]["damage"]).is_equal_approx(dealt[0]["damage"] * multiplier, 0.01)
	night.queue_free()


func test_the_boss_bar_follows_its_health_and_goes_with_it() -> void:
	var host := auto_free(Control.new()) as Control
	host.size = Vector2(1920, 1080)
	add_child(host)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	host.add_child(hud)
	var met := await _boss_night(hud)
	var night: Night = met["night"]
	NightFixture.run(night, 3)
	assert_bool(hud.boss_bar.visible).is_true()
	assert_float(hud.boss_bar.fractions[0]).is_equal(1.0)
	var before: float = hud.state.bosses[0]["health"]
	var lamp := Hitbox.WEAK_ZONE["a"] as Vector3
	var scale: float = night.server.sim.zombies[met["id"]].profile.hit_scale()
	_shoot_boss(night, met["id"], lamp.y * scale, lamp.z * scale)
	assert_float(hud.state.bosses[0]["health"]).is_less(before)
	assert_float(hud.boss_bar.fractions[0]).is_less(1.0)
	var kill := RulesAction.hit(1, met["id"], RulesAction.ZONE_BODY, RulesFixture.KILLING_DAMAGE)
	night.state.apply_events(night.server.rules.apply(kill))
	assert_bool(hud.boss_bar.visible).is_false()
	night.queue_free()


func test_the_marquee_and_the_banner_follow_the_real_night_into_its_special_round() -> void:
	var host := auto_free(Control.new()) as Control
	host.size = Vector2(1920, 1080)
	add_child(host)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	host.add_child(hud)
	var night := await NightFixture.start(
		self, Night.Mode.MANUAL, NightFixture.boss_tuning(), 7, hud
	)
	NightFixture.run(night, 5)
	# The intro break before round 1 is the announcement: the marquee is up and says what comes.
	assert_bool(hud.marquee.visible).is_true()
	assert_str(hud.marquee.title_text).is_equal("DOUBLE FEATURE")
	assert_str(hud.marquee.detail_text).is_equal("THE HEADLINER ARRIVES")
	night.state.apply_events(night.server.rules.apply(RulesAction.skip_break()))
	NightFixture.run(night, 5)
	assert_bool(hud.marquee.visible).is_false()
	assert_str(String(hud.state.special_id)).is_equal("double_feature")
	assert_str(hud.banner.title).is_equal("DOUBLE FEATURE")
	night.queue_free()
