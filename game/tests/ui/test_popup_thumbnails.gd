extends GdUnitTestSuite
## The unlock card shows what the wardrobe shows (#1131): the item's own picture in place of the
## letter chip and the wardrobe's name in place of the spelled id, both from the one source the
## wardrobe reads (`unlocks.json`, the part registry, the palette, the maps), so a card and the
## wardrobe never say two things.

const SCREEN := "res://ui/screens/customize_screen.tscn"
const TEST_PATH := "user://popup_thumbnails_test.cfg"
## The card slots that are clothes: the wardrobe has a cell for each.
const CLOTHES: Array[StringName] = [&"top", &"trousers", &"shoes", &"headwear", &"eyewear", &"neck"]
const LONG_ID := &"the_projectionists_very_long_named_jacket_of_the_late_show_at_the_lot"

var _saved_path: String


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()


func after_test() -> void:
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	await RouterFixture.clear(get_tree())


func _available_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table := LadderUnlocks.shipped()
	for level in table.levels():
		for row: Dictionary in table.earned_at(level):
			out.append(row)
	return out


func _card(slot: StringName, item: StringName) -> PopupCard:
	var card := PopupCard.new()
	card.setup(PopupQueue.Kind.UNLOCK, {"slot": slot, "item": item, "level": 1})
	auto_free(card)
	add_child(card)
	return card


func _colour_cell(screen: CustomizeScreen, item: StringName) -> WardrobeCell:
	for found in screen.cells("colour:primary"):
		if found.id == item:
			return found
	return null


func test_every_available_row_has_a_thumbnail_and_a_name_on_its_card() -> void:
	var rows := _available_rows()
	# Pins the table the test runs over: the ladder announces dozens of rows.
	assert_int(rows.size()).is_greater(30)
	for row in rows:
		var card := _card(row["slot"], row["item"])
		var where := "%s/%s" % [row["slot"], row["item"]]
		assert_bool(card.has_thumbnail()).override_failure_message("no picture: " + where).is_true()
		var words := card.lines()
		assert_int(words.size()).override_failure_message("words: " + where).is_equal(2)
		assert_str(words[1]).override_failure_message("name: " + where).is_not_empty()
		var item := LadderItem.of(row["slot"], row["item"])
		match int(item["kind"]):
			LadderItem.Kind.PART:
				assert_bool(ItemIcons.has(item["slot"], item["id"])).is_true()
			LadderItem.Kind.MAP:
				assert_object((item["info"] as MapInfo).preview()).is_not_null()


func test_a_card_names_an_item_as_the_wardrobe_cell_does() -> void:
	var screen := (load(SCREEN) as PackedScene).instantiate() as CustomizeScreen
	screen.params = {"unlocks": LookUnlocks.at_level(55), "seed": 5}
	var layer := CanvasLayer.new()
	add_child(layer)
	auto_free(layer)
	layer.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var checked := 0
	for row in _available_rows():
		var slot: StringName = row["slot"]
		var shown := PopupLadder.name_of(slot, row["item"])
		var found: WardrobeCell = null
		if slot == &"colour":
			found = _colour_cell(screen, row["item"])
		elif CLOTHES.has(slot):
			var key := String(row["part"])
			found = screen.cell_of(
				StringName(key.get_slice("/", 0)), StringName(key.get_slice("/", 1))
			)
		else:
			continue
		assert_object(found).override_failure_message("no cell for %s" % row["item"]).is_not_null()
		assert_str(shown).is_equal(found.title)
		checked += 1
	assert_int(checked).is_greater(30)


func test_the_item_is_read_from_the_registries_the_wardrobe_reads() -> void:
	var part := LadderItem.of(&"top", &"rolled_sleeves")
	assert_int(part["kind"]).is_equal(LadderItem.Kind.PART)
	assert_str(part["slot"]).is_equal("torso")
	assert_str(part["id"]).is_equal("rolled")
	assert_str(part["name"]).is_equal("Rolled sleeves")
	var colour := LadderItem.of(&"colour", &"cherry")
	assert_int(colour["kind"]).is_equal(LadderItem.Kind.COLOUR)
	var entry: Dictionary = LookCatalog.palette(LadderItem.COLOUR_CHANNEL)[7]
	assert_str(colour["name"]).is_equal(entry["label"])
	assert_bool(colour["colour"] == entry["colour"]).is_true()
	var map := LadderItem.of(&"map", &"back_rooms")
	assert_int(map["kind"]).is_equal(LadderItem.Kind.MAP)
	assert_str(map["name"]).is_equal("The back rooms")


