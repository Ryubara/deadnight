# The HUD sits on one grid: the cards of a column share an edge, the text inside them shares a left
# and a right line, the gaps between parts are one distance, and no label leaves the part that
# holds it. Measured from the laid-out rectangles at several window sizes (#218): the canvas the
# window gives (1920 x 1080 and up; 720p and the UI scale setting give the smallest).
extends GdUnitTestSuite

const Layout := preload("res://tests/ui/test_hud_layout.gd")
const WINDOWS: Array[Vector2] = [
	Vector2(1280, 720),
	Vector2(1920, 1080),
	Vector2(2560, 1440),
	Vector2(3840, 2160),
	Vector2(1024, 768),
]
const UI_SCALES: Array[float] = [0.8, 1.0, 1.25]
## Rectangles are float sums; an edge counts as shared within this many canvas units.
const EDGE := 0.51


func before_test() -> void:
	UIMotion.reduced = false


func after_test() -> void:
	HudFonts.reset()


## A busy night's HUD on `canvas`: four players, a banner done, feeds, a prompt, the panel up.
func _busy(canvas: Vector2) -> Hud:
	var host: Control = auto_free(Control.new())
	host.size = canvas
	add_child(host)
	var fixture := HudFixture.make(host, 4)
	fixture.into_round_one()
	var state := fixture.hud.state
	state.set_ammo(30, 150, "Shotgun")
	state.set_equipment("Flare gun", 2)
	state.set_area("The Concession Stand", "Light the booth to open the back lot")
	state.set_prompt(&"buy_door", "Projection booth door", 750)
	fixture.act(RulesAction.set_downed(2, true))
	for text in ["RUBY OPENED THE PROJECTION BOOTH", "GENERATOR RUNNING LOW", "MOE IS DOWN"]:
		fixture.hud.events_feed.push(text)
	fixture.hud.notices.push("CAL CONNECTED")
	for amount in [100, 60]:
		fixture.hud.gains.add_gain(&"kill", amount)
	fixture.hud.fuel.peek()
	fixture.advance(HudTuning.current().fuel_in + 0.1)
	return fixture.hud


func _canvases() -> Array[Vector2]:
	var seen := {}
	var list: Array[Vector2] = []
	for window in WINDOWS:
		for ui_scale in UI_SCALES:
			var canvas := Layout.canvas_for(window, ui_scale)
			var key := Vector2i(canvas.round())
			if not seen.has(key):
				seen[key] = true
				list.append(canvas)
	return list


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= EDGE


## The visible labels under `node`, in tree order.
func _labels(node: Node, found: Array[Label]) -> Array[Label]:
	if node is Label and (node as Label).is_visible_in_tree():
		found.append(node)
	for child in node.get_children():
		_labels(child, found)
	return found


