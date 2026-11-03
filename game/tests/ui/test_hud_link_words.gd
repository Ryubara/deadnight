extends GdUnitTestSuite
## A map's link cards use that map's own words (#697): the second map's door and stairs say what
## they open and never speak of the lot; the lot's cards (no `MapWords`) stay as they were. The
## card, the marker over a link and the feed's line are read through the real binding.

const SMALL_SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const SMALL_TUNING := "res://world/smallmap/smallmap_tuning.tres"
## Words of the lot that no card of the second map may use.
const LOT_WORDS: Array[String] = ["LOT", "FIELD", "YARD", "FENCE", "CONCESSION", "BOOTH"]

var _host: Control
var _fixture: HudFixture


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)
	_fixture = HudFixture.make(_host, 1)
	_fixture.into_round_one()


func _binding(words: MapWords) -> NightHudBinding:
	return NightHudBinding.new(_fixture.hud, ClientState.new(), _fixture.rules.tuning, null, words)


func _offer(binding: NightHudBinding, id: StringName, price := 450) -> HudPrompt:
	binding.show_prompt({"kind": &"door", "id": id, "price": price})
	return _fixture.hud.prompt


func _small() -> MapTuning:
	return load(SMALL_TUNING) as MapTuning


func test_each_link_card_of_the_second_map_says_a_door_or_a_stair_and_names_no_lot() -> void:
	var map := _small()
	var binding := _binding(map.words)
	var links := map.link_ids()
	assert_int(links.size()).is_equal(3)
	for id in links:
		var prompt := _offer(binding, id)
		assert_str(prompt.title_text).is_equal(map.words.link_name(id).to_upper())
		assert_str(prompt.detail_text).is_equal(map.words.link_detail(id).to_upper())
		assert_str(prompt.price_text).is_equal("NEED 450 POINTS")
		for word in LOT_WORDS:
			(
				assert_bool(prompt.title_text.contains(word) or prompt.detail_text.contains(word))
				. override_failure_message(
					(
						"%s: the card says %s: %s / %s"
						% [id, word, prompt.title_text, prompt.detail_text]
					)
				)
				. is_false()
			)
	assert_str(_offer(binding, &"door_side").title_text).contains("DOOR")
	assert_str(_offer(binding, &"door_stairs_start").title_text).contains("STAIRS")
	assert_str(_offer(binding, &"door_stairs_side").title_text).contains("STAIRS")


func test_every_door_of_the_second_maps_scene_has_words() -> void:
	var map := _small()
	var scene := auto_free((load(SMALL_SCENE) as PackedScene).instantiate()) as Node3D
	var ids: Array[StringName] = []
	for door in scene.get_node("Doors").get_children():
		ids.append(StringName(door.get_meta(&"shop_id")))
	assert_array(ids).contains_exactly_in_any_order(map.link_ids())
	for id in ids:
		assert_str(map.words.link_name(id)).is_not_empty()
		assert_str(map.words.link_detail(id)).is_not_empty()
		assert_str(NightHudBinding.door_name(id, map.words)).is_equal(map.words.link_name(id))


func test_the_lots_door_cards_keep_their_words() -> void:
	var binding := _binding(null)
	var prompt := _offer(binding, &"door_concession", 350)
	assert_str(prompt.title_text).is_equal("CONCESSION STAND")
	assert_str(prompt.detail_text).is_equal("OPENS THE NEXT PART OF THE LOT")
	for id in NightHudBinding.DOOR_NAMES:
		prompt = _offer(binding, id, 350)
		assert_str(prompt.title_text).is_equal(String(NightHudBinding.DOOR_NAMES[id]).to_upper())
		assert_str(prompt.detail_text).is_equal(HudPrompt.DETAILS[&"buy_door"])
	# A door no one named reads plainly, on the lot as before.
	assert_str(_offer(binding, &"door_unknown", 350).title_text).is_equal("A WAY THROUGH")


func test_the_card_changes_when_the_player_walks_from_one_link_to_the_next() -> void:
	var map := _small()
	var binding := _binding(map.words)
	_offer(binding, &"door_side")
	var prompt := _offer(binding, &"door_stairs_start")
	assert_str(prompt.title_text).is_equal("HALL STAIRS")
	assert_str(prompt.detail_text).is_equal("OPENS THE FLOOR ABOVE")


func test_the_marker_and_the_feed_use_the_maps_names_and_a_breach_says_window() -> void:
	var map := _small()
	var binding := _binding(map.words)
	assert_str(NightHudBinding.door_name(&"door_side", map.words)).is_equal("Side room door")
	assert_str(NightHudBinding.door_name(&"door_concession", null)).is_equal("Concession stand")
	binding.show_prompt({"kind": &"repair"})
	assert_str(_fixture.hud.prompt.title_text).is_equal("BOARDED WINDOW")
	var feed := _fixture.hud.events_feed
	_fixture.hud.state.apply_event(
		{"type": &"purchase_made", "player_id": 1, "item_id": &"door_stairs_side", "price": 450}
	)
	assert_str(feed.history.back()).ends_with("OPENED THE SIDE ROOM STAIRS")
	_fixture.hud.state.clear_prompt()
	var lot := _binding(null)
	lot.show_prompt({"kind": &"repair"})
	assert_str(_fixture.hud.prompt.title_text).is_equal("BROKEN FENCE")
