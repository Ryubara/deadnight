# The map registry and the map choice in the match settings (#624): the drive-in lot and the small
# indoor map (#792) are shipped, an id nobody knows or a map that is listed and not built falls
# back to the lot, the choice rides the settings dictionary every road carries (snapshot, ticket,
# lobby) and a settings dictionary from before the choice still reads. A stub map stands for one
# that is not built.
extends GdUnitTestSuite


func after_test() -> void:
	StubMaps.remove()


func test_the_drive_in_lot_and_the_small_indoor_map_are_the_shipped_maps() -> void:
	var ids: Array[String] = []
	for info in MapRegistry.playable():
		ids.append(info.id)
	assert_array(ids).contains_exactly(["drive_in", "small_indoor"])
	assert_str(MapRegistry.DEFAULT).is_equal("drive_in")
	var lot := MapRegistry.default_map()
	assert_bool(lot.is_playable()).is_true()
	assert_object(lot.load_scene()).is_not_null()
	assert_object(lot.preview()).is_not_null()
	assert_int(lot.min_players).is_equal(1)
	assert_int(lot.max_players).is_equal(NightHost.MAX_PLAYERS)


func test_the_small_indoor_map_is_shipped_and_playable() -> void:
	var small := MapRegistry.find("small_indoor")
	assert_object(small).is_not_null()
	assert_bool(small.shipped).is_true()
	assert_bool(small.is_playable()).is_true()
	assert_str(small.scene_path).is_equal("res://world/smallmap/smallmap_greybox.tscn")
	assert_object(small.load_scene()).is_not_null()
	assert_object(small.preview()).is_not_null()
	# The card shows what the design says of it: about 600 square metres, as many seats as the lot.
	assert_str(small.size_text()).is_equal("600 m²")
	assert_str(small.players_text()).is_equal("1 to 8 players")
	assert_int(small.max_players).is_equal(NightHost.MAX_PLAYERS)
	assert_bool(MapRegistry.is_playable("small_indoor")).is_true()
	assert_str(MapRegistry.of("small_indoor").id).is_equal("small_indoor")
	var settings := MatchSettings.new()
	settings.map = "small_indoor"
	assert_str(String(MatchSettings.problem(settings.to_dict()))).is_equal("")
	assert_str(settings.clamped().map).is_equal("small_indoor")
	# Listed after the lot, as the picker shows them.
	assert_str(MapRegistry.all()[0].id).is_equal("drive_in")
	assert_str(MapRegistry.all()[1].id).is_equal("small_indoor")


func test_every_map_has_a_name_a_size_and_a_scene_or_a_lock() -> void:
	for info in MapRegistry.all():
		assert_str(info.title).is_not_empty()
		assert_str(info.id).is_not_empty()
		assert_int(info.area_m2).is_greater(0)
		if info.is_playable():
			assert_object(info.preview()).is_not_null()
			assert_bool(ResourceLoader.exists(info.scene_path)).is_true()


func test_an_unknown_or_locked_map_falls_back_to_the_lot() -> void:
	assert_str(MapRegistry.of("nope").id).is_equal("drive_in")
	StubMaps.install(false)
	assert_str(MapRegistry.of(StubMaps.ID).id).is_equal("drive_in")
	StubMaps.remove()
	assert_str(MapRegistry.of("").id).is_equal("drive_in")
	assert_str(MapRegistry.of("drive_in").id).is_equal("drive_in")


func test_a_map_is_described_in_words() -> void:
	var lot := MapRegistry.default_map()
	assert_str(lot.size_text()).is_equal("13,200 m²")
	assert_str(lot.facts_text()).is_equal("13,200 m² · 1 to 8 players")
	var one := MapInfo.new()
	one.min_players = 1
	one.max_players = 1
	assert_str(one.players_text()).is_equal("1 player")
	assert_str(one.size_text()).is_equal("")


