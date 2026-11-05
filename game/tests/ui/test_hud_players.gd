# A container per player, `[portrait][points in the player's colour]`, for one to eight players: the
# local player first, each in the colour of their seat, a downed player dimmed, the numbers on one
# line. Driven by the rules' own events (#218).
extends GdUnitTestSuite

const NAMES := ["Ruby", "Moe", "Dee", "Cal", "Ned", "Ivy", "Sal", "Pat"]

var _host: Control


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


func after_test() -> void:
	HudPortrait.live = true


func _party(players: int, portraits := false, bots := 0) -> HudFixture:
	var fixture := HudFixture.make(_host, players, 1958, portraits, bots)
	fixture.into_round_one()
	for i in players:
		fixture.hud.state.apply_event(
			{"type": &"points_changed", "player_id": i + 1, "total": 1000 * (i + 1), "delta": 0}
		)
	for i in bots:
		fixture.hud.state.apply_event(
			{
				"type": &"points_changed",
				"player_id": NightBots.id_at(i),
				"total": 500 * (i + 1),
				"delta": 0
			}
		)
	return fixture


## What the server says on a join: the player's seat and look.
func _look(state: HudState, id: int, seat: int, look: CharacterLook) -> void:
	state.apply_event(
		{"type": &"player_look", "player_id": id, "seat": seat, "look": look.to_dict()}
	)


func test_one_to_eight_players_each_get_a_box_in_their_seats_colour() -> void:
	for players in range(1, NightHost.MAX_PLAYERS + 1):
		var fixture := _party(players)
		var shown := fixture.hud.points.shown
		assert_array(shown).override_failure_message("%d players" % players).has_size(players)
		var colours: Array[Color] = []
		for i in players:
			var entry := shown[i]
			assert_int(entry["id"]).is_equal(i + 1)
			assert_int(entry["seat"]).is_equal(i)
			assert_int(entry["points"]).is_equal(1000 * (i + 1))
			assert_str(entry["name"]).is_equal(NAMES[i])
			# The seat's colour is the armband's, the one the player wears in the lot.
			assert_object(entry["colour"]).is_equal(LookCatalog.armband_colour(i))
			assert_object(fixture.hud.points.box_of(i + 1).fill()).is_equal(entry["colour"])
			colours.append(entry["colour"])
		for i in colours.size():
			for j in range(i + 1, colours.size()):
				assert_bool(colours[i].is_equal_approx(colours[j])).is_false()
		fixture.hud.get_parent().remove_child(fixture.hud)
		fixture.hud.free()


func test_the_local_player_comes_first_and_is_the_larger() -> void:
	var fixture := _party(4)
	var hud := fixture.hud
	hud.state.local_player_id = 3
	hud.points.refresh()
	var order := hud.points.order()
	assert_array(order).is_equal([3, 1, 2, 4])
	assert_bool(hud.points.shown[0]["local"]).is_true()
	assert_int(hud.points.shown[0]["id"]).is_equal(3)
	assert_str(hud.points.number_text).is_equal("3000")
	await await_idle_frame()
	await await_idle_frame()
	var own := hud.points.box_of(3)
	var other := hud.points.box_of(1)
	assert_float(own.size.y).is_equal(HudPlayerBox.LOCAL_HEIGHT)
	assert_float(other.size.y).is_equal(HudPlayerBox.OTHER_HEIGHT)
	assert_float(own.global_position.y).is_less(other.global_position.y)
	# The portrait is a square the box's height.
	assert_float(own.portrait.size.x).is_equal_approx(own.portrait.size.y, 0.01)


func test_a_seat_is_the_lowest_free_one_as_the_server_gives_it() -> void:
	var fixture := _party(3)
	var state := fixture.hud.state
	assert_int(state.team[2]["seat"]).is_equal(1)
	fixture.act(RulesAction.remove_player(2))
	fixture.act(RulesAction.add_player(5))
	assert_int(state.team[5]["seat"]).is_equal(1)
	# Told by the server, the seat and the look stand.
	_look(state, 5, 3, CharacterLook.from_preset(4))
	assert_int(state.team[5]["seat"]).is_equal(3)
	var entry := fixture.hud.points.shown.filter(func(e: Dictionary) -> bool: return e["id"] == 5)
	assert_object(entry[0]["colour"]).is_equal(LookCatalog.armband_colour(3))


