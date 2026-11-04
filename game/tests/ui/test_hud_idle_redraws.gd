# A HUD that is not changing is not redrawn (#948). In the Compatibility renderer a canvas item that
# is redrawn builds its polygons and glyph runs again, and a HUD is 150 or so draw calls: redrawing
# it on the clock (a `queue_redraw()` in `_process`) costs that every frame for a picture that did
# not change. The late-round HUD stands still, every timed part has run out, and the `draw` signals
# of every canvas item below it are counted over a second of frames.
extends GdUnitTestSuite

const SECOND_OF_FRAMES := 60


func _late_round() -> HudFixture:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	var fixture := HudFixture.make(host, 4)
	fixture.fill_late_round()
	# The banner, the gains, the feed and the generator panel all run out.
	fixture.advance(30.0)
	# The round's digits roll in real time (a tween): let them stop.
	await get_tree().create_timer(HudReelDigit.ROLL_SECONDS + 0.3).timeout
	await _frames(10)
	return fixture


## Starts counting the redraws of every canvas item below `hud`; returns the counts, which fill as
## frames pass.
func _watch(hud: Hud) -> Dictionary:
	var redraws := {}
	var counter := func(item: CanvasItem) -> void:
		var key := str(hud.get_path_to(item))
		redraws[key] = redraws.get(key, 0) + 1
	for item in hud.find_children("*", "CanvasItem", true, false):
		item.draw.connect(counter.bind(item))
	return redraws


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func test_a_still_late_round_hud_redraws_nothing() -> void:
	var fixture := await _late_round()
	var redraws := _watch(fixture.hud)
	await _frames(SECOND_OF_FRAMES)
	assert_dict(redraws).is_empty()


func test_the_low_fuel_pulse_redraws_nothing() -> void:
	var fixture := await _late_round()
	var hud := fixture.hud
	hud.state.apply_event({"type": &"fuel_low"})
	hud.fuel.peek()
	# The panel slides in, then holds for longer than the second counted.
	fixture.advance(HudTuning.current().fuel_in + 0.1)
	await _frames(10)
	var redraws := _watch(hud)
	var low := 1.0
	var high := 0.0
	for _i in SECOND_OF_FRAMES:
		await get_tree().process_frame
		var alpha := hud.fuel._lit.self_modulate.a
		low = minf(low, alpha)
		high = maxf(high, alpha)
	# The pulse is the alpha of the lit segments' layer: a second of it redraws no canvas item, and the
	# layer's alpha really moved.
	assert_dict(redraws).is_empty()
	assert_float(high - low).is_greater(0.2)


func test_a_change_redraws_only_what_it_changes() -> void:
	var fixture := await _late_round()
	var hud := fixture.hud
	var redraws := _watch(hud)
	hud.state.set_ammo(10, 142, "Rifle")
	await _frames(3)
	# The ammo card and nothing in the corners on the other side.
	(
		assert_bool(redraws.keys().any(func(key: String) -> bool: return key.contains("Ammo")))
		. is_true()
	)
	(
		assert_bool(redraws.keys().any(func(key: String) -> bool: return key.contains("Points")))
		. is_false()
	)
	(
		assert_bool(redraws.keys().any(func(key: String) -> bool: return key.contains("Perks")))
		. is_false()
	)


func _moved(hud: Hud, by_share: float, farther: float) -> Array[Dictionary]:
	var moved: Array[Dictionary] = []
	for marker in hud.state.markers:
		var copy := marker.duplicate()
		copy["x"] = float(marker["x"]) + by_share
		copy["distance"] = float(marker["distance"]) + farther
		moved.append(copy)
	return moved


func test_markers_that_move_a_hair_are_not_redrawn_and_markers_that_move_are() -> void:
	var fixture := await _late_round()
	var hud := fixture.hud
	var redraws := _watch(hud)
	# A marker follows the world, so its float place changes every frame: a hundredth of a unit of the
	# canvas and a tenth of a metre do not change the picture.
	hud.state.set_markers(_moved(hud, 0.00001, 0.1))
	await _frames(3)
	(
		assert_bool(redraws.keys().any(func(key: String) -> bool: return key.ends_with("Markers")))
		. is_false()
	)
	# A few units of the canvas do.
	hud.state.set_markers(_moved(hud, 0.003, 0.0))
	await _frames(3)
	(
		assert_bool(redraws.keys().any(func(key: String) -> bool: return key.ends_with("Markers")))
		. is_true()
	)
