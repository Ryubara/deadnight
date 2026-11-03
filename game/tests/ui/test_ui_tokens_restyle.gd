class_name TestUITokensRestyle
extends GdUnitTestSuite
## The addon's look is tokens only: a second palette (the demo's light one) restyles the router, the
## screens, the components and the shader transitions with no code change, live or at startup, and
## every literal that used to sit in a shader or a component is a token.

const LIGHT := "res://addons/gds_ui/demo/light_tokens.tres"
const DEMO_MENU := "res://addons/gds_ui/demo/demo_menu.tscn"
const SHEET := "res://addons/gds_ui/demo/states_sheet.tscn"
const BURN := preload("res://addons/gds_ui/shaders/film_burn.gdshader")
const IRIS := preload("res://addons/gds_ui/shaders/projector_iris.gdshader")
const SETTLE_SECONDS := 4.0
const MID_SLIDE_TIME_SCALE := 0.02
const MID_SLIDE_FRAMES := 3
const TOLERANCE := 0.02

var _before: UITokens
var _was_reduced := false


func before_test() -> void:
	_before = UITokens.active()
	_was_reduced = UIMotion.reduced
	UIMotion.reduced = false
	await RouterFixture.clear(get_tree())


func after_test() -> void:
	Engine.time_scale = 1.0
	UITokens.set_active(_before)
	UIMotion.reduced = _was_reduced
	await RouterFixture.clear(get_tree())


func test_every_colour_a_shader_declares_is_a_token() -> void:
	var tokens := UITokens.new()
	for shader in [BURN, IRIS]:
		var colours := 0
		for uniform in (shader as Shader).get_shader_uniform_list():
			var uniform_name := StringName(uniform["name"])
			if uniform["type"] == TYPE_VECTOR3:
				colours += 1
				(
					assert_bool(tokens.get(uniform_name) is Color)
					. override_failure_message("%s is not a colour token" % uniform_name)
					. is_true()
				)
		assert_int(colours).is_greater(2)


func test_the_shaders_get_their_palette_from_the_tokens() -> void:
	var tokens := UITokens.new()
	tokens.burn_hot = Color(0.1, 0.2, 0.3)
	tokens.burn_flame = Color(0.4, 0.5, 0.6)
	tokens.burn_ember = Color(0.7, 0.8, 0.9)
	tokens.burn_char = Color(0.15, 0.25, 0.35)
	tokens.iris_shade = Color(0.2, 0.3, 0.4)
	tokens.iris_rim = Color(0.5, 0.6, 0.7)
	tokens.iris_rim_hot = Color(0.8, 0.9, 1.0)
	var burn := ShaderMaterial.new()
	burn.shader = BURN
	UITransitionShader.feed_tokens(burn, tokens)
	for token in [&"burn_hot", &"burn_flame", &"burn_ember", &"burn_char"]:
		assert_object(burn.get_shader_parameter(token)).is_equal(tokens.get(token))
	var iris := ShaderMaterial.new()
	iris.shader = IRIS
	UITransitionShader.feed_tokens(iris, tokens)
	for token in [&"iris_shade", &"iris_rim", &"iris_rim_hot"]:
		assert_object(iris.get_shader_parameter(token)).is_equal(tokens.get(token))


func test_a_running_shader_transition_uses_the_active_palette() -> void:
	var light := load(LIGHT) as UITokens
	UITokens.set_active(light)
	UIRouter.reset(_screen("a"), UITransition.Kind.CUT)
	await _settle()
	UIRouter.push(_screen("b"), UITransition.Kind.BURN)
	await get_tree().process_frame
	await get_tree().process_frame
	var overlay := UIRouter.get_node("Overlay") as ColorRect
	var material := overlay.material as ShaderMaterial
	assert_object(material).is_not_null()
	assert_object(material.get_shader_parameter(&"burn_flame")).is_equal(light.burn_flame)
	assert_object(material.get_shader_parameter(&"burn_char")).is_equal(light.burn_char)
	assert_bool(await _settle()).is_true()