## What is out of line in the laid-out HUD, as sentences.
func _problems(hud: Hud, canvas: Vector2) -> Array[String]:
	var found: Array[String] = []
	var margin := float(HudStyle.margin())
	var pad_left := float(HudStyle.PAD_LEFT)
	var pad := float(HudStyle.PAD)

	# The left column: one left edge, one gap between parts, the stack on the margin.
	var top: Array[Control] = [hud.round_part, hud.objective]
	var bottom: Array[Control] = []
	for id in hud.points.order():
		bottom.append(hud.points.box_of(id))
	bottom.append(hud.health)
	for part in top + bottom:
		var rect := part.get_global_rect()
		if not _near(rect.position.x, margin):
			found.append(
				"%s starts at x %.1f, not the margin %.0f" % [part.name, rect.position.x, margin]
			)
	for stack: Array[Control] in [top, bottom]:
		for i in range(1, stack.size()):
			var gap: float = (
				stack[i].get_global_rect().position.y - stack[i - 1].get_global_rect().end.y
			)
			if not _near(gap, float(HudStyle.GAP)):
				found.append("gap before %s is %.1f, not %d" % [stack[i].name, gap, HudStyle.GAP])
	if not _near(hud.round_part.get_global_rect().position.y, margin):
		found.append("the round card is not on the top margin")
	if not _near(hud.health.get_global_rect().end.y, canvas.y - margin):
		found.append("the health card is not on the bottom margin")

	# The right column: one right edge, the text on one right line.
	var right_edge := canvas.x - margin
	for part: Control in [hud.fuel.panel, hud.ammo]:
		if not _near(part.get_global_rect().end.x, right_edge):
			found.append(
				(
					"%s ends at x %.1f, not %.0f"
					% [part.name, part.get_global_rect().end.x, right_edge]
				)
			)
	if not _near(hud.ammo.get_global_rect().end.y, canvas.y - margin):
		found.append("the ammo card is not on the bottom margin")
	if not _near(hud.fuel.panel.get_global_rect().position.y, margin):
		found.append("the generator card is not on the top margin")
	var text_right := right_edge - pad
	for feed: HudFeed in [hud.events_feed, hud.notices]:
		for row: Dictionary in feed.rows:
			var label: Label = row["label"]
			if not _near(label.get_global_rect().end.x, text_right):
				found.append(
					(
						"a %s row ends at x %.1f, not the text line %.1f"
						% [feed.name, label.get_global_rect().end.x, text_right]
					)
				)

	# Inside a card the text starts on one line and ends before another.
	for card: HudTicket in [hud.round_part, hud.objective, hud.health, hud.fuel.panel]:
		var rect := card.get_global_rect()
		for label in _labels(card, []):
			var first := (
				label.get_parent() == card.body
				or (label.get_parent().get_parent() == card.body and label.get_index() == 0)
			)
			var at := label.get_global_rect().position.x
			if first and not _near(at, rect.position.x + pad_left):
				found.append(
					(
						'%s\'s "%s" starts at %.1f, not %.1f'
						% [card.name, label.text, at, rect.position.x + pad_left]
					)
				)
			if label.get_global_rect().end.x > rect.end.x - pad + EDGE:
				found.append('%s\'s "%s" runs past the right text line' % [card.name, label.text])

	# No label leaves its part, whatever it says.
	for part in hud.boxed_parts():
		if not part.is_visible_in_tree():
			continue
		var bounds := part.get_global_rect().grow(EDGE)
		for label in _labels(part, []):
			if not bounds.encloses(label.get_global_rect()):
				found.append(
					(
						'%s\'s "%s" %s leaves %s'
						% [part.name, label.text, label.get_global_rect(), bounds]
					)
				)
	return found


func _check(face: StringName) -> void:
	if not HudFonts.apply(face):
		return
	var problems: Array[String] = []
	for canvas in _canvases():
		var hud := _busy(canvas)
		await _settle()
		for problem in _problems(hud, canvas):
			problems.append("%s, canvas %s: %s" % [face, canvas, problem])
		hud.get_parent().queue_free()
	HudFonts.reset()
	assert_array(problems).is_empty()


func test_the_hud_sits_on_the_grid_at_every_canvas() -> void:
	await _check(HudFonts.FALLBACK)


func test_the_hud_sits_on_the_grid_in_a_wide_typeface() -> void:
	await _check(HudFonts.WIDE)


func test_the_hud_sits_on_the_grid_in_the_marquee_typeface_when_its_files_exist() -> void:
	await _check(HudFonts.MARQUEE)


func test_the_hud_is_smaller_than_the_first_draft_at_1080p() -> void:
	# The side columns take under a fifth of a 1920-wide canvas, the ammo card under a seventh.
	var hud := _busy(Vector2(1920, 1080))
	await _settle()
	assert_float(hud.round_part.size.x).is_less_equal(1920.0 * 0.2)
	assert_float(hud.fuel.panel.size.x).is_less_equal(1920.0 * 0.2)
	assert_float(hud.ammo.size.x).is_less_equal(1920.0 / 7.0)
	# And the type is still readable: nothing under the minimum, 13 px at 720p.
	for label in _labels(hud, []):
		assert_int(label.get_theme_font_size(&"font_size")).is_greater_equal(HudStyle.MIN_TEXT)
	(
		assert_float(HudStyle.MIN_TEXT * Layout.pixels_per_unit(Vector2(1280, 720), 1.0))
		. is_greater_equal(13.0)
	)
