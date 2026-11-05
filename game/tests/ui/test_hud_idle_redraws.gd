# A HUD that is not changing is not redrawn (#948). In the Compatibility renderer a canvas item that
# is redrawn builds its polygons and glyph runs again, and a HUD is 150 or so draw calls: redrawing
# it on the clock (a `queue_redraw()` in `_process`) costs that every frame for a picture that did
# not change. The late-round HUD stands still, every timed part has run out, and the `draw` signals
# of every canvas item below it are counted over a second of frames.
extends GdUnitTestSuite

const SECOND_OF_FRAMES := 60
## One turn of the low-fuel pulse, in seconds.
const PULSE_PERIOD := TAU / HudFuel.PULSE_RATE
## A cap on the frames of the pulse window, so a stuck clock fails instead of hanging.
const MOST_FRAMES := 3000


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
	# The panel slides in, then holds for longer than the pulse's period.
	fixture.advance(HudTuning.current().fuel_in + 0.1)
	await _frames(10)
	var redraws := _watch(hud)
	var low := 1.0
	var high := 0.0
	# The pulse is a function of time, so the window is a whole period of it in seconds of frame time,
	# not a number of frames: a frame of 4 ms (a window with no cap) or of 33 ms sees the same swing.
	var elapsed := 0.0
	var frames := 0
	while elapsed < PULSE_PERIOD and frames < MOST_FRAMES:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		frames += 1
		var alpha := hud.fuel._lit.self_modulate.a
		low = minf(low, alpha)
		high = maxf(high, alpha)
	# The pulse is the alpha of the lit segments' layer: a period of it redraws no canvas item, and the
	# layer's alpha really moved.
	assert_dict(redraws).is_empty()
	assert_float(high - low).is_greater(0.2)


## The pulse is a function of the HUD's clock alone: the same time in steps of 30, 60 or 144 frames
## a second gives the same alpha (a player on a slow or a fast screen sees the same pulse).
func test_the_low_fuel_pulse_is_the_same_at_any_frame_rate() -> void:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	var alphas := []
	for rate in [30.0, 60.0, 144.0, 240.0]:
		var fixture := HudFixture.make(host, 1)
		fixture.hud.state.apply_event({"type": &"fuel_low"})
		for _i in int(rate * PULSE_PERIOD):
			fixture.hud.fuel.advance(1.0 / rate)
		# The same time, to the frame: the whole count of frames of one period is the period only to
		# the last frame, so the clock is topped up to it before reading.
		fixture.hud.fuel.advance(PULSE_PERIOD - int(rate * PULSE_PERIOD) / rate)
		alphas.append(fixture.hud.fuel._lit.self_modulate.a)
		fixture.hud.queue_free()
	for alpha in alphas:
		assert_float(alpha).is_equal_approx(alphas[0], 0.001)


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