func test_swapping_the_tokens_restyles_the_router_and_its_theme() -> void:
	var light := load(LIGHT) as UITokens
	assert_object(light).is_not_null()
	var stage := UIRouter.get_node("Stage") as Control
	var dark := UITokens.new()
	UITokens.set_active(dark)
	assert_object(stage.theme.get_color(&"font_color", &"UILabelBody")).is_equal(dark.ink)
	UITokens.set_active(light)
	assert_object(stage.theme.get_color(&"font_color", &"UILabelBody")).is_equal(light.ink)
	assert_object(stage.theme.get_color(&"font_color", &"UILabelDisplay")).is_equal(
		light.accent_bright
	)
	assert_object(RenderingServer.get_default_clear_color()).is_equal(light.bg)


func test_the_demo_menu_restyles_live_with_no_code_change() -> void:
	var dark := UITokens.new()
	UITokens.set_active(dark)
	UIRouter.reset(DEMO_MENU, UITransition.Kind.CUT)
	await _settle()
	var menu := UIRouter.top() as UIScreen
	assert_int(menu.star_count()).is_equal(dark.star_count)
	var title := _first_label(menu, UILabel.Style.TITLE)
	assert_object(title.get_theme_color(&"font_color")).is_equal(dark.ink)
	var light := load(LIGHT) as UITokens
	UITokens.set_active(light)
	# The same instances, now reading the light palette: the theme, the stars, the cached tokens.
	assert_object(UIRouter.top()).is_same(menu)
	assert_object(title.get_theme_color(&"font_color")).is_equal(light.ink)
	assert_int(menu.star_count()).is_equal(0)
	assert_object(menu._tokens).is_same(light)
	for button in _all(menu, UIButton):
		assert_object((button as UIButton)._tokens).is_same(light)
	for panel in _all(menu, UIPanel):
		assert_object((panel as UIPanel)._tokens).is_same(light)


func test_a_screen_built_after_the_swap_takes_the_new_palette() -> void:
	var light := load(LIGHT) as UITokens
	UITokens.set_active(light)
	UIRouter.reset(SHEET, UITransition.Kind.CUT)
	await _settle()
	var sheet := UIRouter.top() as UIScreen
	assert_object(sheet._tokens).is_same(light)
	for button in _all(sheet, UIButton):
		assert_object((button as UIButton)._tokens).is_same(light)
	assert_int(sheet.star_count()).is_equal(0)


func test_sizes_from_the_tokens_follow_a_swap() -> void:
	var toggle := UIToggle.new()
	var slider := UISlider.new()
	var selector := UIOptionSelector.new()
	var row := UIRow.new()
	var holder := Control.new()
	for node in [toggle, slider, selector, row]:
		holder.add_child(node)
	add_child(holder)
	var big := UITokens.new()
	big.control_height = 90
	big.control_width = 700
	UITokens.set_active(big)
	assert_float(toggle.custom_minimum_size.y).is_equal(90.0)
	assert_float(slider.custom_minimum_size.y).is_equal(90.0)
	assert_float(selector.custom_minimum_size.y).is_equal(90.0)
	assert_float(selector.custom_minimum_size.x).is_equal(350.0)
	row.set_control(Control.new())
	assert_float(row.get_child(1).custom_minimum_size.x).is_equal(700.0)
	UITokens.set_active(UITokens.new())
	assert_float(row.get_child(1).custom_minimum_size.x).is_equal(440.0)
	holder.free()


func test_set_active_tells_listeners_once_and_null_returns_to_the_project_look() -> void:
	var seen: Array[UITokens] = []
	var listen := func(next: UITokens) -> void: seen.append(next)
	UITokens.active_changed().connect(listen)
	var other := UITokens.new()
	UITokens.set_active(other)
	UITokens.set_active(other)
	assert_int(seen.size()).is_equal(1)
	UITokens.set_active(null)
	assert_int(seen.size()).is_equal(2)
	assert_object(UITokens.active()).is_not_same(other)
	assert_object(UITokens.active().bg).is_equal(_before.bg)
	UITokens.active_changed().disconnect(listen)


