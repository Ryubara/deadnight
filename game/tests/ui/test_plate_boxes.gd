extends GdUnitTestSuite
## The calling card behind a player's box and the emblem after the name (#1070), and the frame round
## the box (#1071): what the HUD's
## state keeps of them, the box in all three sizes (your own, a teammate's, the compact one) with
## the order of icon, level and name untouched, the words readable on every card for every seat
## colour, the card cut to the box's own shape, and a box with neither exactly what it was.

const LOCAL := 1
const OTHER := 2
## A party of five or more makes the teammates' boxes the compact size (`HudPoints.COMPACT_FROM`).
const BIG_PARTY := 6

var _hosts: Array[Control] = []


func after_test() -> void:
	for host in _hosts:
		if is_instance_valid(host):
			host.queue_free()
	_hosts.clear()
	HudPortrait.live = true


func before_test() -> void:
	HudPortrait.live = false


func _hud(players := 2) -> Hud:
	var host: Control = Control.new()
	host.size = Vector2(1920.0, 1080.0)
	add_child(host)
	_hosts.append(host)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	host.add_child(hud)
	hud.state.local_player_id = LOCAL
	for i in players:
		hud.state.set_player_name(i + 1, ["Ruby", "Moe", "Dee", "Cal", "Ned", "Ivy"][i])
		hud.state.set_player_level(i + 1, 12 + i, 12 + i)
	return hud


func _box(hud: Hud, id: int) -> HudPlayerBox:
	hud.points.refresh()
	return hud.points.box_of(id)


# --- The state ---


func test_the_state_keeps_the_card_and_emblem_of_a_seat_from_the_events() -> void:
	var state := HudState.new()
	state.apply_event({"type": &"player_named", "player_id": 2, "name": "Moe"})
	assert_str(state.plate_of(state.team[2])["card"]).is_equal("")
	state.apply_event(
		{
			"type": &"account_seated",
			"player_id": 2,
			"level": 30,
			"card": &"cartoon",
			"emblem": &"walk_in"
		}
	)
	assert_str(state.plate_of(state.team[2])["card"]).is_equal("cartoon")
	assert_str(state.plate_of(state.team[2])["emblem"]).is_equal("walk_in")
	# A level crossed in the night changes the level, not what the seat wears.
	state.apply_event({"type": &"level_up", "player_id": 2, "level": 31, "total": 4000})
	assert_str(state.plate_of(state.team[2])["card"]).is_equal("cartoon")
	state.apply_event({"type": &"account_left", "player_id": 2})
	assert_str(state.plate_of(state.team[2])["card"]).is_equal("")
	assert_str(state.plate_of(state.team[2])["emblem"]).is_equal("")


func test_a_late_joiner_reads_every_plate_from_the_welcome_and_a_bot_has_none() -> void:
	var state := HudState.new()
	state.local_player_id = 1
	(
		state
		. load_snapshot(
			{
				"players": {1: {}, 2: {}, 3: {}},
				"plates": {2: {"card": &"dead_eye", "emblem": &"dead_eye"}},
			}
		)
	)
	assert_str(state.plate_of(state.team[2])["card"]).is_equal("dead_eye")
	assert_str(state.plate_of(state.team[3])["card"]).is_equal("")
	# What it already knew stays through a second snapshot that does not name it.
	state.apply_event({"type": &"account_seated", "player_id": 1, "level": 9, "card": &"cartoon"})
	state.load_snapshot({"players": {1: {}, 2: {}, 3: {}}})
	assert_str(state.plate_of(state.team[1])["card"]).is_equal("cartoon")
	state.team[2]["bot"] = true
	assert_str(state.plate_of(state.team[2])["card"]).is_equal("")


