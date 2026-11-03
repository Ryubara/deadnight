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
