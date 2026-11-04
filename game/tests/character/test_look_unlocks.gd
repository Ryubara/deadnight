extends GdUnitTestSuite
## The ladder of wearables and colours (#1065): `unlocks.json` (the one table of what each level
## gives, the popups' and the maps' too) says what each level opens; the catalogue reads it into its
## gates, a look wearing what the level does not open is repaired on load, and the server drops it
## from a client that does not have it. Weapons and tonics are never in it.

const LADDER_PATH := "res://gameplay/progression/unlocks.json"
const PARTS_PATH := "res://assets/characters/soldier_parts/parts.json"
## The slots that carry the ladder's wearables; every other slot is free forever.
const WEARABLE_SLOTS: Array[StringName] = [
	&"headwear", &"torso", &"legs", &"feet", &"eyewear", &"neck"
]
const FREE_SLOTS: Array[StringName] = [&"head", &"hair", &"body", &"mouth", &"arm"]
const STARTING_COLOURS := ["black", "cream", "grey", "olive", "red", "blue"]
const PROFILE_PATH := "user://look_unlocks_test_profile.json"

var _profile_path_before: String


func before_test() -> void:
	_profile_path_before = LookUnlocks.profile_path
	LookUnlocks.profile_path = PROFILE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))


func after_test() -> void:
	LookUnlocks.profile_path = _profile_path_before
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))


func _json(path: String) -> Dictionary:
	var json := JSON.new()
	assert_int(json.parse(FileAccess.get_file_as_string(path))).is_equal(OK)
	return json.data


## The wardrobe's rows of the table: `parts` (`slot`, `id`, `level`, `available`) and `colours`
## (`id`, `level`); the starting pieces have no row.
func _ladder() -> Dictionary:
	var json := JSON.new()
	assert_int(json.parse(FileAccess.get_file_as_string(LADDER_PATH))).is_equal(OK)
	var parts: Array[Dictionary] = []
	var colours: Array[Dictionary] = []
	for row: Dictionary in json.data:
		if row["slot"] == "colour":
			colours.append({"id": row["item"], "level": int(row["level"])})
		elif row.has("part"):
			(
				parts
				. append(
					{
						"slot": String(row["part"]).get_slice("/", 0),
						"id": String(row["part"]).get_slice("/", 1),
						"level": int(row["level"]),
						"available": row["available"],
					}
				)
			)
	return {"parts": parts, "colours": colours}


func _write_profile(level: int) -> void:
	var profile := Profile.new()
	profile.xp = LevelCurve.xp_for(level)
	assert_bool(ProfileSave.write(profile, [], 1, PROFILE_PATH)).is_true()


func test_the_ladder_is_the_design_pages_table() -> void:
	var ladder := _ladder()
	var parts: Array = ladder["parts"]
	var art := _json(PARTS_PATH)["slots"] as Dictionary
	# 26 wearables up the ladder, and two of each of the six to start with (a model with no row).
	assert_int(parts.size()).is_equal(26)
	for slot in WEARABLE_SLOTS:
		var on_ladder := parts.filter(func(e: Dictionary) -> bool: return e["slot"] == String(slot))
		var starting := 0
		for id: String in art[slot]["parts"]:
			var listed := on_ladder.any(func(e: Dictionary) -> bool: return e["id"] == id)
			if id != "none" and not listed:
				starting += 1
		assert_int(starting).override_failure_message("two %s to start" % slot).is_equal(2)
	# Ten colours of the 16 up the ladder, and the six that are not on it to start with.
	var colours: Array = ladder["colours"]
	assert_int(colours.size()).is_equal(10)
	var names: Array = _json(PARTS_PATH)["palette_names"]["cloth"]
	var on_ladder_names := colours.map(func(e: Dictionary) -> String: return e["id"])
	var starting_colours := names.filter(
		func(n: String) -> bool: return not on_ladder_names.has(n.replace(" ", "_"))
	)
	assert_array(starting_colours).contains_exactly(STARTING_COLOURS)
	for entry: Dictionary in parts + colours:
		assert_int(int(entry["level"])).is_between(2, LevelCurve.MAX_LEVEL)


func test_only_wearables_and_cloth_are_on_the_ladder() -> void:
	var ladder := _ladder()
	for entry: Dictionary in ladder["parts"]:
		(
			assert_bool(StringName(entry["slot"]) in WEARABLE_SLOTS)
			. override_failure_message("%s is not a wearable slot" % entry["slot"])
			. is_true()
		)
	var names: Array = _json(PARTS_PATH)["palette_names"]["cloth"]
	for entry: Dictionary in ladder["colours"]:
		assert_bool(names.has(String(entry["id"]).replace("_", " "))).is_true()
	# Nothing free is gated: face, hair, character, mouth, armband, skin and hair colour.
	for slot in FREE_SLOTS:
		for option: Dictionary in LookCatalog.options(slot):
			assert_dict(option["gate"]).is_empty()
	for channel: StringName in [&"skin", &"hair"]:
		for entry: Dictionary in LookCatalog.palette(channel):
			assert_dict(entry["gate"]).is_empty()
	# The plain "None" of a wearable slot is free too.
	for slot in WEARABLE_SLOTS:
		var none := LookCatalog.option_index(slot, &"none")
		if none >= 0:
			assert_dict(LookCatalog.options(slot)[none]["gate"]).is_empty()


