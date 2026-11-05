class_name TestGdsUiSelf
extends GdUnitTestSuite
## The gds_ui addon's own self-test (#11): a spring settles on its target and does not depend on the
## frame rate, the theme builds from the tokens, the router's stack depth follows push and pop, and
## the faces named by the tokens are the faces the theme, the sign and the HUD use. It names no
## game screen (bar the sign and the committed tokens it checks), so it moves with the addon.

const SPRING_FRAME_RATES: Array[float] = [30.0, 60.0, 144.0]
const SPRING_SECONDS := 2.0
## A damping ratio of 0.63 overshoots by about 7.5 percent: little, and not growing.
const OVERSHOOT_LIMIT := 0.08
const AGREE := 0.005
## Long enough to be mid-flight, and a whole number of frames at every rate above.
const HALF_SECOND := 0.5
const SETTLE_SECONDS := 4.0
## The committed Deadnight tokens, whose faces are the project's choice.
const SKIN := "res://ui/skin/deadnight_tokens.tres"
const TEXT_FACE := "res://assets/fonts/barlow_condensed/BarlowCondensed-SemiBold.ttf"
const TITLE := "DEADNIGHT"
## Every character the game's own text uses, beyond the title.
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz0123456789"
const MARKS := ".,:;!?-+/%()[]<>&#@$…•×"

var _tokens_before: UITokens


func before_test() -> void:
	_tokens_before = UITokens.active()
	UIMotion.reduced = false
	await RouterFixture.clear(get_tree())


func after_test() -> void:
	UITokens.set_active(_tokens_before)
	await RouterFixture.clear(get_tree())


# --- The spring ---


func test_a_spring_settles_on_its_target_with_little_overshoot() -> void:
	var spring := UISpring.new()
	spring.target = 1.0
	var peak := 0.0
	for _i in int(SPRING_SECONDS * 60.0):
		spring.step(1.0 / 60.0)
		peak = maxf(peak, spring.value)
	assert_bool(spring.is_settled()).is_true()
	assert_float(spring.value).is_equal(1.0)
	assert_float(spring.velocity).is_equal(0.0)
	assert_float(peak).is_less(1.0 + OVERSHOOT_LIMIT)


func test_a_frame_shorter_than_one_step_moves_nothing_and_is_not_lost() -> void:
	var spring := UISpring.new()
	spring.snap(1.0)
	spring.target = 0.0
	spring.step(UISpring.STEP * 0.5)
	assert_float(spring.value).is_equal(1.0)
	spring.step(UISpring.STEP * 0.5)
	assert_float(spring.value).is_less(1.0)


func test_a_spring_ends_in_the_same_place_at_any_frame_rate() -> void:
	var ends := []
	for rate in SPRING_FRAME_RATES:
		var spring := UISpring.new()
		spring.target = 1.0
		for _i in int(HALF_SECOND * rate):
			spring.step(1.0 / rate)
		ends.append(spring.value)
	for value in ends:
		assert_float(value).is_equal_approx(ends[0], AGREE)


# --- The theme ---


func test_the_theme_builds_every_style_from_the_tokens() -> void:
	var tokens := UITokens.new()
	var theme := UIThemeBuilder.build(tokens)
	assert_object(theme.default_font).is_not_null()
	assert_int(theme.default_font_size).is_equal(tokens.size_body)
	for style in UIThemeBuilder.LABEL_STYLES:
		assert_str(theme.get_type_variation_base(style)).is_equal("Label")
		assert_bool(theme.has_font(&"font", style)).is_true()
		assert_bool(theme.has_font_size(&"font_size", style)).is_true()
		assert_bool(theme.has_color(&"font_color", style)).is_true()
	for style in UIThemeBuilder.BUTTON_STYLES:
		assert_str(theme.get_type_variation_base(style)).is_equal("Button")
		assert_bool(theme.has_font(&"font", style)).is_true()
	for style in UIThemeBuilder.PANEL_STYLES:
		assert_str(theme.get_type_variation_base(style)).is_equal("PanelContainer")
	assert_object(theme.get_color(&"font_color", &"UILabelBody")).is_equal(tokens.ink)
	assert_int(theme.get_font_size(&"font_size", &"UILabelDisplay")).is_equal(tokens.size_display)


func test_every_label_style_has_a_theme_variation() -> void:
	var count := UILabel.Style.size()
	assert_int(UIThemeBuilder.LABEL_STYLES.size()).is_equal(count)
	for style in count:
		var label := auto_free(UILabel.new()) as UILabel
		label.style = style
		assert_str(label.theme_type_variation).is_equal(UIThemeBuilder.LABEL_STYLES[style])


# --- The router ---


