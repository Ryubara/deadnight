# The HUD at every screen size the game runs at, and with reduced motion. The project stretches
# the canvas (1920 x 1080, expanding to the window shape) and the UI scale setting divides it
# again, so a window from 720p to 4K and a scale of 0.8 to 1.25 give canvases from 1536 x 864 up;
# the HUD must fit each with its busiest content on screen, and stay readable in pixels.
extends GdUnitTestSuite

const BASE := Vector2(1920.0, 1080.0)
const WINDOWS: Array[Vector2] = [
	Vector2(1280, 720),
	Vector2(1920, 1080),
	Vector2(2560, 1440),
	Vector2(3840, 2160),
	Vector2(1024, 768),
	Vector2(2560, 1080),
	Vector2(1366, 768),
]
const UI_SCALES: Array[float] = [0.8, 1.0, 1.25]
## Smallest text height in screen pixels: at the default UI scale, and at the smallest setting.
const READABLE_PX := 16.0
const READABLE_SMALL_PX := 12.0


## The canvas the window gives the UI: stretch "canvas_items", aspect "expand", then the UI scale.
static func canvas_for(window: Vector2, ui_scale: float) -> Vector2:
	var fit := minf(window.x / BASE.x, window.y / BASE.y)
	return window / (fit * ui_scale)


static func pixels_per_unit(window: Vector2, ui_scale: float) -> float:
	return minf(window.x / BASE.x, window.y / BASE.y) * ui_scale


func before_test() -> void:
	UIMotion.reduced = false


## A HUD showing everything at once, as in the worst moment of a four-player night. With `worst` it
## also holds the longest content the game allows (see `HudFixture.fill_worst_case`).
func _busy_hud(canvas: Vector2, worst := false) -> HudFixture:
	var host: Control = auto_free(Control.new())
	host.size = canvas
	add_child(host)
	var fixture := HudFixture.make(host, 4)
	var hud := fixture.hud
	fixture.into_round_one()
	var state := hud.state
	state.set_ammo(30, 150, "Shotgun")
	state.set_equipment("Flare", 2)
	state.set_area("The Concession Stand", "Light the booth to open the back lot")
	state.set_prompt(&"buy_door", "Projection booth door", 750)
	fixture.act(RulesAction.set_downed(2, true))
	fixture.act(RulesAction.set_downed(1, true))
	hud.banner.show_banner("ROUND 100 SURVIVED", "CATCH YOUR BREATH", HudBanner.Rank.ROUND)
	for text in ["RUBY OPENED THE PROJECTION BOOTH", "GENERATOR RUNNING LOW", "MOE IS DOWN"]:
		hud.events_feed.push(text)
	hud.notices.push("CAL CONNECTED")

	for amount in [100, 60, 130, 60]:
		hud.gains.add_gain(&"kill", amount)
	fixture.advance(HudBanner.IN_TIME + 0.1)
	if worst:
		fixture.fill_worst_case()
	return fixture


## What is wrong with the laid-out HUD: parts leaving the canvas or overlapping each other.
func _problems(fixture: HudFixture, canvas: Vector2, label: String) -> Array[String]:
	await await_idle_frame()
	await await_idle_frame()
	var found: Array[String] = []
	var bounds := Rect2(Vector2.ZERO, canvas)
	var parts := fixture.hud.boxed_parts()
	for part in parts:
		if part.is_visible_in_tree() and not bounds.encloses(part.get_global_rect()):
			found.append("%s: %s %s leaves %s" % [label, part.name, part.get_global_rect(), bounds])
	for i in parts.size():
		for j in range(i + 1, parts.size()):
			if not (parts[i].is_visible_in_tree() and parts[j].is_visible_in_tree()):
				continue
			var overlap := parts[i].get_global_rect().intersection(parts[j].get_global_rect())
			if overlap.has_area():
				found.append(
					"%s: %s overlaps %s by %s" % [label, parts[i].name, parts[j].name, overlap.size]
				)
	return found


