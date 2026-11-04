# The special-round marquee's bulbs and the damage frame are polygons the Compatibility renderer
# builds into buffers of their own: each is drawn when what it shows changes by a step, not every
# frame (#834, #934). The counts are of the engine's `draw` signal, over 2 s of 60 Hz frames.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0
const FRAMES := 120

var _host: Control


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


func after_test() -> void:
	UIMotion.reduced = false


## The night played to the break before round 5, the first special round, every zombie killed.
func _marquee_up() -> HudMarquee:
	var fixture := HudFixture.make(_host)
	fixture.act(RulesAction.start())
	while fixture.rules.round_number < 4 or fixture.rules.phase != GameRules.Phase.BREAK:
		if fixture.rules.phase == GameRules.Phase.BREAK:
			fixture.act(RulesAction.skip_break())
			continue
		var guard := 0
		while fixture.rules.phase == GameRules.Phase.ACTIVE and guard < 20000:
			fixture.act(RulesAction.tick(RulesFixture.STEP * 6.0))
			for zombie_id in fixture.rules.zombie_ids():
				fixture.act(
					RulesAction.hit(1, zombie_id, RulesAction.ZONE_BODY, HudFixture.KILLING)
				)
			guard += 1
	var marquee := fixture.hud.marquee
	assert_bool(marquee.visible).is_true()
	# The test steps the clock itself: one count, not two.
	marquee.set_process(false)
	return marquee


## Draws of `part` over `FRAMES` frames, each stepping `advance` once.
func _draws(part: Control) -> int:
	await get_tree().process_frame
	var draws := [0]
	part.draw.connect(func() -> void: draws[0] += 1)
	for _i in FRAMES:
		part.advance(STEP)
		await get_tree().process_frame
	return draws[0]


func test_the_marquee_is_redrawn_when_the_bulbs_step_not_every_frame() -> void:
	var marquee := _marquee_up()
	var draws: int = await _draws(marquee)
	# Two seconds of the chase: six steps, a draw each, not a hundred and twenty.
	assert_int(draws).is_between(int(2.0 * HudMarquee.CHASE) - 1, int(2.0 * HudMarquee.CHASE) + 1)


func test_the_letters_still_flicker_while_the_board_is_not_redrawn() -> void:
	var marquee := _marquee_up()
	var lights := {}
	await get_tree().process_frame
	for _i in FRAMES:
		marquee.advance(STEP)
		lights[marquee.letter_light] = true
	assert_int(lights.size()).is_greater(2)


func test_the_marquee_with_reduced_motion_is_not_redrawn_while_it_shows() -> void:
	var marquee := _marquee_up()
	UIMotion.reduced = true
	marquee.advance(STEP)
	var draws: int = await _draws(marquee)
	assert_int(draws).is_equal(0)


func test_the_damage_frame_at_full_health_is_never_redrawn() -> void:
	var fixture := HudFixture.make(_host)
	fixture.hud.damage.set_process(false)
	var draws: int = await _draws(fixture.hud.damage)
	assert_int(draws).is_equal(0)


func test_the_pulsing_damage_frame_is_redrawn_by_steps_not_every_frame() -> void:
	var fixture := HudFixture.make(_host)
	var damage := fixture.hud.damage
	damage.set_process(false)
	fixture.hud.state.set_health(20.0, 100.0)
	assert_float(damage.frame_strength).is_greater(0.0)
	var draws: int = await _draws(damage)
	assert_int(draws).is_between(1, FRAMES / 4)


func test_the_damage_frame_with_reduced_motion_holds_still() -> void:
	UIMotion.reduced = true
	var fixture := HudFixture.make(_host)
	var damage := fixture.hud.damage
	damage.set_process(false)
	fixture.hud.state.set_health(20.0, 100.0)
	await get_tree().process_frame
	var draws: int = await _draws(damage)
	assert_int(draws).is_equal(0)


func test_an_arc_is_drawn_through_its_life_by_steps_and_cleared_at_the_end() -> void:
	var fixture := HudFixture.make(_host)
	var damage := fixture.hud.damage
	damage.set_process(false)
	await get_tree().process_frame
	var draws := [0]
	damage.draw.connect(func() -> void: draws[0] += 1)
	damage.on_event({"type": HudState.PLAYER_HURT, "player_id": 1, "bearing": 0.5})
	var frames := int((HudTuning.current().damage_arc_life + 0.2) / STEP)
	for _i in frames:
		damage.advance(STEP)
		await get_tree().process_frame
	assert_array(damage.arcs).is_empty()
	# One draw a step of the arc's life (and the first, and the clearing one), not one a frame.
	var steps: int = (load("res://ui/hud/hud_damage.gd") as GDScript).get_script_constant_map().get(
		"STEPS", 32
	)
	assert_int(draws[0]).is_between(steps, steps + 3)
	assert_int(frames).is_greater(draws[0])