func test_the_state_keeps_the_frame_of_a_seat_with_its_card() -> void:
	var state := HudState.new()
	state.apply_event({"type": &"player_named", "player_id": 2, "name": "Moe"})
	assert_str(state.plate_of(state.team[2])["frame"]).is_equal("")
	state.apply_event({"type": &"account_seated", "player_id": 2, "level": 30, "frame": &"chrome"})
	assert_str(state.plate_of(state.team[2])["frame"]).is_equal("chrome")
	state.set_player_plate(2, &"cartoon", &"", &"")
	assert_str(state.plate_of(state.team[2])["frame"]).is_equal("")
	state.load_snapshot({"players": {1: {}, 2: {}}, "plates": {2: {"frame": &"gold"}}})
	assert_str(state.plate_of(state.team[2])["frame"]).is_equal("gold")
	state.team[2]["bot"] = true
	assert_str(state.plate_of(state.team[2])["frame"]).is_equal("")
	state.team[2]["bot"] = false
	state.apply_event({"type": &"account_left", "player_id": 2})
	assert_str(state.plate_of(state.team[2])["frame"]).is_equal("")


# --- The boxes ---


func test_a_frame_runs_round_the_box_in_all_three_sizes_and_moves_nothing() -> void:
	for players in [3, BIG_PARTY]:
		var hud := _hud(players)
		var before := {}
		for id in [LOCAL, OTHER]:
			var box := _box(hud, id)
			assert_bool(box._frame.visible).is_false()
			before[id] = {"badge": box.badge_parts.duplicate(), "number": box.number_right()}
		for id in [LOCAL, OTHER]:
			hud.state.set_player_plate(id, &"", &"", &"neon")
		for id in [LOCAL, OTHER]:
			var box := _box(hud, id)
			var frame := box._frame as FrameArt
			assert_bool(frame.visible).is_true()
			assert_str(frame.frame_id).is_equal("neon")
			assert_vector(frame.position).is_equal(box._box().position)
			assert_vector(frame.size).is_equal(box._box().size)
			assert_int(frame.outline.size()).is_equal(6)
			assert_int(frame.op_count()).is_greater(0)
			# The icon, the level, the name and the points are where they were.
			assert_dict(box.badge_parts).is_equal(before[id]["badge"])
			assert_float(box.number_right()).is_equal(before[id]["number"])
			# The border is thinner than the room the words keep at the box's edge.
			assert_float(frame.depth()).is_less(HudPlayerBox.PADDING)


func test_a_frame_comes_off_with_the_seat_and_dims_with_a_downed_player() -> void:
	var hud := _hud(3)
	hud.state.set_player_plate(OTHER, &"", &"", &"gold")
	var box := _box(hud, OTHER)
	assert_float((box._frame as FrameArt).dim).is_equal(0.0)
	hud.state.team[OTHER]["downed"] = true
	hud.state.set_player_plate(OTHER, &"", &"", &"gold")
	hud.state.set_player_name(OTHER, "Moe")
	box = _box(hud, OTHER)
	assert_float((box._frame as FrameArt).dim).is_equal(HudPlayerBox.CARD_DOWN)
	hud.state.set_player_plate(OTHER, &"", &"", &"")
	assert_bool(_box(hud, OTHER)._frame.visible).is_false()


func test_a_box_with_no_card_or_emblem_is_exactly_what_it_was() -> void:
	var hud := _hud(BIG_PARTY)
	for id in [LOCAL, OTHER]:
		var box := _box(hud, id)
		assert_str(box.shown_card).is_equal("")
		assert_int((box._card as CardArt).shape_count()).is_equal(0)
		assert_bool(box._emblem.visible).is_false()


func test_the_card_fills_the_box_in_all_three_sizes_and_takes_its_shape() -> void:
	var hud := _hud(BIG_PARTY)
	for id in [LOCAL, OTHER, 3]:
		hud.state.set_player_plate(id, &"cartoon", &"")
	for id in [LOCAL, OTHER]:
		var box := _box(hud, id)
		var card := box._card as CardArt
		var expected := box._box()
		assert_vector(card.position).is_equal(expected.position)
		assert_vector(card.size).is_equal(expected.size)
		assert_int(card.shape_count()).is_greater(10)
		# Cut to the box's ticket shape: the corners of the box are cut, the art does not poke out.
		assert_int(card.clip.size()).is_equal(6)
	# The three heights: yours, a teammate's, and the compact teammate's of a party of six.
	assert_float(_box(hud, LOCAL).custom_minimum_size.y).is_equal(HudPlayerBox.LOCAL_HEIGHT)
	assert_float(_box(hud, OTHER).custom_minimum_size.y).is_equal(HudPlayerBox.COMPACT_HEIGHT)
	var wide := _hud(3)
	wide.state.set_player_plate(OTHER, &"cartoon", &"")
	assert_float(_box(wide, OTHER).custom_minimum_size.y).is_equal(HudPlayerBox.OTHER_HEIGHT)