func test_the_star_backdrop_is_optional_and_repeatable() -> void:
	var screen := UIScreen.new()
	add_child(screen)
	assert_int(screen.star_count()).is_equal(UITokens.active().star_count)
	screen.stars = false
	assert_int(screen.star_count()).is_equal(0)
	screen.stars = true
	assert_int(screen.star_count()).is_greater(0)
	var none := UITokens.new()
	none.star_count = 0
	UITokens.set_active(none)
	assert_int(screen.star_count()).is_equal(0)
	var few := UITokens.new()
	few.star_count = 5
	few.star_seed = 42
	UITokens.set_active(few)
	assert_int(screen.star_count()).is_equal(5)
	var again := screen._stars.duplicate()
	UITokens.set_active(none)
	UITokens.set_active(few)
	assert_array(screen._stars).is_equal(again)
	# Every star sits in the top band of the screen.
	for star in screen._stars:
		assert_bool(star.y <= screen.size.y * few.star_band).is_true()
	screen.free()


func test_button_tints_come_from_the_tokens() -> void:
	var tokens := UITokens.new()
	tokens.tint_hover = 0.5
	tokens.tint_press = 0.4
	tokens.ghost_hover_alpha = 0.3
	tokens.disabled_alpha = 0.6
	UITokens.set_active(tokens)
	var holder := Control.new()
	add_child(holder)
	var secondary := _button(holder, UIButton.Variant.SECONDARY, UIButton.Preview.HOVER)
	assert_object(secondary._fill.bg_color).is_equal(tokens.surface_raised.lightened(0.5))
	var pressed := _button(holder, UIButton.Variant.PRIMARY, UIButton.Preview.PRESSED)
	assert_object(pressed._fill.bg_color).is_equal(tokens.accent_bright.darkened(0.4))
	var ghost := _button(holder, UIButton.Variant.GHOST, UIButton.Preview.HOVER)
	assert_float(ghost._fill.bg_color.a).is_equal_approx(0.3, TOLERANCE)
	var off := _button(holder, UIButton.Variant.SECONDARY, UIButton.Preview.DISABLED)
	assert_float(off._fill.bg_color.a).is_equal_approx(0.6, TOLERANCE)
	holder.free()


func test_the_theme_emboldening_follows_the_token_ratios() -> void:
	var tokens := UITokens.new()
	tokens.embolden_display = 0.8
	tokens.embolden_heading_ratio = 0.25
	tokens.embolden_button_ratio = 0.5
	tokens.embolden_option_ratio = 0.75
	var theme := UIThemeBuilder.build(tokens)
	var heading := theme.get_font(&"font", &"UILabelHeading") as FontVariation
	var button := theme.get_font(&"font", &"UIButtonPrimary") as FontVariation
	var option := theme.get_font(&"font", &"UIOptionSelector") as FontVariation
	assert_float(heading.variation_embolden).is_equal_approx(0.2, 0.001)
	assert_float(button.variation_embolden).is_equal_approx(0.4, 0.001)
	assert_float(option.variation_embolden).is_equal_approx(0.6, 0.001)


func test_the_slide_dim_and_parallax_come_from_the_tokens() -> void:
	var tokens := UITokens.new()
	tokens.slide_dim = Color(0.2, 0.6, 0.9)
	tokens.slide_parallax = 0.5
	UITokens.set_active(tokens)
	var below := _screen("below")
	UIRouter.reset(below, UITransition.Kind.CUT)
	await _settle()
	UIRouter.push(_screen("top"), UITransition.Kind.SLIDE)
	await _settle()
	var width := (UIRouter.get_node("Stage") as Control).size.x
	# A pop starts the screen below at the dim colour, parallax of the width to the left.
	Engine.time_scale = MID_SLIDE_TIME_SCALE
	UIRouter.pop()
	for _i in MID_SLIDE_FRAMES:
		await get_tree().process_frame
	# How far the slide got is the frames' business (on a loaded machine they are long), so the
	# check does not name a place: the position and the colour ride the same tween, so the share
	# `done` of the way that the position shows (from the token's 0.5 of the width) must be the
	# share the colour shows too (from the token's dim). Another parallax or dim breaks the match.
	var done := 1.0 + below.position.x / (width * 0.5)
	assert_float(done).is_between(0.0, 0.9)
	# Red loses 0.8 and green 0.4 on the way to the dim colour, so their losses keep a 1 : 2 ratio.
	var lost_red := 1.0 - below.modulate.r
	var lost_green := 1.0 - below.modulate.g
	assert_float(lost_red).is_equal_approx(0.8 * (1.0 - done), 0.02)
	assert_float(lost_green).is_equal_approx(0.4 * (1.0 - done), 0.02)
	Engine.time_scale = 1.0
	assert_bool(await _settle()).is_true()