func test_the_stack_depth_follows_push_and_pop() -> void:
	UIRouter.reset(_screen("root"), UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(1)
	UIRouter.push(_screen("a"), UITransition.Kind.CUT)
	UIRouter.push(_screen("b"), UITransition.Kind.FADE)
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(3)
	assert_str(UIRouter.top().get_meta(&"label")).is_equal("b")
	UIRouter.pop()
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(2)
	UIRouter.pop()
	UIRouter.pop()
	assert_bool(await _settle()).is_true()
	assert_int(UIRouter.depth()).is_equal(1)
	assert_str(UIRouter.top().get_meta(&"label")).is_equal("root")


# --- The faces ---


func test_the_theme_applies_each_face_slot_to_its_styles() -> void:
	var display := _face()
	var text := _face()
	var mono := _face()
	var tokens := UITokens.new()
	tokens.font_display = display
	tokens.font_text = text
	tokens.font_mono = mono
	var theme := UIThemeBuilder.build(tokens)
	assert_object(_base(theme, &"UILabelDisplay")).is_same(display)
	assert_object(_base(theme, &"UILabelTitle")).is_same(display)
	for style in [&"UILabelHeading", &"UILabelBody", &"UILabelCaption", &"UILabelOverline"]:
		assert_object(_base(theme, style)).is_same(text)
	for style in UIThemeBuilder.BUTTON_STYLES:
		assert_object(_base(theme, style)).is_same(text)
	assert_object(_base(theme, &"UIOptionSelector")).is_same(text)
	assert_object(_base(theme, &"UILabelMono")).is_same(mono)
	assert_object((theme.default_font as FontVariation).base_font).is_same(text)


func test_with_no_faces_the_theme_uses_the_engine_font() -> void:
	var theme := UIThemeBuilder.build(UITokens.new())
	for style in UIThemeBuilder.LABEL_STYLES:
		assert_object(_base(theme, style)).is_same(ThemeDB.fallback_font)
	for style in UIThemeBuilder.BUTTON_STYLES:
		assert_object(_base(theme, style)).is_same(ThemeDB.fallback_font)


func test_the_mono_slot_falls_back_to_the_text_face_with_tabular_figures() -> void:
	var tokens := UITokens.new()
	tokens.font_text = load(TEXT_FACE)
	var mono := tokens.mono_font()
	assert_object(mono.base_font).is_same(tokens.font_text)
	var widths := {}
	for digit in "0123456789":
		widths[mono.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 40).x] = true
	assert_int(widths.size()).is_equal(1)


func test_a_chosen_face_keeps_the_engine_font_for_a_glyph_it_lacks() -> void:
	var tokens := UITokens.new()
	tokens.font_text = _face()
	assert_array(tokens.text_font().fallbacks).contains([ThemeDB.fallback_font])
	assert_array(UITokens.new().text_font().fallbacks).is_empty()


func test_swapping_the_tokens_swaps_the_faces_on_a_shown_screen() -> void:
	UITokens.set_active(UITokens.new())
	var screen := UIScreen.new()
	var label := UILabel.new()
	label.style = UILabel.Style.BODY
	label.text = "Gates open at dusk"
	screen.add_child(label)
	UIRouter.reset(screen, UITransition.Kind.CUT)
	assert_bool(await _settle()).is_true()
	assert_object((label.get_theme_font(&"font") as FontVariation).base_font).is_same(
		ThemeDB.fallback_font
	)
	var chosen := UITokens.new()
	chosen.font_text = _face()
	UITokens.set_active(chosen)
	assert_object((label.get_theme_font(&"font") as FontVariation).base_font).is_same(
		chosen.font_text
	)


func test_the_neon_sign_takes_its_lettering_from_the_display_slot() -> void:
	var tokens := UITokens.new()
	UITokens.set_active(tokens)
	var sign: NeonSign = auto_free(NeonSign.new())
	add_child(sign)
	assert_object(sign._font.base_font).is_same(ThemeDB.fallback_font)
	var chosen := UITokens.new()
	chosen.font_display = _face()
	UITokens.set_active(chosen)
	assert_object(sign._font.base_font).is_same(chosen.font_display)
	var own := _face()
	sign.font = own
	assert_object(sign._font.base_font).is_same(own)


# --- The faces the game chose ---


func test_the_game_tokens_name_both_open_licence_faces() -> void:
	var tokens := load(SKIN) as UITokens
	assert_str(tokens.font_display.get_font_name()).is_equal("Bungee Inline")
	assert_str(tokens.font_text.get_font_name()).starts_with("Barlow Condensed")
	assert_str(tokens.font_text.get_font_style_name()).is_equal("SemiBold")


func test_the_chosen_faces_draw_every_letter_digit_and_mark_the_game_shows() -> void:
	var tokens := load(SKIN) as UITokens
	for face: Font in [tokens.font_display, tokens.font_text]:
		for letter in TITLE + LETTERS + MARKS:
			(
				assert_bool(face.has_char(letter.unicode_at(0)))
				. override_failure_message("%s lacks '%s'" % [face.get_font_name(), letter])
				. is_true()
			)


func test_the_game_sign_reads_deadnight_in_the_display_face() -> void:
	UITokens.set_active(load(SKIN) as UITokens)
	var sign: NeonSign = auto_free(NeonSign.new())
	add_child(sign)
	assert_str(sign.text).is_equal(TITLE)
	assert_str(sign._font.base_font.get_font_name()).is_equal("Bungee Inline")
	assert_float(sign.custom_minimum_size.x).is_greater(sign.font_size * 4.0)


# --- Helpers ---


## A font file to stand for a chosen face (each call is a different object).
func _face() -> Font:
	return FontFile.new()


func _base(theme: Theme, style: StringName) -> Font:
	return (theme.get_font(&"font", style) as FontVariation).base_font


func _screen(screen_name: String) -> Control:
	var screen := Control.new()
	screen.name = screen_name
	screen.set_meta(&"label", screen_name)
	return screen


func _settle() -> bool:
	var waited := 0.0
	while UIRouter.busy and waited < SETTLE_SECONDS:
		await get_tree().process_frame
		waited += get_tree().root.get_process_delta_time()
	return not UIRouter.busy
