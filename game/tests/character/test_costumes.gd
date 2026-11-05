extends GdUnitTestSuite
## The twelve presets as costumes (#1066): which of them a level owns, which one a look wears, and
## what a costume's Default colours are allowed to be. The data is read from the same tables the
## game reads (`parts.json`, `unlocks.json`), so a change to the ladder moves the expected answers
## with it, and the numbers pinned here say what the data is today.

const LEVELS: Array[int] = [1, 10, 30, 55]
## The costumes made only of starting pieces, by the ladder as it is. The design page says four
## (docs/design/progression.md); the data has these two, which is an open question for the
## maintainer (#1066).
const STARTING_COSTUMES: Array[StringName] = [&"soda_jerk", &"carhop"]
## Which costumes each of the levels above owns.
const LIT_AT := {
	1: [&"soda_jerk", &"carhop"],
	10: [&"soda_jerk", &"carhop", &"projectionist"],
	30:
	[
		&"greaser",
		&"usher",
		&"mechanic",
		&"lifeguard",
		&"soda_jerk",
		&"ranger",
		&"letterman",
		&"projectionist",
		&"carhop",
		&"usherette",
		&"pit_crew",
		&"pep_squad"
	],
}


func _expected_level(index: int) -> int:
	var level := 0
	var parts: Dictionary = LookCatalog.presets()[index]["parts"]
	for slot: StringName in parts:
		var gate: Dictionary = LookCatalog.part_gates().get("%s/%s" % [slot, parts[slot]], {})
		level = maxi(level, int(gate.get("level", 0)))
	return level


func test_there_are_twelve_costumes_and_each_is_a_preset_that_wears_itself() -> void:
	assert_int(Costumes.count()).is_equal(12)
	for index in Costumes.count():
		assert_int(Costumes.of_look(Costumes.look(index))).is_equal(index)
		assert_str(Costumes.title(index)).is_equal(LookCatalog.presets()[index]["name"])


func test_the_level_a_costume_needs_is_its_last_piece() -> void:
	for index in Costumes.count():
		assert_int(Costumes.level_needed(index)).is_equal(_expected_level(index))


func test_the_costumes_of_starting_pieces_are_lit_for_a_new_player() -> void:
	var starter := LookUnlocks.at_level(1)
	var lit: Array[StringName] = []
	for index in Costumes.count():
		if starter.owns_costume(index):
			lit.append(Costumes.id(index))
	lit.sort()
	var wanted := STARTING_COSTUMES.duplicate()
	wanted.sort()
	assert_array(lit).is_equal(wanted)
	for index in Costumes.count():
		assert_bool(starter.owns_costume(index)).is_equal(Costumes.level_needed(index) <= 1)


func test_a_level_owns_exactly_the_costumes_whose_pieces_it_opens() -> void:
	for level in LEVELS:
		var unlocks := LookUnlocks.at_level(level)
		var lit: Array[StringName] = []
		for index in Costumes.count():
			var owned := unlocks.owns_costume(index)
			assert_bool(owned).is_equal(Costumes.level_needed(index) <= level)
			if owned:
				lit.append(Costumes.id(index))
				assert_str(unlocks.costume_instructions(index)).is_empty()
			else:
				assert_str(unlocks.costume_instructions(index)).is_equal(
					"Reach level %d (you are level %d)" % [Costumes.level_needed(index), level]
				)
		if LIT_AT.has(level):
			var wanted: Array = LIT_AT[level].duplicate()
			wanted.sort()
			lit.sort()
			assert_array(lit).is_equal(wanted)
		else:
			assert_int(lit.size()).is_equal(Costumes.count())


func test_a_costume_is_worn_by_its_pieces_and_not_by_face_hair_or_colours() -> void:
	var look := Costumes.look(1)
	look.parts[&"hair"] = &"flattop"
	look.parts[&"head"] = &"beard"
	look.parts[&"mouth"] = &"grin"
	look.colours[&"skin"] = 3
	look.colours[&"primary"] = 4
	assert_int(Costumes.of_look(look)).is_equal(1)
	look.parts[&"torso"] = &"vest"
	assert_int(Costumes.of_look(look)).is_equal(-1)