func test_a_party_of_eight_takes_compact_teammate_boxes_and_a_column_no_taller_than_the_room(
) -> void:
	var small := _party(HudPoints.COMPACT_FROM)
	await await_idle_frame()
	await await_idle_frame()
	assert_float(small.hud.points.box_of(2).size.y).is_equal(HudPlayerBox.OTHER_HEIGHT)
	small.hud.get_parent().remove_child(small.hud)
	small.hud.free()
	var fixture := _party(NightHost.MAX_PLAYERS)
	await await_idle_frame()
	await await_idle_frame()
	var points := fixture.hud.points
	assert_array(points.order()).has_size(NightHost.MAX_PLAYERS)
	assert_float(points.box_of(1).size.y).is_equal(HudPlayerBox.LOCAL_HEIGHT)
	for id in range(2, NightHost.MAX_PLAYERS + 1):
		assert_float(points.box_of(id).size.y).is_equal(HudPlayerBox.COMPACT_HEIGHT)
		# The number still shows whole.
		assert_float(points.box_of(id).number_width()).is_less_equal(
			points.box_of(id).number_size().x + 0.5
		)
	# Eight players stand in less than twice the height of the four before them.
	var four := HudPlayerBox.LOCAL_HEIGHT + 3.0 * (HudPlayerBox.OTHER_HEIGHT + float(HudStyle.GAP))
	assert_float(points.size.y).is_less(four * 1.6)
	fixture.hud.get_parent().remove_child(fixture.hud)
	fixture.hud.free()


func test_eight_people_and_seven_bots_the_people_get_boxes_and_the_bots_a_strip_of_chips() -> void:
	var fixture := _party(NightHost.MAX_PLAYERS, false, MatchSettings.MAX_BOTS)
	await await_idle_frame()
	await await_idle_frame()
	var points := fixture.hud.points
	assert_array(points.order()).has_size(NightHost.MAX_SEATS)
	# You, then the other people by id, then the bots by id.
	var expected: Array[int] = []
	for id in range(1, NightHost.MAX_PLAYERS + 1):
		expected.append(id)
	for i in MatchSettings.MAX_BOTS:
		expected.append(NightBots.id_at(i))
	assert_array(points.order()).is_equal(expected)
	var bots_seen := 0
	for entry in points.shown:
		if entry["bot"]:
			bots_seen += 1
			assert_bool(NightBots.is_bot_id(entry["id"])).is_true()
			# Past eight bodies a bot is a chip, not a box.
			assert_bool(entry.get("chip", false)).is_true()
			assert_object(points.box_of(entry["id"])).is_null()
			assert_object(points.chips().chip_of(entry["id"])).is_not_null()
	assert_int(bots_seen).is_equal(MatchSettings.MAX_BOTS)
	# The people's boxes are the compact ones and the whole column is what the strip adds to eight.
	for id in range(2, NightHost.MAX_PLAYERS + 1):
		assert_float(points.box_of(id).size.y).is_equal(HudPlayerBox.COMPACT_HEIGHT)
	var eight := (
		HudPlayerBox.LOCAL_HEIGHT + 7.0 * (HudPlayerBox.COMPACT_HEIGHT + float(HudStyle.GAP))
	)
	# The strip adds its two rows to the eight; the layout suite holds the whole column off the
	# parts above it at the shortest canvas.
	assert_float(points.size.y).is_less_equal(
		eight + float(HudStyle.GAP) + HudBotChips.height_for(MatchSettings.MAX_BOTS) + 8.0
	)
	# A bot that goes down reads down on its chip.
	fixture.act(RulesAction.set_downed(NightBots.id_at(2), true))
	await await_idle_frame()
	var downed: Array = points.chips().shown.filter(
		func(chip: Dictionary) -> bool: return chip["downed"]
	)
	assert_array(downed).has_size(1)
	assert_int(downed[0]["id"]).is_equal(NightBots.id_at(2))
	# Eight bodies or fewer have no strip: a room of four people and four bots is eight boxes.
	fixture.hud.get_parent().remove_child(fixture.hud)
	fixture.hud.free()
	var small := _party(4, false, 4)
	await await_idle_frame()
	assert_bool(small.hud.points.chips().visible).is_false()
	assert_object(small.hud.points.box_of(NightBots.id_at(0))).is_not_null()
	small.hud.get_parent().remove_child(small.hud)
	small.hud.free()


func test_the_number_is_readable_on_every_seats_colour() -> void:
	for seat in NightHost.MAX_PLAYERS:
		var fill := LookCatalog.armband_colour(seat)
		var ink := HudPlayerBox.ink_for(fill)
		(
			assert_float(HudPlayerBox.contrast(fill, ink))
			. override_failure_message("seat %d" % seat)
			. is_greater_equal(4.5)
		)