func test_the_badge_and_the_name_keep_their_order_and_gaps_with_a_card_behind() -> void:
	for players in [3, BIG_PARTY]:
		var hud := _hud(players)
		var before := {}
		for id in [LOCAL, OTHER]:
			before[id] = (_box(hud, id) as HudPlayerBox).badge_parts.duplicate()
			assert_dict(before[id]).is_not_empty()
		for id in [LOCAL, OTHER]:
			hud.state.set_player_plate(id, &"midnight_show", &"")
		for id in [LOCAL, OTHER]:
			var box := _box(hud, id)
			# The icon, the level and where the name starts are where they were (its end gives way
			# to the tab's lean, which is the name's room, not its place).
			for part in ["icon", "level"]:
				assert_object(box.badge_parts[part]).is_equal(before[id][part])
			assert_vector((box.badge_parts["name"] as Rect2).position).is_equal(
				(before[id]["name"] as Rect2).position
			)
			# Icon, then the level beside it, then the larger gap, then the name.
			var parts := box.badge_parts
			(
				assert_float((parts["level"] as Rect2).position.x - (parts["icon"] as Rect2).end.x)
				. is_equal(LevelTag.ICON_GAP)
			)
			(
				assert_float((parts["name"] as Rect2).position.x - (parts["level"] as Rect2).end.x)
				. is_equal(LevelTag.NAME_GAP)
			)


func test_the_emblem_follows_the_name_and_leaves_the_badge_and_the_points_where_they_were() -> void:
	for players in [3, BIG_PARTY]:
		var hud := _hud(players)
		var bare := {}
		for id in [LOCAL, OTHER]:
			var box := _box(hud, id)
			bare[id] = {"parts": box.badge_parts.duplicate(), "right": box.number_right()}
		for id in [LOCAL, OTHER]:
			hud.state.set_player_plate(id, &"", &"cartoon")
		for id in [LOCAL, OTHER]:
			var box := _box(hud, id)
			assert_bool(box._emblem.visible).is_true()
			(
				assert_dict({"icon": box.badge_parts["icon"], "level": box.badge_parts["level"]})
				. is_equal({"icon": bare[id]["parts"]["icon"], "level": bare[id]["parts"]["level"]})
			)
			assert_float(box.number_right()).is_equal(bare[id]["right"])
			# After the name's own text, before the points, inside the box, and square.
			var emblem := Rect2(box._emblem.position, box._emblem.size)
			assert_float(emblem.position.x).is_greater_equal(
				(box.badge_parts["name"] as Rect2).position.x
			)
			assert_float(emblem.end.x).is_less_equal(box._number.position.x)
			assert_float(emblem.size.x).is_equal(emblem.size.y)
			assert_float(emblem.size.y).is_less_equal(box.custom_minimum_size.y)
			assert_int((box._emblem as EmblemArt).shape_count()).is_greater(4)


func test_a_long_name_gives_way_to_the_emblem_not_the_other_way() -> void:
	var hud := _hud(3)
	hud.state.set_player_name(LOCAL, "RubyTheRiveterOfTheNight")
	hud.state.set_player_plate(LOCAL, &"", &"headliner")
	var box := _box(hud, LOCAL)
	var emblem_right := box._emblem.position.x + box._emblem.size.x
	assert_float(emblem_right).is_less_equal(box._number.position.x)
	# The name's own room ends where the emblem begins.
	assert_float(box.name_rect().end.x).is_less_equal(box._emblem.position.x + 0.01)
	assert_float(box.name_rect().size.x).is_greater(HudPlayerBox.NAME_ROOM * 0.5)