func test_every_gate_opens_at_its_level_and_not_before() -> void:
	var gates := LookCatalog.part_gates()
	# The 26 wearables above level 1; the starting ones are free and carry no gate.
	assert_int(gates.size()).is_equal(26)
	for key: String in gates:
		var gate: Dictionary = gates[key]
		var slot := StringName(key.get_slice("/", 0))
		var id := StringName(key.get_slice("/", 1))
		var needed := LookUnlocks.level_of(gate)
		assert_bool(LookUnlocks.at_level(needed).is_unlocked(slot, id, gate)).is_true()
		if needed > 1:
			(
				assert_bool(LookUnlocks.at_level(needed - 1).is_unlocked(slot, id, gate))
				. override_failure_message("%s is open a level early" % key)
				. is_false()
			)
	var palette_gates := LookCatalog.palette_gates()
	# Ten gated colours on each of the three cloth channels; the six starting ones are free.
	assert_int(palette_gates.size()).is_equal(10 * 3)
	for channel: StringName in [&"primary", &"secondary", &"accent"]:
		var gated := 0
		for i in LookCatalog.palette(channel).size():
			var entry: Dictionary = LookCatalog.palette(channel)[i]
			var key := "%s/%d" % [channel, i]
			if palette_gates.has(key):
				gated += 1
				assert_dict(entry["gate"]).is_equal(palette_gates[key])
			else:
				assert_dict(entry["gate"]).is_empty()
		assert_int(gated).is_equal(10)


func test_the_gate_words_say_the_level_and_for_a_player_where_they_stand() -> void:
	assert_str(LookUnlocks.describe({"level": 22})).is_equal("Reach level 22")
	assert_str(LookUnlocks.at_level(12).instructions({"level": 22})).is_equal(
		"Reach level 22 (you are level 12)"
	)
	assert_str(LookUnlocks.describe({})).is_equal("")


func test_what_the_art_has_and_what_the_ladder_promises_agree() -> void:
	var art := _json(PARTS_PATH)["slots"] as Dictionary
	# The table says a piece is available exactly when the parts have a model for it: a drawn piece
	# whose row still says no is never earned by anyone (the level popups skip it), a row that says
	# yes without a model dresses nobody.
	for entry: Dictionary in _ladder()["parts"]:
		var slot_parts: Dictionary = art[entry["slot"]]["parts"]
		(
			assert_bool(entry["available"])
			. override_failure_message(
				(
					"%s/%s: the row says %s and the parts say %s"
					% [entry["slot"], entry["id"], entry["available"], slot_parts.has(entry["id"])]
				)
			)
			. is_equal(slot_parts.has(entry["id"]))
		)
	# A piece with no model yet is listed for the grid by its icon, and only that.
	for slot in WEARABLE_SLOTS:
		for waiting: Dictionary in LookCatalog.pending(slot):
			assert_bool(art[slot]["parts"].has(String(waiting["id"]))).is_false()
			assert_bool(LookCatalog.option_index(slot, waiting["id"]) >= 0).is_false()
			assert_str(waiting["label"]).is_not_empty()
			assert_int(LookUnlocks.level_of(waiting["gate"])).is_greater(1)


func test_every_wearable_the_ladder_names_has_an_icon() -> void:
	for entry: Dictionary in _ladder()["parts"]:
		(
			assert_bool(ItemIcons.has(StringName(entry["slot"]), StringName(entry["id"])))
			. override_failure_message("no icon for %s/%s" % [entry["slot"], entry["id"]])
			. is_true()
		)


func test_a_look_wearing_what_the_level_does_not_open_is_put_back_to_what_it_may_wear() -> void:
	var look := CharacterLook.from_preset(0)
	look.parts[&"torso"] = &"letterman"
	look.parts[&"headwear"] = &"ranger"
	look.parts[&"feet"] = &"boots"
	look.parts[&"legs"] = &"striped"
	look.colours[&"primary"] = 11
	var at_one := look.without_locked(LookUnlocks.new())
	# The first piece of the slot that is theirs: a vest, no hat, the sneakers, plain trousers, black.
	assert_str(String(at_one.parts[&"torso"])).is_equal("vest")
	assert_str(String(at_one.parts[&"headwear"])).is_equal("none")
	assert_str(String(at_one.parts[&"feet"])).is_equal("sneakers")
	assert_str(String(at_one.parts[&"legs"])).is_equal("trousers")
	assert_int(at_one.colours[&"primary"]).is_equal(0)
	# At 12 the boots are theirs, and the rest still is not.
	var at_twelve := look.without_locked(LookUnlocks.at_level(12))
	assert_str(String(at_twelve.parts[&"feet"])).is_equal("boots")
	assert_str(String(at_twelve.parts[&"headwear"])).is_equal("none")
	assert_str(String(at_twelve.parts[&"torso"])).is_equal("vest")
	# At 55 nothing is put back.
	assert_bool(look.equals(look.without_locked(LookUnlocks.at_level(55)))).is_true()