func _canvases() -> Array[Vector2]:
	var seen := {}
	var list: Array[Vector2] = []
	for window in WINDOWS:
		for ui_scale in UI_SCALES:
			var canvas := canvas_for(window, ui_scale)
			var key := Vector2i(canvas.round())
			if not seen.has(key):
				seen[key] = true
				list.append(canvas)
	return list


func _fits_everywhere(face: StringName, worst: bool) -> void:
	if not HudFonts.apply(face):
		return
	var problems: Array[String] = []
	for canvas in _canvases():
		var fixture := _busy_hud(canvas, worst)
		var label := "%s, %s, canvas %s" % [face, "worst case" if worst else "busy", canvas]
		problems.append_array(await _problems(fixture, canvas, label))
		fixture.hud.get_parent().queue_free()
	HudFonts.reset()
	assert_array(problems).is_empty()


func after_test() -> void:
	HudFonts.reset()
	UIMotion.reduced = false


func test_the_busiest_hud_fits_every_canvas_without_overlap() -> void:
	await _fits_everywhere(HudFonts.FALLBACK, false)


func test_the_busiest_hud_fits_in_a_wide_typeface() -> void:
	await _fits_everywhere(HudFonts.WIDE, false)


func test_the_busiest_hud_fits_in_the_marquee_typeface_when_its_files_exist() -> void:
	await _fits_everywhere(HudFonts.MARQUEE, false)


func test_the_longest_content_fits_every_canvas_in_the_fallback_face() -> void:
	await _fits_everywhere(HudFonts.FALLBACK, true)


func test_the_longest_content_fits_every_canvas_in_a_wide_typeface() -> void:
	await _fits_everywhere(HudFonts.WIDE, true)


func test_the_longest_content_fits_every_canvas_in_the_marquee_typeface_when_its_files_exist(
) -> void:
	await _fits_everywhere(HudFonts.MARQUEE, true)


func test_the_cards_keep_their_size_whatever_they_say() -> void:
	var canvas := Vector2(1536, 864)
	for face in HudFonts.available():
		HudFonts.apply(face)
		var short := _busy_hud(canvas, false)
		var long := _busy_hud(canvas, true)
		await await_idle_frame()
		await await_idle_frame()
		var label := "%s" % face
		# Width is the card's own; the prompt and the ammo card never grow with their content.
		assert_float(long.hud.prompt.size.x).override_failure_message(label).is_equal(HudStyle.CARD)
		assert_float(long.hud.ammo.size.x).override_failure_message(label).is_equal(HudAmmo.WIDTH)
		assert_float(long.hud.prompt.size.y).override_failure_message(label).is_equal_approx(
			short.hud.prompt.size.y, 40.0
		)
		assert_float(long.hud.points.size.x).override_failure_message(label).is_less_equal(
			HudStyle.COLUMN
		)
		short.hud.get_parent().queue_free()
		long.hud.get_parent().queue_free()
	HudFonts.reset()


func test_the_words_beside_the_generator_bulbs_fit_their_slots() -> void:
	for face in HudFonts.available():
		HudFonts.apply(face)
		var host: Control = auto_free(Control.new())
		host.size = Vector2(1536, 864)
		add_child(host)
		var fixture := HudFixture.make(host, 1)
		var fuel := fixture.hud.fuel
		var font := UITokens.active().text_font(0.0, HudFuel.WORD_TRACKING)
		var slot := fuel.word_slot(fuel._gauge.custom_minimum_size.x)
		assert_int(fuel.circuit_words.size()).is_greater(0)
		for word in fuel.circuit_words.values():
			(
				assert_float(HudStyle.text_width(font, word, HudStyle.MIN_TEXT))
				. override_failure_message("%s: %s is wider than its slot" % [face, word])
				. is_less_equal(slot)
			)
		host.queue_free()
	HudFonts.reset()