func test_a_second_map_is_taken_once_it_is_playable() -> void:
	StubMaps.install(false)
	assert_bool(MapRegistry.is_playable(StubMaps.ID)).is_false()
	var locked := MatchSettings.new()
	locked.map = StubMaps.ID
	assert_str(String(MatchSettings.problem(locked.to_dict()))).is_equal("map")
	assert_str(locked.clamped().map).is_equal("drive_in")
	StubMaps.install(true)
	assert_bool(MapRegistry.is_playable(StubMaps.ID)).is_true()
	assert_str(MapRegistry.of(StubMaps.ID).id).is_equal(StubMaps.ID)
	assert_str(String(MatchSettings.problem(locked.to_dict()))).is_equal("")
	assert_str(locked.clamped().map).is_equal(StubMaps.ID)


func test_the_settings_carry_the_map_on_every_road() -> void:
	StubMaps.install()
	var chosen := MatchSettings.new()
	chosen.map = StubMaps.ID
	chosen.count_multiplier = 2.0
	assert_bool(chosen.is_default()).is_false()
	assert_bool(MatchSettings.new().is_default()).is_true()
	assert_str(MatchSettings.new().map).is_equal("drive_in")
	var data := chosen.to_dict()
	assert_str(data["map"]).is_equal(StubMaps.ID)
	assert_bool(MatchSettings.from_dict(data).same_as(chosen)).is_true()
	# JSON (a ticket's claims, the lobby the backend answers with).
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	assert_str(MatchSettings.from_json(parsed).map).is_equal(StubMaps.ID)
	# A snapshot (a WELCOME, a late join).
	var rules := GameRules.new(null, 3, chosen)
	assert_str(MatchSettings.from_snapshot(rules.to_dict()).map).is_equal(StubMaps.ID)
	var other := GameRules.new(null, 4)
	assert_str(String(other.from_dict(rules.to_dict()))).is_equal("")
	assert_str(other.settings.map).is_equal(StubMaps.ID)


func test_settings_from_before_the_choice_still_read() -> void:
	var old := {"count_multiplier": 2.0, "max_alive": 6, "break_seconds": 0.0}
	assert_str(String(MatchSettings.problem(old))).is_equal("")
	var read := MatchSettings.from_dict(old)
	assert_str(read.map).is_equal("drive_in")
	assert_float(read.count_multiplier).is_equal(2.0)
	# The same for the JSON a ticket from an older backend holds.
	assert_str(MatchSettings.from_json(old).map).is_equal("drive_in")
	# What the choice adds is checked as the other keys are: a wrong type or an unknown map is named.
	assert_str(String(MatchSettings.problem(old.merged({"map": 4})))).is_equal("map")
	assert_str(String(MatchSettings.problem(old.merged({"map": "nope"})))).is_equal("map")
	StubMaps.install(false)
	assert_str(String(MatchSettings.problem(old.merged({"map": StubMaps.ID})))).is_equal("map")
	StubMaps.remove()
	assert_str(String(MatchSettings.problem(old.merged({"map": "small_indoor"})))).is_equal("")
	assert_str(String(MatchSettings.problem(old.merged({"map": "drive_in"})))).is_equal("")
	assert_object(MatchSettings.from_dict(old.merged({"map": "nope"}))).is_null()


func test_a_lobby_or_a_preview_names_its_map() -> void:
	StubMaps.install()
	var settings := {
		"count_multiplier": 1.0, "max_alive": 0, "break_seconds": 0.0, "map": StubMaps.ID
	}
	assert_str(MapRegistry.of_lobby({"settings": settings}).id).is_equal(StubMaps.ID)
	assert_str(MapRegistry.of_lobby({"settings": null, "map": StubMaps.ID}).id).is_equal(
		StubMaps.ID
	)
	assert_str(MapRegistry.of_lobby({"map": StubMaps.ID}).id).is_equal(StubMaps.ID)
	assert_str(MapRegistry.of_lobby({"settings": null}).id).is_equal("drive_in")
	assert_str(MapRegistry.of_lobby({}).id).is_equal("drive_in")
	assert_str(MapRegistry.of_lobby({"map": "nope"}).id).is_equal("drive_in")


