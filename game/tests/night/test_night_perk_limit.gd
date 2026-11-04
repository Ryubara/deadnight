# The perk limit setting (#913) in the real night: at every perk machine the fifth perk is refused
# on Default ("YOU CARRY 4 TONICS, THE MOST") and sold on Unlimited, through the same `use` press
# every shop prompt takes; the frame's perk bits and the HUD's badges show all of them, and the
# bots' shop reads the same limit. The rules' own checks are `tests/rules/test_perk_limit.gd`.
extends GdUnitTestSuite

var _night: Night


func after_test() -> void:
	if is_instance_valid(_night):
		_night.queue_free()


func _start(unlimited: bool, bots := 0) -> Night:
	_night = Night.new()
	_night.match_settings = MatchSettings.new()
	if unlimited:
		_night.match_settings.perk_limit = MatchSettings.PERKS_UNLIMITED
	_night.match_settings.bots = bots
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7)
	NightFixture.run(_night, 5)
	_night.server.rules.apply(RulesAction.grant_points(1, 50000))
	NightFixture.run(_night, 2)
	return _night


func _spot(night: Night, item: StringName) -> Vector3:
	for spot in night.world.shop_spots():
		if spot["shop_id"] == item:
			return spot["position"]
	return Vector3.INF


func _stand_at(night: Night, item: StringName) -> Dictionary:
	night.player().teleport(_spot(night, item) + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 3)
	return night.state.me()["prompt"]


func _press_use(night: Night) -> void:
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 3)


## Walks to the machine of `item`, presses use and returns the prompt it showed before.
func _buy_at_machine(night: Night, item: StringName) -> Dictionary:
	var prompt := _stand_at(night, item)
	if prompt.get("kind", &"") == &"tonic":
		_press_use(night)
	return prompt


func _perks_of(night: Night) -> int:
	return night.server.rules.players[1].tonics.size()


func test_on_default_the_fifth_machine_says_the_limit_and_sells_nothing() -> void:
	var night := await _start(false)
	var ids := PerkEffects.tonic_ids(night.server.rules.tuning.economy)
	var limit := night.server.rules.tuning.economy.max_tonics
	for i in limit:
		assert_str(String(_buy_at_machine(night, ids[i])["kind"])).is_equal("tonic")
	assert_int(_perks_of(night)).is_equal(limit)
	var prompt := _stand_at(night, ids[limit])
	assert_str(String(prompt["kind"])).is_equal("tonic_full")
	assert_int(int(prompt["limit"])).is_equal(limit)
	var points := night.state.points()
	_press_use(night)
	assert_int(night.state.points()).is_equal(points)
	assert_int(_perks_of(night)).is_equal(limit)


func test_on_unlimited_every_machine_sells_and_the_frame_and_badges_show_all_six() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	_night = Night.new()
	_night.hud = hud
	_night.match_settings = MatchSettings.new()
	_night.match_settings.perk_limit = MatchSettings.PERKS_UNLIMITED
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7)
	NightFixture.run(_night, 5)
	_night.server.rules.apply(RulesAction.grant_points(1, 50000))
	NightFixture.run(_night, 2)
	var ids := PerkEffects.tonic_ids(_night.server.rules.tuning.economy)
	for id in ids:
		var prompt := _buy_at_machine(_night, id)
		assert_str(String(prompt["kind"])).override_failure_message(String(id)).is_equal("tonic")
	assert_int(_perks_of(_night)).is_equal(ids.size())
	NightFixture.run(_night, 3)
	var mask := int(_night.state.me()["perks"])
	assert_int(PerkEffects.mask_count(mask)).is_equal(ids.size())
	# Every machine now says the perk was had, not the limit.
	assert_str(String(_stand_at(_night, ids[0])["kind"])).is_equal("tonic_owned")
	assert_int(hud.perks.get_child_count()).is_greater_equal(ids.size())
	hud.queue_free()


func test_the_bots_shop_reads_the_nights_limit() -> void:
	var usual := await _start(false, 1)
	var economy := usual.server.rules.tuning.economy
	assert_int(usual.bots.level.shop.tonic_limit()).is_equal(economy.max_tonics)
	usual.queue_free()
	await get_tree().process_frame
	var lifted := await _start(true, 1)
	assert_int(lifted.bots.level.shop.tonic_limit()).is_equal(MatchSettings.UNLIMITED_PERKS)