func test_a_name_the_state_keeps_still_fits_the_party_and_the_points_caption() -> void:
	var canvas := Vector2(1536, 864)
	for face in HudFonts.available():
		HudFonts.apply(face)
		var fixture := _busy_hud(canvas, true)
		await await_idle_frame()
		await await_idle_frame()
		var hud := fixture.hud
		# The word after the name always survives; the name is what is cut.
		assert_str(hud.points.caption_text).ends_with("POINTS")
		for row: Dictionary in hud.team._lines.values():
			var name_label: Label = row["name"]
			assert_float(name_label.size.x).is_equal_approx(HudTeam.NAME_WIDTH, 0.5)
		hud.get_parent().queue_free()
	HudFonts.reset()


func test_the_smallest_text_stays_readable_in_pixels() -> void:
	for window in WINDOWS:
		for ui_scale in UI_SCALES:
			var px := HudStyle.MIN_TEXT * pixels_per_unit(window, ui_scale)
			var floor_px := READABLE_SMALL_PX if ui_scale < 1.0 else READABLE_PX
			if window.x < 1280.0:
				continue
			(
				assert_float(px)
				. override_failure_message("%s at %.2f gives %.1f px text" % [window, ui_scale, px])
				. is_greater_equal(floor_px)
			)


func test_every_hud_label_is_at_least_the_minimum_size() -> void:
	var host: Control = auto_free(Control.new())
	host.size = BASE
	add_child(host)
	var fixture := HudFixture.make(host, 4)
	var small: Array[String] = []
	_collect_small_labels(fixture.hud, small)
	assert_array(small).is_empty()


func _collect_small_labels(node: Node, found: Array[String]) -> void:
	if node is Label:
		var size_px := (node as Label).get_theme_font_size(&"font_size")
		if size_px < HudStyle.MIN_TEXT:
			found.append("%s is %d" % [node.name, size_px])
	for child in node.get_children():
		_collect_small_labels(child, found)


# --- Reduced motion ---


func test_reduced_motion_removes_movement_and_keeps_the_information() -> void:
	UIMotion.reduced = true
	var host: Control = auto_free(Control.new())
	host.size = BASE
	add_child(host)
	var fixture := HudFixture.make(host, 2)
	var hud := fixture.hud
	fixture.into_round_one()
	# The banner appears at full size and fades, it does not grow.
	assert_vector(hud.banner.scale).is_equal(Vector2.ONE)
	assert_str(hud.banner.title).is_equal("ROUND 1")
	# A damage number does not rise; the gain list still lists.
	var ids := fixture.spawn(1)
	fixture.act(RulesAction.hit(1, ids[0], RulesAction.ZONE_HEAD, 30.0))
	var start_at: Vector2 = hud.crosshair.numbers[0]["at"]
	hud.crosshair.advance(0.4)
	assert_vector(hud.crosshair.numbers[0]["at"]).is_equal(start_at)
	assert_array(hud.gains.texts()).is_not_empty()
	# Every reel digit changes at once, with no roll.
	hud.state.apply_event({"type": &"round_started", "round": 7, "zombie_count": 20})
	assert_str(hud.round_part.number_text).is_equal("07")
	for reel in hud.round_part._reels.get_children():
		assert_float(reel._roll).is_equal(1.0)


# --- The typeface token ---


func test_the_faces_come_from_the_tokens_and_fall_back_cleanly() -> void:
	var tokens := UITokens.new()
	assert_object(tokens.font_display).is_null()
	assert_object(tokens.display_font().base_font).is_same(ThemeDB.fallback_font)
	var face := SystemFont.new()
	tokens.font_display = face
	tokens.font_text = face
	assert_object(tokens.display_font().base_font).is_same(face)
	assert_object(tokens.text_font(0.2, 3.0).base_font).is_same(face)
	assert_int(tokens.text_font(0.2, 3.0).spacing_glyph).is_equal(3)
	# A label made by the HUD takes the face of the active tokens.
	var before := UITokens.active()
	UITokens.set_active(tokens)
	var label := HudStyle.label("A", 30, Color.WHITE, true)
	UITokens.set_active(before)
	assert_object((label.get_theme_font(&"font") as FontVariation).base_font).is_same(face)
	label.free()
