# The perk badges beside the health card and the DOWN card's self-revive (#707): what the HUD state
# makes of the frame's perk bits and self-revive seconds, and where the badges stand at the canvases
# the game runs at, for either hand and with the touch controls up. The night itself (a purchase
# through the machine, a down, the perk getting the holder up) is
# `tests/night/test_night_perk_hud.gd`.
extends GdUnitTestSuite

## Canvases (canvas units): the smallest the game gives (720p at UI scale 1.25), full HD, a 16:9 and
## a 20:9 phone held sideways.
const CANVASES: Array[Vector2] = [
	Vector2(1536.0, 864.0),
	Vector2(1920.0, 1080.0),
	Vector2(2340.0, 1080.0),
	Vector2(2400.0, 1080.0),
]
## The smallest a badge may be on screen, in pixels, at the smallest window the game runs at (720p,
## UI scale 1.25).
const READABLE_PX := 36.0

var _host: Control


func before_test() -> void:
	UIMotion.reduced = false


func _fixture(canvas := CANVASES[1], players := 4) -> HudFixture:
	_host = auto_free(Control.new())
	_host.size = canvas
	add_child(_host)
	var fixture := HudFixture.make(_host, players)
	fixture.into_round_one()
	return fixture


func _ids(fixture: HudFixture) -> Array[StringName]:
	return PerkEffects.tonic_ids(fixture.rules.tuning.economy)


func test_there_is_a_badge_for_each_perk_in_the_shops_order_and_none_without() -> void:
	var fixture := _fixture()
	var hud := fixture.hud
	assert_bool(hud.perks.visible).is_false()
	assert_array(hud.perks.shown()).is_empty()
	var ids := _ids(fixture)
	hud.state.set_perks([ids[2], ids[0]] as Array[StringName])
	assert_array(hud.perks.shown()).is_equal([ids[2], ids[0]])
	assert_bool(hud.perks.visible).is_true()
	hud.state.set_perks([ids[0], ids[1], ids[2]] as Array[StringName])
	assert_array(hud.perks.shown()).is_equal([ids[0], ids[1], ids[2]])
	hud.state.set_perks([] as Array[StringName])
	assert_array(hud.perks.shown()).is_empty()
	assert_bool(hud.perks.visible).is_false()
	assert_int(hud.perks.get_child_count()).is_equal(0)


func test_a_frame_said_twice_changes_nothing_and_a_badge_is_kept_not_remade() -> void:
	var fixture := _fixture()
	var hud := fixture.hud
	fixture.give_perks(2)
	var first: HudPerkBadge = hud.perks.badges()[0]
	var changes := [0]
	hud.state.changed.connect(func() -> void: changes[0] += 1)
	fixture.give_perks(2)
	assert_int(changes[0]).is_equal(0)
	fixture.give_perks(3)
	assert_object(hud.perks.badges()[0]).is_same(first)
	assert_int(hud.perks.badges().size()).is_equal(3)


func test_the_frames_bits_make_the_tonics_the_hud_shows() -> void:
	var economy := (load(HudFixture.TUNING) as RulesTuning).economy
	var ids := PerkEffects.tonic_ids(economy)
	assert_array(PerkEffects.mask_tonics(economy, 0)).is_empty()
	assert_array(PerkEffects.mask_tonics(economy, (1 << 4) | (1 << 1))).is_equal([ids[1], ids[4]])
	for id in ids:
		var mask := 0
		for at in ids.size():
			if ids[at] == id:
				mask = 1 << at
		assert_array(PerkEffects.mask_tonics(economy, mask)).is_equal([id])
		assert_bool(PerkEffects.mask_has(economy, mask, id)).is_true()


