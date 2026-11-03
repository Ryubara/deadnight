# The night loads the map the match settings name from the registry (#624), tested with a stub
# second map: the world is built from that map's scene, a solo night under settings that name it
# runs on it, and a map that cannot be played is never loaded (the lot is, so a night never fails to
# start for an id nobody knows).
extends GdUnitTestSuite


func after_test() -> void:
	StubMaps.remove()


func _world(info: MapInfo) -> NightWorld:
	var world := NightWorld.new()
	add_child(world)
	await world.build(info)
	return world


func test_a_world_built_with_no_map_is_the_drive_in_lot() -> void:
	var world := await _world(null)
	assert_str(world.map_info.id).is_equal(MapRegistry.DEFAULT)
	assert_bool(StubMaps.built_from_stub(world)).is_false()
	assert_str(world.greybox.scene_file_path).is_equal(MapRegistry.default_map().scene_path)
	world.queue_free()


func test_a_world_is_built_from_the_scene_of_the_map_it_is_given() -> void:
	var stub := StubMaps.install()
	var world := await _world(stub)
	assert_str(world.map_info.id).is_equal(StubMaps.ID)
	assert_bool(StubMaps.built_from_stub(world)).is_true()
	# It is the lot's own layout, so the night's parts all find what they look for.
	assert_object(world.doors).is_not_null()
	assert_int(world.door_ids().size()).is_greater(0)
	world.queue_free()


func test_a_map_that_is_not_built_is_never_loaded() -> void:
	var stub := StubMaps.install(false)
	var world := await _world(stub)
	assert_str(world.map_info.id).is_equal(MapRegistry.DEFAULT)
	assert_bool(StubMaps.built_from_stub(world)).is_false()
	world.queue_free()


func test_a_solo_night_runs_on_the_map_its_settings_name() -> void:
	StubMaps.install()
	var night := Night.new()
	night.match_settings = MatchSettings.new()
	night.match_settings.map = StubMaps.ID
	add_child(night)
	await night.start(Night.Mode.MANUAL, 7)
	assert_bool(StubMaps.built_from_stub(night.world)).is_true()
	assert_str(night.world.map_info.id).is_equal(StubMaps.ID)
	# The rules of the night carry the choice, so the HUD, the snapshot and a late join read it.
	assert_str(night.server.rules.settings.map).is_equal(StubMaps.ID)
	assert_str(MatchSettings.from_snapshot(night.server.rules.to_dict()).map).is_equal(StubMaps.ID)
	NightFixture.run(night, 5)
	assert_int(night.state.phase()).is_equal(GameRules.Phase.BREAK)
	night.queue_free()


func test_a_solo_night_with_the_usual_settings_is_on_the_lot() -> void:
	StubMaps.install()
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	assert_bool(StubMaps.built_from_stub(night.world)).is_false()
	assert_str(night.world.map_info.id).is_equal(MapRegistry.DEFAULT)
	night.queue_free()


func test_the_second_map_is_built_from_its_scene_and_runs_a_night() -> void:
	var info := MapRegistry.of("small_indoor")
	assert_str(info.id).is_equal("small_indoor")
	var world := await _world(info)
	assert_str(world.map_info.id).is_equal("small_indoor")
	assert_str(world.greybox.scene_file_path).is_equal(info.scene_path)
	assert_object(world.doors).is_not_null()
	assert_int(world.door_ids().size()).is_equal(3)
	world.queue_free()
	var night := Night.new()
	night.match_settings = MatchSettings.new()
	night.match_settings.map = "small_indoor"
	add_child(night)
	await night.start(Night.Mode.MANUAL, 7)
	assert_str(night.world.map_info.id).is_equal("small_indoor")
	assert_str(night.server.rules.settings.map).is_equal("small_indoor")
	assert_str(MatchSettings.from_snapshot(night.server.rules.to_dict()).map).is_equal(
		"small_indoor"
	)
	NightFixture.run(night, 5)
	assert_int(night.state.phase()).is_equal(GameRules.Phase.BREAK)
	night.queue_free()