func test_the_default_colours_are_the_three_cloth_channels_of_the_preset() -> void:
	var look := Costumes.look(2)
	look.colours[&"primary"] = 1
	look.colours[&"hair"] = 2
	assert_bool(Costumes.has_default_colours(look, 2)).is_false()
	Costumes.give_default_colours(look, 2)
	assert_bool(Costumes.has_default_colours(look, 2)).is_true()
	# Skin and hair colour are the player's: Default does not touch them.
	assert_int(look.colours[&"hair"]).is_equal(2)
	for channel in Costumes.COLOUR_CHANNELS:
		assert_int(look.colours[channel]).is_equal(Costumes.look(2).colours[channel])


func test_the_default_colours_of_an_owned_costume_need_none_of_the_colour_unlocks() -> void:
	# The Usher at level 20: gold trim asks level 42 and cherry main asks level 3.
	var usher := LookUnlocks.at_level(20)
	var look := Costumes.look(1)
	var gold := Costumes.colour_index(1, &"accent")
	assert_bool(LookCatalog.palette(&"accent")[gold]["gate"].has("level")).is_true()
	(
		assert_bool(
			usher.is_unlocked(&"accent", &"gold", LookCatalog.palette(&"accent")[gold]["gate"])
		)
		. is_false()
	)
	assert_bool(look.without_locked(usher).equals(look)).is_true()
	assert_int(look.default_costume(usher)).is_equal(1)
	# A player who does not own it is put back to the palette they have.
	var low := LookUnlocks.at_level(12)
	var repaired := look.without_locked(low)
	assert_int(repaired.colours[&"accent"]).is_not_equal(gold)
	assert_int(look.default_costume(low)).is_equal(-1)


func test_changing_one_default_colour_leaves_the_others_to_the_palette_the_player_owns() -> void:
	var usher := LookUnlocks.at_level(20)
	var look := Costumes.look(1)
	var red := LookCatalog.palette(&"primary").find_custom(
		func(entry: Dictionary) -> bool: return entry["id"] == &"red"
	)
	look.colours[&"primary"] = red
	var repaired := look.without_locked(usher)
	assert_int(repaired.colours[&"primary"]).is_equal(red)
	# Gold trim was the costume's; on its own it asks level 42.
	assert_int(repaired.colours[&"accent"]).is_not_equal(Costumes.colour_index(1, &"accent"))
	assert_bool(repaired.equals(look)).is_false()


func test_the_server_keeps_a_costume_in_its_default_colours_for_the_level_it_knows() -> void:
	var sent: Array = []
	var server := LookServer.new(
		func(_id: int, packet: PackedByteArray) -> void: sent.append(packet),
		func(_id: int) -> LookUnlocks: return LookUnlocks.at_level(20)
	)
	server.join(7)
	server.receive(7, LookWire.look(Costumes.look(1)))
	assert_bool(server.looks[7].equals(Costumes.look(1))).is_true()
	# At level 12 the same packet comes back repaired: the pieces and the gold.
	var server_low := LookServer.new(
		func(_id: int, packet: PackedByteArray) -> void: sent.append(packet),
		func(_id: int) -> LookUnlocks: return LookUnlocks.at_level(12)
	)
	server_low.join(7)
	server_low.receive(7, LookWire.look(Costumes.look(1)))
	assert_bool(server_low.looks[7].equals(Costumes.look(1))).is_false()
	(
		assert_bool(
			server_low.looks[7].equals(server_low.looks[7].without_locked(LookUnlocks.at_level(12)))
		)
		. is_true()
	)


func test_every_cloth_colour_a_costume_brings_exists_in_the_palette() -> void:
	for index in Costumes.count():
		for channel in Costumes.COLOUR_CHANNELS:
			var at := Costumes.colour_index(index, channel)
			assert_int(at).is_between(0, LookCatalog.palette(channel).size() - 1)
