extends GdUnitTestSuite
## An objective's name and distance are never under a card of the HUD (Deadnight #1192): the label
## beside a marker was drawn under the health card (`SSION STAND 30 m`) when the marker stood near a
## corner. A marker is put on a grid over the whole screen, corners and edges included, off the
## screen too (it pins to an edge), on every canvas a window and an interface size give (a phone's
## night has no phone factor), with the busiest HUD, and the words are read where they were drawn.

const WINDOWS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(1024, 768),
	Vector2i(2560, 1080),
	Vector2i(844, 390),
	Vector2i(932, 430),
	Vector2i(667, 375),
]
const UI_SCALES: Array[float] = [0.8, 1.0, 1.25]
const LABELS: Array[String] = ["Concession Stand", "Projection Booth Door", ""]
## The grid's steps across the screen: the edges and the corners are on it, and so is outside.
const STEPS: Array[float] = [-0.3, 0.0, 0.05, 0.12, 0.2, 0.35, 0.5, 0.65, 0.8, 0.9, 0.96, 1.0, 1.3]
const DISTANCES: Array[float] = [3.0, 30.0, 120.0]


func after_test() -> void:
	UIMotion.reduced = false


## The busiest corners: eight players, the round and the objective, perks, slots, the feeds.
func _busy_hud(canvas: Vector2, insets: Vector4, mirrored: bool, touch := false) -> HudFixture:
	var host: Control = auto_free(Control.new())
	host.size = canvas
	add_child(host)
	var fixture := HudFixture.make(host, NightHost.MAX_PLAYERS)
	var hud := fixture.hud
	hud.mirrored = mirrored
	hud.touch_layout = touch
	hud.set_safe_insets(insets)
	fixture.into_round_one()
	var state := hud.state
	state.set_ammo(30, 150, "Shotgun")
	state.set_equipment("Flare", 2)
	state.set_area("The Concession Stand", "Light the booth to open the back lot")
	fixture.give_perks(fixture.rules.tuning.economy.max_tonics)
	fixture.act(RulesAction.set_downed(2, true))
	for text in ["RUBY OPENED THE PROJECTION BOOTH", "GENERATOR RUNNING LOW", "MOE IS DOWN"]:
		hud.events_feed.push(text)
	hud.notices.push("CAL CONNECTED")
	hud.fuel.peek()
	fixture.advance(1.0)
	return fixture


func _markers() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var n := 0
	for x in STEPS:
		for y in STEPS:
			var label: String = LABELS[n % LABELS.size()]
			var distance: float = DISTANCES[(n / LABELS.size()) % DISTANCES.size()]
			list.append(
				HudFixture.late_marker(
					StringName("m%d" % n), &"objective", x, y, distance, label, false
				)
			)
			n += 1
	return list


## The words of a marker that sit under a card, in sentences.
func _faults(fixture: HudFixture, where: String) -> Array[String]:
	var hud := fixture.hud
	var found: Array[String] = []
	var markers := hud.markers
	var origin := markers.get_global_rect().position
	var screen := Rect2(Vector2.ZERO, markers.size)
	for card in hud.corner_cards():
		if not card.is_visible_in_tree() or card.size == Vector2.ZERO:
			continue
		var rect := Rect2(card.get_global_rect().position - origin, card.size)
		for id: StringName in markers.labels:
			var words: Rect2 = markers.labels[id]
			if words.intersects(rect):
				found.append("%s: %s %s is under %s %s" % [where, id, words, card.name, rect])
	for id: StringName in markers.labels:
		var words: Rect2 = markers.labels[id]
		if not screen.encloses(words):
			found.append("%s: %s %s leaves the screen %s" % [where, id, words, screen])
	assert_int(markers.labels.size()).is_greater(0)
	return found


func _canvas(window: Vector2i, ui_scale: float) -> Vector2:
	return Vector2(window) / MenuScale.pixels_per_unit(window, ui_scale)


func _run(mirrored: bool, touch := false) -> Array[String]:
	var found: Array[String] = []
	for window in WINDOWS:
		for ui_scale in UI_SCALES:
			var canvas := _canvas(window, ui_scale)
			var insets := (
				Vector4(96.0, 0.0, 96.0, 24.0) if window.x > window.y * 2 else Vector4.ZERO
			)
			var fixture := _busy_hud(canvas, insets, mirrored, touch)
			await await_idle_frame()
			await await_idle_frame()
			fixture.hud.state.set_markers(_markers())
			await await_idle_frame()
			await await_idle_frame()
			var where := (
				"%s at %s%s%s"
				% [window, ui_scale, ", mirrored" if mirrored else "", ", touch" if touch else ""]
			)
			found.append_array(_faults(fixture, where))
			fixture.hud.get_parent().queue_free()
	return found


func test_an_objectives_words_are_never_under_a_card_on_any_screen() -> void:
	assert_array(await _run(false)).is_empty()


func test_an_objectives_words_are_never_under_a_card_for_a_left_hand() -> void:
	assert_array(await _run(true)).is_empty()


func test_an_objectives_words_are_never_under_a_card_with_the_touch_layout() -> void:
	# The weapon slots move under the health card with the touch controls up.
	assert_array(await _run(false, true)).is_empty()
