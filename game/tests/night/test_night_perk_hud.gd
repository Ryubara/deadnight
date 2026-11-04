# The perk badges and the DOWN card in the real night (#707): a drink bought at its machine with the
# same press of use as a door puts its badge beside the health card, a down that takes the perks
# takes the badges, and the revive perk getting its holder up alone shows on the card and the ring.
# Everything reaches the HUD through the frame the client hears (`NightHudBinding`), a tick of
# 1/60 s.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60


func _start() -> Dictionary:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	var tuning := RulesFixture.tuning()
	# Nothing spawns while a test talks about the card.
	tuning.rounds.first_spawn_delay = 6000.0
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning, 7, hud)
	NightFixture.run(night, 5)
	night.server.rules.apply(RulesAction.grant_points(1, 30000))
	night.server.rules.apply(RulesAction.skip_break())
	NightFixture.run(night, 3)
	return {"night": night, "hud": hud}


func _finish(night: Night, hud: Hud) -> void:
	night.queue_free()
	hud.queue_free()
	await get_tree().process_frame


func _spot(night: Night, item: StringName) -> Vector3:
	for spot in night.world.shop_spots():
		if spot["shop_id"] == item:
			return spot["position"]
	return Vector3.INF


## Walks to the machine of `item` and presses use, as a player does.
func _drink(night: Night, item: StringName) -> void:
	night.player().teleport(_spot(night, item) + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 3)
	var press := NightCommand.new()
	press.use = true
	NightFixture.run(night, 1, press)
	NightFixture.run(night, 3)
	NightFixture.drink_down(night)  # the perk is had, and its badge shows, when the drink ends (#912)


## Takes the local player down with one blow, as the zombies would.
func _down(night: Night) -> void:
	night.state.apply_events(night.server.rules.apply(RulesAction.blow(1, 9999.0)))
	NightFixture.run(night, 3)


func test_a_drink_bought_at_its_machine_puts_its_badge_beside_the_health_card() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	assert_array(hud.perks.shown()).is_empty()
	assert_bool(hud.perks.visible).is_false()
	var bought: Array[StringName] = []
	for id: StringName in [&"tonic_double_shot", &"tonic_swift_rescue", &"tonic_quick_load"]:
		_drink(night, id)
		bought.append(id)
		# In the shop's order, whatever the order of the purchases.
		var wanted := PerkEffects.tonic_ids(night.server.rules.tuning.economy).filter(
			func(tonic: StringName) -> bool: return bought.has(tonic)
		)
		assert_array(hud.perks.shown()).is_equal(wanted)
	assert_bool(hud.perks.visible).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	var card := hud.health.get_global_rect()
	var badges := hud.perks.get_global_rect()
	assert_float(badges.position.x).is_greater(card.end.x)
	assert_float(badges.end.y).is_equal_approx(card.end.y, 1.0)
	await _finish(night, hud)


func test_a_down_with_a_teammate_on_their_feet_takes_the_badges_and_the_card_bleeds_out() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	night.server.apply({"type": NightServer.JOIN, "player_id": 2, "local": false})
	NightFixture.run(night, 3)
	_drink(night, &"tonic_double_shot")
	_drink(night, &"tonic_quick_load")
	assert_array(hud.perks.shown()).has_size(2)
	_down(night)
	var left := night.server.rules.players[1].tonics
	# The badges are what the server says is still had, whether it takes all, the last or none.
	assert_array(hud.perks.shown()).has_size(left.size())
	assert_int(PerkEffects.mask_count(int(night.state.me()["perks"]))).is_equal(left.size())
	assert_bool(hud.state.is_local_self_reviving()).is_false()
	assert_str(hud.health.hint_text).starts_with("BLEEDING OUT")
	assert_int(hud.revive.mode).is_equal(HudRevive.Mode.DOWNED)
	await _finish(night, hud)


func test_alone_with_the_revive_perk_the_card_counts_the_self_revive_and_the_badges_stay() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	var rules := night.server.rules
	_drink(night, &"tonic_swift_rescue")
	_drink(night, &"tonic_double_shot")
	assert_array(hud.perks.shown()).has_size(2)
	_down(night)
	assert_bool(hud.state.is_local_downed()).is_true()
	assert_bool(hud.state.is_local_self_reviving()).is_true()
	assert_str(hud.health.down_text).is_equal("DOWN")
	assert_str(hud.health.hint_text).starts_with("GETTING YOURSELF UP")
	assert_int(hud.revive.mode).is_equal(HudRevive.Mode.SELF_REVIVING)
	# It counts down with the server's own seconds, and the bleed-out clock stays where it was.
	var bleed := float(hud.state.team[1]["bleed"])
	var seen: Array[String] = []
	for _step in 5:
		NightFixture.run(night, TICKS_PER_SECOND)
		if not hud.state.is_local_self_reviving():
			break
		var said := "GETTING YOURSELF UP  %d S" % ceili(rules.players[1].self_revive_left)
		assert_str(hud.health.hint_text).is_equal(said)
		seen.append(said)
		assert_float(float(hud.state.team[1]["bleed"])).is_equal_approx(bleed, 0.001)
	assert_int(seen.size()).is_greater(1)
	assert_bool(seen[0] != seen[seen.size() - 1]).is_true()
	# Up again: the card is the plain health card, the perks are still shown.
	NightFixture.run(night, 6 * TICKS_PER_SECOND)
	assert_bool(rules.players[1].downed).is_false()
	assert_bool(hud.state.is_local_downed()).is_false()
	assert_bool(hud.health.shown_downed).is_false()
	assert_int(hud.revive.mode).is_equal(HudRevive.Mode.NONE)
	assert_array(hud.perks.shown()).has_size(2)
	await _finish(night, hud)


func test_the_self_revive_runs_out_with_its_uses_and_the_card_goes_back_to_bleeding_out() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	var rules := night.server.rules
	_drink(night, &"tonic_swift_rescue")
	rules.players[1].self_revives = rules.tuning.perks.self_revive_uses
	_down(night)
	assert_bool(hud.state.is_local_self_reviving()).is_false()
	assert_str(hud.health.hint_text).starts_with("BLEEDING OUT")
	await _finish(night, hud)