func test_a_downed_player_is_dimmed_and_says_so() -> void:
	var fixture := _party(2)
	var hud := fixture.hud
	var box := hud.points.box_of(2)
	var alive := box.fill()
	assert_bool(box.portrait.downed).is_false()
	fixture.act(RulesAction.set_downed(2, true))
	assert_bool(box.portrait.downed).is_true()
	assert_str(box.name_text).is_equal("DOWN")
	assert_bool(box.fill().is_equal_approx(alive)).is_false()
	assert_float(box.portrait.get_child(0).modulate.r).is_less(0.5)
	fixture.act(RulesAction.set_downed(2, false))
	assert_str(box.name_text).is_equal("MOE")
	assert_object(box.fill()).is_equal(alive)


func test_the_numbers_of_every_box_end_on_one_line_and_share_a_baseline_with_the_name() -> void:
	var fixture := _party(4)
	await await_idle_frame()
	await await_idle_frame()
	var points := fixture.hud.points
	var right := -1.0
	for id in points.order():
		var box := points.box_of(id)
		var number_label: Label = box._number
		var name_label: Label = box._name
		var end := box.global_position.x + number_label.position.x + number_label.size.x
		if right < 0.0:
			right = end
		assert_float(end).override_failure_message("box %d" % id).is_equal_approx(right, 0.5)
		# Name and number stand on one baseline.
		var number_base := (
			number_label.position.y
			+ number_label.get_theme_font(&"font").get_ascent(
				number_label.get_theme_font_size(&"font_size")
			)
		)
		var name_base := (
			name_label.position.y
			+ name_label.get_theme_font(&"font").get_ascent(
				name_label.get_theme_font_size(&"font_size")
			)
		)
		assert_float(name_base).override_failure_message("box %d" % id).is_equal_approx(
			number_base, 0.5
		)
		# Neither text leaves its box.
		var inside := Rect2(Vector2.ZERO, box.size)
		assert_bool(inside.encloses(Rect2(number_label.position, number_label.size))).is_true()
		assert_bool(inside.encloses(Rect2(name_label.position, name_label.size))).is_true()


func test_a_leaving_player_frees_their_box() -> void:
	var fixture := _party(4)
	var column := fixture.hud.points._column
	var boxes := func() -> int:
		return column.get_children().filter(func(c: Node) -> bool: return c is HudPlayerBox).size()
	assert_int(boxes.call()).is_equal(4)
	fixture.act(RulesAction.remove_player(3))
	await await_idle_frame()
	assert_int(boxes.call()).is_equal(3)
	assert_object(fixture.hud.points.box_of(3)).is_null()


func test_the_portrait_is_the_soldier_as_the_player_wears_it() -> void:
	var fixture := _party(2, true)
	var points := fixture.hud.points
	for id in [1, 2]:
		var portrait := points.box_of(id).portrait
		assert_object(portrait.model).is_not_null()
		assert_str(portrait.look_key).is_not_empty()
		# The armband on the model is the seat's colour.
		var band := portrait.model.find_child(CharacterAssembler.ARMBAND_NAME, true, false)
		assert_object(band).is_not_null()
		var material := (band as MeshInstance3D).mesh.material as StandardMaterial3D
		assert_object(material.albedo_color).is_equal(LookCatalog.armband_colour(id - 1))
	assert_str(points.box_of(1).portrait.look_key).is_not_equal(points.box_of(2).portrait.look_key)
	# A look from the server replaces the preset; showing the same one again changes nothing.
	var look := CharacterLook.from_preset(5)
	_look(fixture.hud.state, 2, 1, look)
	var key := points.box_of(2).portrait.look_key
	assert_str(key).contains(look.key())
	var model := points.box_of(2).portrait.model
	_look(fixture.hud.state, 2, 1, look)
	assert_object(points.box_of(2).portrait.model).is_same(model)


func test_the_portrait_is_drawn_once_and_then_costs_nothing() -> void:
	var fixture := _party(1, true)
	var portrait := fixture.hud.points.box_of(1).portrait
	var viewport: SubViewport = portrait._viewport
	assert_int(viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_DISABLED)
	for _i in HudPortrait.POSE_FRAMES + 1:
		await await_idle_frame()
	# UPDATE_ONCE puts itself back to disabled once drawn; either way it is not drawing each frame.
	assert_int(viewport.render_target_update_mode).is_not_equal(SubViewport.UPDATE_ALWAYS)