func test_every_perk_has_its_own_picture_and_a_colour_the_picture_can_be_read_on() -> void:
	var economy := (load(HudFixture.TUNING) as RulesTuning).economy
	var seen_glyphs := {}
	var seen_grounds := {}
	for id in PerkEffects.tonic_ids(economy):
		var look := HudPerkBadge.look_of(id)
		assert_bool(look["glyph"] == HudPerkBadge.Glyph.BOTTLE).is_false()
		seen_glyphs[look["glyph"]] = id
		seen_grounds[(look["ground"] as Color).to_html()] = id
		# Light picture on a dark ground: the difference in brightness carries it, not the hue.
		var ground: Color = look["ground"]
		var glow: Color = look["glow"]
		(
			assert_float(glow.get_luminance() - ground.get_luminance())
			. override_failure_message("%s: the picture is hard to read on its ground" % id)
			. is_greater(0.4)
		)
	assert_int(seen_glyphs.size()).is_equal(PerkEffects.tonic_ids(economy).size())
	assert_int(seen_grounds.size()).is_equal(PerkEffects.tonic_ids(economy).size())
	# A tonic nobody drew an emblem for still gets a badge.
	assert_int(HudPerkBadge.glyph_of(&"tonic_unheard_of")).is_equal(HudPerkBadge.Glyph.BOTTLE)


func test_the_badges_stand_beside_the_health_card_at_its_bottom_on_every_canvas() -> void:
	var problems: Array[String] = []
	for canvas in CANVASES:
		for mirrored in [false, true]:
			for touch in [false, true]:
				for count in [1, 2, 4]:
					var fixture := _fixture(canvas)
					var hud := fixture.hud
					hud.mirrored = mirrored
					hud.touch_layout = touch
					fixture.give_perks(count)
					fixture.act(RulesAction.set_downed(2, true))
					await await_idle_frame()
					await await_idle_frame()
					var label := (
						"%s %d perks mirrored %s touch %s" % [canvas, count, mirrored, touch]
					)
					problems.append_array(_beside_the_card(hud, canvas, label))
					_host.free()
	assert_array(problems).is_empty()


func _beside_the_card(hud: Hud, canvas: Vector2, label: String) -> Array[String]:
	var found: Array[String] = []
	var perks := hud.perks.get_global_rect()
	var card := hud.health.get_global_rect()
	if not Rect2(Vector2.ZERO, canvas).encloses(perks):
		found.append("%s: the badges %s leave the canvas" % [label, perks])
	if absf(perks.end.y - card.end.y) > 1.0:
		found.append("%s: the badges end at %s, the card at %s" % [label, perks.end.y, card.end.y])
	var gap := perks.position.x - card.end.x if not hud.mirrored else card.position.x - perks.end.x
	if gap < 1.0 or gap > 24.0:
		found.append("%s: %s units between the card and the badges" % [label, gap])
	for part in hud.boxed_parts():
		if part == hud.perks or not part.is_visible_in_tree():
			continue
		if part.get_global_rect().intersects(perks):
			found.append("%s: the badges touch %s %s" % [label, part.name, part.get_global_rect()])
	return found


func test_a_badge_is_big_enough_to_read_at_the_smallest_window() -> void:
	var window := 720.0
	var pixels_per_unit := (window / 1080.0) * 1.25
	assert_float(HudPerkBadge.SIDE * pixels_per_unit).is_greater_equal(READABLE_PX)


func test_the_badges_follow_the_card_when_the_touch_controls_move_the_slot_strip_under_it() -> void:
	var fixture := _fixture(CANVASES[2])
	var hud := fixture.hud
	fixture.give_perks(2)
	await await_idle_frame()
	await await_idle_frame()
	var before := hud.perks.get_global_rect()
	hud.touch_layout = true
	await await_idle_frame()
	await await_idle_frame()
	var after := hud.perks.get_global_rect()
	# The strip now sits under the health card, so the card (and the badges with it) moved up.
	assert_float(after.end.y).is_less(before.end.y)
	assert_float(after.end.y).is_equal_approx(hud.health.get_global_rect().end.y, 1.0)


