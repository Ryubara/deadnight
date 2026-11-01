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


func after_test() -> void:
	UIMotion.reduced = false


## A HUD showing everything at once, as in the worst moment of a four-player night.
func _busy_hud(canvas: Vector2) -> HudFixture:
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
	return fixture


func _check_fits(fixture: HudFixture, canvas: Vector2, label: String) -> void:
	await await_idle_frame()
	await await_idle_frame()
	var bounds := Rect2(Vector2.ZERO, canvas)
	var parts := fixture.hud.boxed_parts()
	for part in parts:
		if not part.is_visible_in_tree():
			continue
		var rect := part.get_global_rect()
		(
			assert_bool(bounds.encloses(rect))
			. override_failure_message("%s: %s %s leaves %s" % [label, part.name, rect, bounds])
			. is_true()
		)
	for i in parts.size():
		for j in range(i + 1, parts.size()):
			if not (parts[i].is_visible_in_tree() and parts[j].is_visible_in_tree()):
				continue
			var overlap := parts[i].get_global_rect().intersection(parts[j].get_global_rect())
			(
				assert_bool(overlap.has_area())
				. override_failure_message(
					"%s: %s overlaps %s by %s" % [label, parts[i].name, parts[j].name, overlap]
				)
				. is_false()
			)


func test_the_busiest_hud_fits_every_canvas_without_overlap() -> void:
	var seen := {}
	for window in WINDOWS:
		for ui_scale in UI_SCALES:
			var canvas := canvas_for(window, ui_scale)
			var key := Vector2i(canvas.round())
			if seen.has(key):
				continue
			seen[key] = true
			var fixture := _busy_hud(canvas)
			await _check_fits(
				fixture, canvas, "%s at %.2f (canvas %s)" % [window, ui_scale, canvas]
			)
			fixture.hud.get_parent().queue_free()


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