func test_the_words_keep_their_contrast_on_every_card_for_every_seat_colour() -> void:
	# Over a card the level and the name sit on a strip of the seat's colour and the points on the
	# tab, so each glyph is on the colour its ink was chosen for, whatever the art behind it is
	# (test_plate_words reads the pixels).
	var plates := PlateCatalog.shipped()
	var hud := _hud(BIG_PARTY)
	var worst := 99.0
	for seat in 8:
		for downed in [false, true]:
			for id in plates.ids(PlateCatalog.CARD):
				hud.state.team[OTHER]["seat"] = seat
				hud.state.team[OTHER]["downed"] = downed
				hud.state.set_player_plate(OTHER, id, &"")
				var box := _box(hud, OTHER)
				for label: HudLabel in [box._name, box._level, box._number]:
					assert_int(label.halo_size).is_equal(0)
				assert_bool(box._tab.visible).is_true()
				assert_bool(box._tab.colour == box.fill()).is_true()
				assert_bool(box._name_tab.visible).is_true()
				assert_bool(box._name_tab.colour == box.fill()).is_true()
				for pair: Array in [
					[box._name, box._name_tab.colour],
					[box._level, box._name_tab.colour],
					[box._number, box._tab.colour],
				]:
					var ink: Color = (pair[0] as Label).get_theme_color(&"font_color")
					worst = minf(worst, HudPlayerBox.contrast(pair[1], ink))
	assert_float(worst).is_greater_equal(HudPlayerBox.MIN_CONTRAST)


func test_the_strip_behind_the_words_is_as_long_as_they_are_and_only_over_a_card() -> void:
	for players in [3, BIG_PARTY]:
		var hud := _hud(players)
		for id in [LOCAL, OTHER]:
			var bare := _box(hud, id)
			assert_bool(bare._name_tab.visible).is_false()
			hud.state.set_player_plate(id, &"cartoon", &"headliner")
			var box := _box(hud, id)
			var strip := box._name_tab.rect
			var level := box.badge_parts["level"] as Rect2
			var name_rect := box.name_rect()
			var text := minf(
				HudStyle.text_width(
					box._name.get_theme_font(&"font"),
					box._name.text,
					box._name.get_theme_font_size(&"font_size")
				),
				name_rect.size.x
			)
			# From before the level to after the name's text, inside the box and its points tab.
			assert_float(strip.position.x).is_less(level.position.x)
			assert_float(strip.end.x).is_greater(name_rect.position.x + text)
			assert_float(strip.end.x).is_less_equal(box._tab.position.x + box._tab.size.x)
			assert_float(strip.end.x - HudNameTab.SLANT).is_less(
				box._tab.position.x + HudPointsTab.SLANT
			)
			# Only as high as the line needs, centred in the box, so the card shows above and below.
			assert_float(strip.size.y).is_less(box._box().size.y)
			assert_float(strip.get_center().y).is_equal_approx(box._box().get_center().y, 0.01)
			assert_float(strip.size.y).is_greater_equal(float(HudStyle.SMALL))
			# The emblem and the portrait are not under it.
			assert_float(strip.position.x).is_greater_equal(box._box().position.x)
		hud.state.set_player_plate(LOCAL, &"", &"")
		assert_bool(_box(hud, LOCAL)._name_tab.visible).is_false()


func test_a_screen_where_a_unit_is_a_fraction_of_a_pixel_gets_the_heavier_type() -> void:
	for players in [3, BIG_PARTY]:
		var hud := _hud(players)
		for id in [LOCAL, OTHER]:
			hud.state.set_player_plate(id, &"cartoon", &"headliner")
			var box := _box(hud, id)
			# The headless window is a few pixels wide: its unit is a fraction of one.
			box.set_thin(false)
			var plain_name := box._name.get_theme_font(&"font") as FontVariation
			var plain_width := box.name_rect().size.x
			box.set_thin(true)
			var thin_name := box._name.get_theme_font(&"font") as FontVariation
			assert_float(thin_name.variation_embolden).is_greater(plain_name.variation_embolden)
			(
				assert_float(
					(box._number.get_theme_font(&"font") as FontVariation).variation_embolden
				)
				. is_greater(HudPlayerBox.THIN_BOLD)
			)
			# Nothing else moves: the badge, the name's start and the points' right edge.
			assert_float(box.name_rect().position.x).is_greater(0.0)
			assert_float(box.number_right()).is_less_equal(box._box().end.x)
			assert_float(box.name_rect().end.x).is_less_equal(box._tab.position.x + 0.01)
			assert_float(box.name_rect().size.x).is_greater(0.0)
			box.set_thin(false)
			(
				assert_float(
					(box._name.get_theme_font(&"font") as FontVariation).variation_embolden
				)
				. is_equal(plain_name.variation_embolden)
			)
			assert_float(box.name_rect().size.x).is_equal(plain_width)


