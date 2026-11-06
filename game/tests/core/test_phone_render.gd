extends GdUnitTestSuite
## A phone draws without multisampling, with a pixel ratio capped; a desktop is left as is (#689).


func after_test() -> void:
	TouchMode.device_is_touch = null


func test_a_phone_draws_the_night_without_multisampling() -> void:
	TouchMode.device_is_touch = true
	var viewport: SubViewport = auto_free(SubViewport.new())
	viewport.msaa_3d = Viewport.MSAA_2X
	PhoneRender.apply(viewport)
	assert_int(viewport.msaa_3d).is_equal(Viewport.MSAA_DISABLED)


func test_a_desktop_keeps_its_multisampling() -> void:
	TouchMode.device_is_touch = false
	var viewport: SubViewport = auto_free(SubViewport.new())
	viewport.msaa_3d = Viewport.MSAA_2X
	PhoneRender.apply(viewport)
	assert_int(viewport.msaa_3d).is_equal(Viewport.MSAA_2X)


func test_the_page_caps_the_pixel_ratio_at_the_same_number() -> void:
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	var found := RegEx.create_from_string(r"parseFloat\(q\[1\]\):([0-9.]+);").search(presets)
	assert_object(found).is_not_null()
	assert_float(float(found.get_string(1))).is_equal(PhoneRender.PIXEL_RATIO_CAP)


func test_the_page_keeps_the_locks_that_hold_a_phone_page_at_scale_one() -> void:
	# #1310: iOS Safari ignores `user-scalable=no`, so `touch-action: none` and the `gesturestart`
	# handler are the lock there; Chrome honours the first two. A page that loses one can zoom.
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	for needle: String in [
		"user-scalable=no",
		"initial-scale=1.0",
		"viewport-fit=cover",
		"touch-action:none",
		"gesturestart",
	]:
		assert_str(presets).contains(needle)


func test_the_view_readout_is_behind_its_query_and_adds_nothing_to_a_players_page() -> void:
	# #1310: `?viewcheck` shows the page's own numbers on a real phone. Without the query the
	# script returns before it touches the page.
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	var start := presets.find("viewcheck")
	assert_int(start).is_greater(-1)
	var opening := presets.substr(presets.rfind("<script>", start), 120)
	assert_str(opening).contains("if(!/[?&]viewcheck/.test(location.search))return;")
	assert_int(presets.count("createElement('pre')")).is_equal(1)


func test_the_view_readout_names_what_separates_the_ios_candidates() -> void:
	# #1310 (an iPhone in Safari): the verdict line, the viewport units, the safe area, the computed
	# touch-action and the gestures the page saw are what tell a stuck zoom from a short viewport.
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	for needle: String in [
		"all as designed",
		"visual viewport is not the page",
		"100svh",
		"100dvh",
		"safe-area-inset-top",
		"touchAction",
		"gesturestart",
		"two-finger touches",
	]:
		assert_str(presets).contains(needle)