func test_the_backend_lists_the_maps_the_game_can_play() -> void:
	# The backend keeps its own list (a TypeScript file); the two must say the same.
	var path := ProjectSettings.globalize_path("res://").path_join(
		"../spikes/backend/src/settings.ts"
	)
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	var found := RegEx.create_from_string("MAP_UNLOCK_LEVELS[^=]*= [{]([^}]*)[}]").search(text)
	assert_object(found).is_not_null()
	var listed: Array[String] = []
	for part in found.get_string(1).split(","):
		var id := part.get_slice(":", 0).strip_edges()
		if id != "":
			listed.append(id)
	var playable: Array[String] = []
	for info in MapRegistry.playable():
		playable.append(info.id)
	assert_array(listed).is_equal(playable)
	var default_found := RegEx.create_from_string('DEFAULT_MAP = "([^"]*)"').search(text)
	assert_str(default_found.get_string(1)).is_equal(MapRegistry.DEFAULT)


# --- Levels open maps (#1067) ---


func test_the_drive_in_is_level_1_and_the_back_rooms_level_10() -> void:
	assert_int(MapRegistry.find("drive_in").unlock_level).is_equal(1)
	assert_int(MapRegistry.find("small_indoor").unlock_level).is_equal(10)
	assert_str(MapRegistry.find("small_indoor").unlock_text()).is_equal("Level 10")
	assert_str(MapRegistry.find("small_indoor").unlock_hint()).contains("level 10")
	# The rungs kept for maps three and four climb past the second map.
	assert_array(MapRegistry.RESERVED_UNLOCKS).is_equal([25, 40])


func test_the_registry_gate_at_every_level() -> void:
	for level in range(1, LevelCurve.MAX_LEVEL + 1):
		assert_bool(MapRegistry.is_open("drive_in", level)).is_true()
		var back_rooms_open := level >= 10
		assert_bool(MapRegistry.is_open("small_indoor", level)).is_equal(back_rooms_open)
		assert_str(MapRegistry.fit_host("small_indoor", level)).is_equal(
			"small_indoor" if back_rooms_open else "drive_in"
		)
		assert_int(MapRegistry.open_at(level).size()).is_equal(2 if back_rooms_open else 1)
	assert_bool(MapRegistry.is_open("nope", 55)).is_false()
	assert_str(MapRegistry.fit_host("nope", 55)).is_equal("drive_in")


func test_a_setting_naming_a_locked_map_falls_back_to_the_default_for_the_host() -> void:
	var asked := MatchSettings.new()
	asked.map = "small_indoor"
	asked.bots = 3
	asked.count_multiplier = 2.0
	var low := asked.fit_host(9)
	assert_str(low.map).is_equal("drive_in")
	# Only the map changes: the host's other rules stand.
	assert_int(low.bots).is_equal(3)
	assert_float(low.count_multiplier).is_equal(2.0)
	assert_str(asked.fit_host(10).map).is_equal("small_indoor")
	# The settings it was called on are not touched.
	assert_str(asked.map).is_equal("small_indoor")


func test_a_map_of_a_higher_rung_opens_at_its_own_level() -> void:
	var third := StubMaps.stub(true)
	third.unlock_level = 25
	var list: Array[MapInfo] = []
	list.append_array(MapRegistry.all())
	list.append(third)
	MapRegistry.use(list)
	assert_bool(MapRegistry.is_open(StubMaps.ID, 24)).is_false()
	assert_bool(MapRegistry.is_open(StubMaps.ID, 25)).is_true()
	assert_int(MapRegistry.open_at(24).size()).is_equal(2)
	assert_int(MapRegistry.open_at(25).size()).is_equal(3)