func test_a_box_with_no_card_has_no_outline_and_no_tab() -> void:
	var hud := _hud(3)
	var box := _box(hud, LOCAL)
	for label: HudLabel in [box._name, box._level, box._number]:
		assert_int(label.halo_size).is_equal(0)
	assert_bool(box._tab.visible).is_false()
	hud.state.set_player_plate(LOCAL, &"cartoon", &"")
	assert_int(_box(hud, LOCAL)._name.halo_size).is_equal(0)
	hud.state.set_player_plate(LOCAL, &"", &"")
	assert_int(_box(hud, LOCAL)._name.halo_size).is_equal(0)
	assert_bool(_box(hud, LOCAL)._tab.visible).is_false()


func test_the_tab_holds_the_points_and_stops_short_of_the_name_and_the_emblem() -> void:
	for players in [3, BIG_PARTY]:
		var hud := _hud(players)
		hud.state.set_player_name(LOCAL, "RubyTheRiveterOfTheNight")
		hud.state.set_player_name(OTHER, "MoeTheMoverOfTheLot")
		for id in [LOCAL, OTHER]:
			hud.state.set_player_plate(id, &"dead_eye", &"headliner")
		for id in [LOCAL, OTHER]:
			var box := _box(hud, id)
			var tab := Rect2(box._tab.position, box._tab.size)
			var number := Rect2(box._number.position, box._number.size)
			# The whole number is on the tab, which runs to the box's right edge.
			assert_float(tab.position.x + HudPointsTab.SLANT).is_less_equal(number.position.x)
			assert_float(tab.end.x).is_equal(box._box().end.x)
			assert_float(tab.size.y).is_equal(box._box().size.y)
			# The name's room and the emblem end before the tab begins.
			assert_float(box.name_rect().end.x + box._emblem_taken()).is_less_equal(
				tab.position.x + 0.01
			)
			assert_float(box._emblem.position.x + box._emblem.size.x).is_less_equal(
				tab.position.x + 0.01
			)


func test_a_downed_players_card_and_emblem_are_dimmed() -> void:
	var hud := _hud(3)
	hud.state.set_player_plate(OTHER, &"cartoon", &"cartoon")
	var box := _box(hud, OTHER)
	assert_float(box._card.dim).is_equal(0.0)
	hud.state.team[OTHER]["downed"] = true
	hud.points.refresh()
	assert_float(box._card.dim).is_equal(HudPlayerBox.CARD_DOWN)
	assert_float(box._emblem.dim).is_equal(HudPlayerBox.CARD_DOWN)


func test_the_strip_is_drawn_by_the_points_tab_and_adds_no_canvas_item_to_a_box() -> void:
	# The night's canvas-item budget (tools/perf/budget.json) is full: the strip is data the points
	# tab draws, not a node of its own, and its opacity is the one constant.
	var hud := _hud(BIG_PARTY)
	hud.state.set_player_plate(OTHER, &"cartoon", &"headliner")
	var box := _box(hud, OTHER)
	assert_object(box._tab.strip).is_same(box._name_tab)
	var items := 0
	for child in box.get_children():
		if child is CanvasItem:
			items += 1
	var bare := _box(_hud(BIG_PARTY), OTHER)
	var bare_items := 0
	for child in bare.get_children():
		if child is CanvasItem:
			bare_items += 1
	assert_int(items).is_equal(bare_items)
	assert_float(box._name_tab.drawn_colour().a).is_equal(box._name_tab.colour.a * HudNameTab.ALPHA)
	assert_array(box._name_tab.outline()).has_size(4)
