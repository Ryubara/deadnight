# The HUD at the sizes people play at, with the values an ordinary night shows: nothing is cut. The
# layout suite proves the worst content never overlaps (and may end in an ellipsis); this one
# proves the everyday content never needs one, so an ellipsis stays a last resort (#170).
extends GdUnitTestSuite

## The window sizes the issue names; at the default UI scale both give a 1920 x 1080 canvas.
const Layout := preload("res://tests/ui/test_hud_layout.gd")
const WINDOWS: Array[Vector2] = [Vector2(1920, 1080), Vector2(2560, 1440)]
const ELLIPSIS := "…"
## What a lit-door night says: the local player is "Player 1" (what the night names them), a friend.
const NAMES := ["Player 1", "Ruby"]


## The HUD of an ordinary moment: round one, a revolver, a door in reach, a line in each feed.
func _typical_hud(canvas: Vector2) -> HudFixture:
	var host: Control = auto_free(Control.new())
	host.size = canvas
	add_child(host)
	var fixture := HudFixture.make(host, NAMES.size())
	for i in NAMES.size():
		fixture.hud.state.set_player_name(i + 1, NAMES[i])
	fixture.into_round_one()
	var state := fixture.hud.state
	state.set_health(100.0, 100.0)
	state.set_ammo(3, 30, "Revolver")
	state.set_equipment("Grenades", 3)
	state.set_area("The Concession Stand", "Light the booth to open the back lot")
	state.set_prompt(&"buy_door", "Concession stand", 350)
	state.apply_event({"type": &"circuit_changed", "circuit_id": &"booth", "on": true})
	for item in [&"door_booth", &"door_concession"]:
		state.apply_event({"type": &"purchase_made", "player_id": 1, "item_id": item})
	state.apply_event({"type": &"player_added", "player_id": 2})
	fixture.hud.banner.show_banner("ROUND 1", "", HudBanner.Rank.ROUND)
	fixture.advance(HudBanner.IN_TIME + 0.1)
	return fixture


## Every place the HUD ends a text with an ellipsis, as sentences: a label showing an ellipsis, or
## one whose text is wider than the room it was given (what its own ellipsis would then cut).
func _cuts(node: Node, found: Array[String]) -> void:
	if node is Label and (node as Label).is_visible_in_tree():
		var label := node as Label
		var font := label.get_theme_font(&"font")
		var size_px := label.get_theme_font_size(&"font_size")
		var width := HudStyle.text_width(font, label.text, size_px)
		if label.text.contains(ELLIPSIS):
			found.append('"%s" has an ellipsis' % label.text)
		elif (
			label.clip_text
			and label.autowrap_mode == TextServer.AUTOWRAP_OFF
			and width > label.size.x + 0.5
		):
			found.append('"%s" is %.0f wide in %.0f' % [label.text, width, label.size.x])
	for child in node.get_children():
		_cuts(child, found)


func _cut_text(hud: Hud) -> Array[String]:
	var found: Array[String] = []
	_cuts(hud, found)
	for word: String in hud.fuel.circuit_words.values():
		if word.contains(ELLIPSIS):
			found.append('generator word "%s" is cut' % word)
	return found


func _check(face: StringName) -> void:
	if not HudFonts.apply(face):
		return
	var problems: Array[String] = []
	for window in WINDOWS:
		var canvas := Layout.canvas_for(window, 1.0)
		var fixture := _typical_hud(canvas)
		await await_idle_frame()
		await await_idle_frame()
		for cut in _cut_text(fixture.hud):
			problems.append("%s, %s: %s" % [face, window, cut])
		fixture.hud.get_parent().queue_free()
	HudFonts.reset()
	assert_array(problems).is_empty()


func after_test() -> void:
	HudFonts.reset()


func test_ordinary_text_is_not_cut_at_1080p_and_1440p() -> void:
	await _check(HudFonts.FALLBACK)


func test_ordinary_text_is_not_cut_in_the_marquee_typeface_when_its_files_exist() -> void:
	await _check(HudFonts.MARQUEE)


func test_the_generator_names_and_the_door_line_show_in_full() -> void:
	var fixture := _typical_hud(Vector2(1920, 1080))
	await await_idle_frame()
	await await_idle_frame()
	var hud := fixture.hud
	var words: Array = hud.fuel.circuit_words.values()
	assert_array(words).contains_exactly_in_any_order(["SCREEN", "SNACKS", "BOOTH", "BACK LOT"])
	assert_array(hud.events_feed.texts()).contains(["PLAYER 1 OPENED THE CONCESSION STAND"])
	assert_array(_cut_text(hud)).is_empty()