func test_a_row_the_wardrobe_does_not_hold_keeps_the_letter_chip_and_the_spelled_name() -> void:
	var card := _card(&"plate_frame", &"no_such_frame")
	assert_bool(card.has_thumbnail()).is_false()
	assert_array(card.lines()).is_equal(["NEW FRAME", "No such frame"])


func test_a_frame_shows_its_own_border_on_a_plate_and_the_plates_name() -> void:
	var item := LadderItem.of(&"plate_frame", &"chrome")
	assert_int(item["kind"]).is_equal(LadderItem.Kind.FRAME)
	assert_str(item["name"]).is_equal("Chrome plate frame")
	assert_bool(PlateCatalog.shipped().has(PlateCatalog.FRAME, item["plate"])).is_true()
	var card := _card(&"plate_frame", &"chrome")
	assert_bool(card.has_thumbnail()).is_true()
	assert_array(card.lines()).is_equal(["NEW FRAME", "Chrome plate frame"])
	# A frame is a border round a plate, so its chip is as wide as a card's.
	assert_float(card._chip.size.x).is_equal(PopupCard.CARD_CHIP_WIDTH)


func test_a_card_and_an_emblem_show_their_own_art_and_the_plates_name() -> void:
	var plates := PlateCatalog.shipped()
	for entry: Array in [
		[&"tier_card", &"cartoon", LadderItem.Kind.CARD, "Cartoon calling card"],
		[&"tier_emblem", &"cartoon", LadderItem.Kind.EMBLEM, "Cartoon emblem"],
		[&"emblem", &"admit_one", LadderItem.Kind.EMBLEM, "Admit One emblem"],
		[&"calling_cards", &"calling_cards", LadderItem.Kind.CARD, "Calling cards"],
	]:
		var item := LadderItem.of(entry[0], entry[1])
		assert_int(item["kind"]).is_equal(entry[2])
		assert_str(item["name"]).is_equal(entry[3])
		(
			assert_bool(
				plates.has(
					PlateCatalog.CARD if entry[2] == LadderItem.Kind.CARD else PlateCatalog.EMBLEM,
					item["plate"]
				)
			)
			. is_true()
		)
		var card := _card(entry[0], entry[1])
		assert_bool(card.has_thumbnail()).is_true()
		assert_str(card.lines()[1]).is_equal(item["name"])
	# A card's chip is wider than a square's, so the card keeps its proportions.
	var wide := _card(&"tier_card", &"cartoon")
	var square := _card(&"tier_emblem", &"cartoon")
	assert_float(wide._chip.size.x).is_equal(PopupCard.CARD_CHIP_WIDTH)
	assert_float(square._chip.size.x).is_equal(PopupCard.CHIP)
	# Drawn: the thumbnail makes shapes (the art of a piece the plate has), and a piece it has not got
	# is the spelled id with the letter chip.
	var unknown := _card(&"tier_card", &"no_such_card")
	assert_bool(unknown.has_thumbnail()).is_false()


func test_a_name_too_long_for_the_card_is_cut_with_an_ellipsis_inside_the_card() -> void:
	var card := _card(&"top", LONG_ID)
	await get_tree().process_frame
	var spelled := LadderItem.spelled(LONG_ID)
	var words: Label = null
	for part in card.get_children():
		if part is Label and (part as Label).text == spelled:
			words = part
	assert_object(words).is_not_null()
	assert_int(words.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_bool(words.clip_text).is_true()
	# It does not fit even at the smallest type, so the cut is what keeps it in.
	var font := words.get_theme_font(&"font")
	assert_float(HudStyle.text_width(font, spelled, HudStyle.MIN_TEXT)).is_greater(words.size.x)
	assert_float(words.position.x + words.size.x).is_less_equal(
		card.size.x - float(HudStyle.PAD) + 0.5
	)
	assert_float(words.get_minimum_size().x).is_less_equal(words.size.x)
	assert_vector(card.size).is_equal(PopupCard.UNLOCK_SIZE)