func test_the_shader_half_length_comes_from_the_tokens() -> void:
	var quick := UITokens.new()
	quick.dur_screen = 0.1
	quick.shader_half_scale = 0.5
	var slow := UITokens.new()
	slow.dur_screen = 0.1
	slow.shader_half_scale = 8.0
	UITokens.set_active(quick)
	UIRouter.reset(_screen("a"), UITransition.Kind.CUT)
	await _settle()
	var quick_ms := await _time_push(UITransition.Kind.IRIS)
	UITokens.set_active(slow)
	var slow_ms := await _time_push(UITransition.Kind.IRIS)
	# Two sweeps of dur_screen * half_scale: 0.1 s against 1.6 s.
	assert_bool(quick_ms < 1000).override_failure_message("quick took %d ms" % quick_ms).is_true()
	assert_bool(slow_ms > 1200).override_failure_message("slow took %d ms" % slow_ms).is_true()


func test_the_marquee_chase_follows_reduced_motion_and_the_tokens() -> void:
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	add_child(panel)
	assert_bool(panel.is_processing()).is_true()
	UIMotion.reduced = true
	assert_bool(panel.is_processing()).is_false()
	UIMotion.reduced = false
	assert_bool(panel.is_processing()).is_true()
	var tokens := UITokens.new()
	tokens.bulb_spacing = 100.0
	tokens.chase_period = 0
	UITokens.set_active(tokens)
	assert_object(panel._tokens).is_same(tokens)
	# A zero period must not divide by zero in the draw.
	panel.size = Vector2(400.0, 200.0)
	panel.notification(CanvasItem.NOTIFICATION_DRAW)
	panel.free()


func test_reduced_motion_changes_at_runtime_through_one_assignment() -> void:
	var seen: Array[bool] = []
	var listen := func(value: bool) -> void: seen.append(value)
	UIMotion.changed().connect(listen)
	UIMotion.reduced = true
	UIMotion.reduced = true
	UIMotion.reduced = false
	UIMotion.changed().disconnect(listen)
	assert_array(seen).is_equal([true, false])
	# A shader transition asked for while reduced becomes the fade: the overlay never gets a shader.
	UIMotion.reduced = true
	UIRouter.reset(_screen("a"), UITransition.Kind.CUT)
	await _settle()
	UIRouter.push(_screen("b"), UITransition.Kind.BURN)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object((UIRouter.get_node("Overlay") as ColorRect).material).is_null()
	assert_bool(await _settle()).is_true()


func _time_push(kind: UITransition.Kind) -> int:
	var started := Time.get_ticks_msec()
	UIRouter.push(_screen("p%d" % started), kind)
	await get_tree().process_frame
	var waited := 0.0
	while UIRouter.busy and waited < 6.0:
		await get_tree().process_frame
		waited += get_tree().root.get_process_delta_time()
	return Time.get_ticks_msec() - started


func _button(holder: Control, variant: UIButton.Variant, state: UIButton.Preview) -> UIButton:
	var button := UIButton.new()
	button.variant = variant
	button.preview_state = state
	holder.add_child(button)
	button.snap_to_targets()
	button._paint_fill()
	return button


func _screen(screen_name: String) -> Control:
	var screen := Control.new()
	screen.name = screen_name
	return screen


func _settle() -> bool:
	var waited := 0.0
	while UIRouter.busy and waited < SETTLE_SECONDS:
		await get_tree().process_frame
		waited += get_tree().root.get_process_delta_time()
	return not UIRouter.busy


func _first_label(root: Node, style: UILabel.Style) -> UILabel:
	for label in _all(root, UILabel):
		if (label as UILabel).style == style:
			return label as UILabel
	return null


func _all(root: Node, type: Variant) -> Array[Node]:
	var found: Array[Node] = []
	for child in root.get_children():
		if is_instance_of(child, type):
			found.append(child)
		found.append_array(_all(child, type))
	return found
