extends GdUnitTestSuite
## Which windows are a phone's (#1197). The window of a web page is its canvas in device pixels:
## an 844 x 390 CSS pixel phone page is 1688 x 780 at the ratio of 2 the game reports. The test
## asks for what the person holds. Each case a player can have is named here, so a change to the
## rule says which one it moved.

var _saved_touch: Variant


func before_test() -> void:
	_saved_touch = TouchMode.device_is_touch


func after_test() -> void:
	TouchMode.device_is_touch = _saved_touch
	PageSize.css_override = null


## A page: its CSS size, whether the device is a touch screen, and the pixel ratio the game sees.
## Returns the window, which is the canvas.
func _page(css: Vector2, touch: bool, ratio: float) -> Vector2i:
	TouchMode.device_is_touch = touch
	PageSize.css_override = css
	return Vector2i(css * ratio)


func test_a_phone_page_is_a_phone_at_every_pixel_ratio() -> void:
	for ratio in [1.0, 2.0, 3.0]:
		var window := _page(Vector2(844, 390), true, ratio)
		assert_bool(MenuScale.is_phone(window)).is_true()
		assert_float(MenuScale.factor(window, 1.0)).is_equal(MenuScale.PHONE_FACTOR)


func test_every_phone_page_lays_out_on_the_same_canvas() -> void:
	var canvases: Array[Vector2] = []
	for ratio in [1.0, 2.0, 3.0]:
		var window := _page(Vector2(844, 390), true, ratio)
		var per_unit := MenuScale.pixels_per_unit(window, MenuScale.PHONE_FACTOR)
		canvases.append((Vector2(window) / per_unit).round())
	assert_vector(canvases[1]).is_equal(canvases[0])
	assert_vector(canvases[2]).is_equal(canvases[0])
	assert_vector(canvases[0]).is_equal(Vector2(1169, 540))


func test_a_unit_is_0_72_css_pixels_on_a_phone_page_not_0_36() -> void:
	var window := _page(Vector2(844, 390), true, 2.0)
	assert_float(MenuScale.css_per_unit(window, MenuScale.factor(window, 1.0))).is_equal_approx(
		0.7222, 0.001
	)
	assert_float(MenuScale.css_per_unit(window, 1.0)).is_equal_approx(0.3611, 0.001)


func test_the_biggest_phones_and_the_narrowest_are_phones() -> void:
	for css in [Vector2(932, 430), Vector2(667, 375), Vector2(740, 360), Vector2(844, 390)]:
		assert_bool(MenuScale.is_phone(_page(css, true, 2.0))).is_true()


func test_a_phone_held_upright_is_a_phone_too() -> void:
	assert_bool(MenuScale.is_phone(_page(Vector2(390, 844), true, 2.0))).is_true()


func test_the_limit_is_500_css_pixels_on_the_short_side() -> void:
	assert_bool(MenuScale.is_phone(_page(Vector2(900, 499), true, 2.0))).is_true()
	assert_bool(MenuScale.is_phone(_page(Vector2(900, 500), true, 2.0))).is_false()


func test_a_tablet_keeps_the_desktop_layout() -> void:
	for css in [Vector2(1024, 768), Vector2(1133, 744), Vector2(1280, 800)]:
		assert_bool(MenuScale.is_phone(_page(css, true, 2.0))).is_false()


func test_a_desktop_browser_window_keeps_the_layout_it_had() -> void:
	# A laptop and a big monitor, at the ratio of a plain screen and a high-density one.
	for css in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1688, 780), Vector2(1000, 500)]:
		for ratio in [1.0, 1.5, 2.0]:
			assert_bool(MenuScale.is_phone(_page(css, false, ratio))).is_false()


func test_a_small_desktop_browser_window_is_a_phone_by_its_canvas_as_before() -> void:
	# At a ratio of 1 the canvas is the page: 800 x 450 was a phone's layout and stays.
	assert_bool(MenuScale.is_phone(_page(Vector2(800, 450), false, 1.0))).is_true()
	# A high-density desktop window of the same CSS size has a 1600 x 900 canvas: not a phone's,
	# as before.
	assert_bool(MenuScale.is_phone(_page(Vector2(800, 450), false, 2.0))).is_false()


func test_a_native_window_is_read_by_its_own_size() -> void:
	TouchMode.device_is_touch = false
	PageSize.css_override = null
	assert_bool(MenuScale.is_phone(Vector2i(844, 390))).is_true()
	assert_bool(MenuScale.is_phone(Vector2i(1920, 1080))).is_false()
	assert_bool(MenuScale.is_phone(Vector2i(1000, 500))).is_false()
	# A phone's native build (Android, iOS) has no CSS pixel: the window is the page.
	TouchMode.device_is_touch = true
	assert_bool(MenuScale.is_phone(Vector2i(2400, 1080))).is_false()
	assert_bool(MenuScale.is_phone(Vector2i(2400, 480))).is_true()


func test_a_page_reports_its_css_size_not_the_canvas() -> void:
	var window := _page(Vector2(844, 390), true, 2.0)
	assert_vector(PageSize.css(window)).is_equal(Vector2(844, 390))
	assert_float(PageSize.css_per_pixel(window)).is_equal(0.5)
	PageSize.css_override = null
	assert_float(PageSize.css_per_pixel(window)).is_equal(1.0)


func test_describe_says_the_scale_a_capture_runs_at() -> void:
	var window := _page(Vector2(844, 390), true, 2.0)
	var line := MenuScale.describe(window, MenuScale.factor(window, 1.0))
	assert_str(line).contains("page 844x390 css").contains("canvas 1688x780")
	assert_str(line).contains("factor 2").contains("1169x540 units")
	assert_str(line).contains("0.72 css px per unit").contains("(phone)")
	var plain := MenuScale.describe(window, 1.0)
	assert_str(plain).contains("2337x1080 units").contains("0.36 css px per unit")


func test_the_audit_reads_the_floor_in_css_pixels() -> void:
	var window := _page(Vector2(844, 390), true, 2.0)
	var host: Control = auto_free(Control.new())
	var label := Label.new()
	label.text = "Hello"
	label.add_theme_font_size_override(&"font_size", 26)
	host.add_child(label)
	get_tree().root.add_child(host)
	var small := UiAudit.scan(host, PageSize.css_per_pixel(window))
	# The root here has no stretch of its own: the audit reads the window's, whatever it is, and
	# the page's CSS pixels per window pixel, 0.5.
	var expected := 26.0 * get_tree().root.get_final_transform().get_scale().x * 0.5
	assert_float(small.text_min).is_equal_approx(expected, 0.01)