func test_every_option_a_level_does_not_open_is_repaired_to_one_it_does() -> void:
	for level in [1, 12, 30, 55]:
		var unlocks := LookUnlocks.at_level(level)
		for slot in LookCatalog.part_slots():
			for option: Dictionary in LookCatalog.options(slot):
				var look := CharacterLook.new()
				look.parts[slot] = option["id"]
				var repaired := look.without_locked(unlocks)
				var now: Dictionary = LookCatalog.options(slot)[LookCatalog.option_index(
					slot, repaired.parts[slot]
				)]
				assert_bool(unlocks.is_unlocked(slot, now["id"], now["gate"])).is_true()
		for channel in LookCatalog.colour_slots():
			for i in LookCatalog.palette(channel).size():
				var look := CharacterLook.new()
				look.colours[channel] = i
				var at: int = look.without_locked(unlocks).colours[channel]
				var entry: Dictionary = LookCatalog.palette(channel)[at]
				assert_bool(unlocks.is_unlocked(channel, entry["id"], entry["gate"])).is_true()


func test_the_saved_look_is_repaired_at_load_by_the_level_in_the_profile() -> void:
	var path := "user://look_unlocks_test.cfg"
	var old_path := Settings.path
	Settings.path = path
	Settings.reset_defaults()
	var look := CharacterLook.from_preset(0)
	look.parts[&"headwear"] = &"helmet"
	look.parts[&"torso"] = &"rolled"
	look.colours[&"accent"] = 12
	LookStore.save_look(look)
	# No profile: a new player, level 1.
	var fresh := LookStore.load_look()
	assert_str(String(fresh.parts[&"headwear"])).is_equal("none")
	assert_str(String(fresh.parts[&"torso"])).is_equal("vest")
	assert_int(fresh.colours[&"accent"]).is_equal(0)
	# A profile at level 14 keeps the helmet (14), the rolled sleeves (4) and the tan (5).
	_write_profile(14)
	assert_int(LookUnlocks.saved().level).is_equal(14)
	var loaded := LookStore.load_look()
	assert_str(String(loaded.parts[&"headwear"])).is_equal("helmet")
	assert_str(String(loaded.parts[&"torso"])).is_equal("rolled")
	assert_int(loaded.colours[&"accent"]).is_equal(12)
	Settings.reset_defaults()
	Settings.save()
	Settings.path = old_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_server_drops_what_a_client_does_not_have() -> void:
	var levels := {1: 12, 2: 55}
	var hub := LoopbackHub.new(
		func(id: int) -> LookUnlocks: return LookUnlocks.at_level(levels[id])
	)
	var a := hub.connect_client()
	var b := hub.connect_client()
	var greedy := CharacterLook.from_preset(3)
	greedy.parts[&"torso"] = &"letterman"
	greedy.parts[&"headwear"] = &"ranger"
	greedy.colours[&"primary"] = 11
	hub.send_look(a, greedy)
	hub.send_look(b, greedy)
	hub.pump()
	var seen := (hub.clients[a] as LookRegistry).resolved()
	var low: CharacterLook = seen[a]
	assert_str(String(low.parts[&"torso"])).is_equal("vest")
	assert_str(String(low.parts[&"headwear"])).is_equal("none")
	assert_int(low.colours[&"primary"]).is_equal(0)
	# What they do have, and what is free, stays.
	assert_int(low.colours[&"skin"]).is_equal(greedy.colours[&"skin"])
	assert_str(String(low.parts[&"mouth"])).is_equal(String(greedy.parts[&"mouth"]))
	var high: CharacterLook = seen[b]
	assert_str(String(high.parts[&"torso"])).is_equal("letterman")
	assert_str(String(high.parts[&"headwear"])).is_equal("ranger")
	assert_int(high.colours[&"primary"]).is_equal(11)


func test_the_night_server_holds_a_player_to_the_level_it_knows() -> void:
	var night := await SeatedNight.start(self, 2)
	night.server.player_levels[1] = 5
	var greedy := CharacterLook.from_preset(3)
	greedy.parts[&"torso"] = &"letterman"
	greedy.colours[&"primary"] = 11
	for id in [1, 2]:
		night.server.apply(
			{"type": NightServer.LOOK, "player_id": id, "packet": LookWire.look(greedy)}
		)
	# Player 1 is known to be level 5; player 2's level is not known yet, and is trusted with it.
	var known: CharacterLook = night.server.looks.looks[1]
	assert_str(String(known.parts[&"torso"])).is_equal("vest")
	assert_int(known.colours[&"primary"]).is_equal(0)
	var unknown: CharacterLook = night.server.looks.looks[2]
	assert_str(String(unknown.parts[&"torso"])).is_equal("letterman")
	assert_int(unknown.colours[&"primary"]).is_equal(11)
	night.dispose()