func test_the_badges_keep_inside_the_safe_area_with_the_hud() -> void:
	var fixture := _fixture(CANVASES[2])
	var hud := fixture.hud
	fixture.give_perks(4)
	hud.set_safe_insets(Vector4(96.0, 0.0, 96.0, 24.0))
	await await_idle_frame()
	await await_idle_frame()
	var safe := Rect2(Vector2(96.0, 0.0), CANVASES[2] - Vector2(192.0, 24.0))
	assert_bool(safe.encloses(hud.perks.get_global_rect())).is_true()
	assert_float(hud.perks.get_global_rect().end.y).is_equal_approx(
		hud.health.get_global_rect().end.y, 1.0
	)


# --- The DOWN card ---


## What the frame adds for a downed player: the bleed-out clock and the perk's own count.
func _frame(fixture: HudFixture, bleed: float, self_revive: float) -> void:
	fixture.hud.state.set_player_revive(1, false, bleed, 0.0, 0, self_revive)


func test_the_down_card_counts_the_self_revive_down_while_the_bleed_clock_stands_still() -> void:
	var fixture := _fixture(CANVASES[1], 1)
	var hud := fixture.hud
	fixture.act(RulesAction.set_downed(1, true))
	_frame(fixture, 45.0, 0.0)
	assert_str(hud.health.hint_text).is_equal("BLEEDING OUT  45 S")
	_frame(fixture, 45.0, 4.0)
	assert_str(hud.health.down_text).is_equal("DOWN")
	assert_str(hud.health.hint_text).is_equal("GETTING YOURSELF UP  4 S")
	_frame(fixture, 45.0, 2.5)
	assert_str(hud.health.hint_text).is_equal("GETTING YOURSELF UP  3 S")
	_frame(fixture, 45.0, 0.2)
	assert_str(hud.health.hint_text).is_equal("GETTING YOURSELF UP  1 S")


func test_the_ring_over_the_view_says_the_same_and_fills_as_the_count_goes() -> void:
	var fixture := _fixture(CANVASES[1], 1)
	var hud := fixture.hud
	fixture.act(RulesAction.set_downed(1, true))
	_frame(fixture, 45.0, 0.0)
	assert_int(hud.revive.mode).is_equal(HudRevive.Mode.DOWNED)
	var total := hud.state.self_revive_total
	_frame(fixture, 45.0, total)
	assert_int(hud.revive.mode).is_equal(HudRevive.Mode.SELF_REVIVING)
	assert_str(hud.revive.line_text).is_equal("GETTING YOURSELF UP")
	assert_str(hud.revive.number_text).is_equal(str(ceili(total)))
	assert_float(hud.revive.fraction).is_equal_approx(0.0, 0.001)
	_frame(fixture, 45.0, total * 0.25)
	assert_float(hud.revive.fraction).is_equal_approx(0.75, 0.001)


func test_up_again_the_card_and_the_ring_go_back_to_normal() -> void:
	var fixture := _fixture(CANVASES[1], 1)
	var hud := fixture.hud
	fixture.act(RulesAction.set_downed(1, true))
	_frame(fixture, 45.0, 3.0)
	fixture.act(RulesAction.set_downed(1, false))
	fixture.hud.state.set_player_revive(1, false, 0.0, 0.0, 0, 0.0)
	assert_bool(hud.health.shown_downed).is_false()
	assert_bool(hud.state.is_local_self_reviving()).is_false()
	assert_int(hud.revive.mode).is_equal(HudRevive.Mode.NONE)


func test_a_late_joiner_reads_the_count_from_the_snapshot_and_the_event_starts_it() -> void:
	var fixture := _fixture(CANVASES[1], 1)
	var state := fixture.hud.state
	fixture.act(RulesAction.set_downed(1, true))
	state.apply_event({"type": &"self_revive_started", "player_id": 1, "seconds": 4.0})
	assert_bool(state.is_local_self_reviving()).is_true()
	assert_str(fixture.hud.health.hint_text).is_equal("GETTING YOURSELF UP  4 S")
	var data := fixture.rules.to_dict()
	data["players"][1]["self_revive_left"] = 2.2
	state.load_snapshot(data)
	assert_float(float(state.team[1]["self_revive"])).is_equal_approx(2.2, 0.001)
