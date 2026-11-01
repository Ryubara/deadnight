class_name TestMenuType
extends GdUnitTestSuite
## The menu's type (#80, #11): the footer line reads over the parked cars, the sign and the buttons
## wear the game's two faces, the credits name every font file the game ships (and fit one screen),
## and every font file comes with its licence.

const MENU := "res://ui/screens/main_menu.tscn"
const CREDITS := "res://ui/screens/credits_screen.tscn"
const FONTS := "res://assets/fonts"
const SKIN := "res://ui/skin/deadnight_tokens.tres"
## WCAG's level AAA for normal text: the footer sits on a night sky and silhouettes.
const READABLE := 7.0
const PLATE_MIN_ALPHA := 0.7
const WINDOW := Vector2i(1280, 720)

var _window_before: Vector2i


func before_test() -> void:
	_window_before = get_tree().root.size
	get_tree().root.size = WINDOW
	MainMenu.items_delay = 0.0
	await RouterFixture.clear(get_tree())


func after_test() -> void:
	get_tree().root.size = _window_before
	MainMenu.items_delay = MainMenu.ITEMS_DELAY
	await RouterFixture.clear(get_tree())


func test_the_footer_has_a_plate_and_enough_contrast_and_size() -> void:
	var tokens := UITokens.active()
	var menu := await _show_menu()
	var footer := menu.find_child("Footer", true, false) as Label
	var plate := footer.get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_object(plate).is_not_null()
	assert_float(plate.bg_color.a).is_greater_equal(PLATE_MIN_ALPHA)
	assert_object(footer.get_theme_color(&"font_color")).is_equal(tokens.ink)
	# The worst ground the plate can sit on is the lightest thing behind it: take white.
	var ground := Color.WHITE.lerp(plate.bg_color, plate.bg_color.a)
	assert_float(_contrast(tokens.ink, ground)).is_greater_equal(READABLE)
	assert_int(footer.get_theme_font_size(&"font_size")).is_greater_equal(tokens.size_caption)
	assert_bool(footer.get_combined_minimum_size().x <= menu.size.x).is_true()


func test_the_sign_and_the_buttons_wear_the_games_faces() -> void:
	var menu := await _show_menu()
	var sign := menu.find_child("Sign", true, false) as NeonSign
	assert_str(sign._font.base_font.get_font_name()).is_equal("Bungee Inline")
	for item in ["Play", "Settings", "Credits"]:
		var button := menu.find_child(item, true, false) as UIButton
		var face := button.get_theme_font(&"font") as FontVariation
		assert_str(face.base_font.get_font_name()).starts_with("Barlow Condensed")
	var overline := menu.find_child("Overline", true, false) as Label
	(
		assert_str((overline.get_theme_font(&"font") as FontVariation).base_font.get_font_name())
		. starts_with("Barlow Condensed")
	)


func test_the_sign_fits_the_board_in_the_game_face() -> void:
	var menu := await _show_menu()
	var board := menu.find_child("Board", true, false) as Control
	var sign := menu.find_child("Sign", true, false) as NeonSign
	assert_float(sign.custom_minimum_size.x).is_less(menu.size.x * 0.75)
	assert_float(board.size.x).is_less(menu.size.x)


func test_the_credits_name_every_font_the_game_ships() -> void:
	var tokens := load(SKIN) as UITokens
	var credits := load("res://ui/credits.tres") as CreditsList
	var text := " ".join(credits.lines)
	for face: Font in [tokens.font_display, tokens.font_text]:
		var family := face.get_font_name().replace(" SemiBold", "")
		assert_str(text).contains(family)
	assert_str(text).contains(ThemeDB.fallback_font.get_font_name().replace(" SemiBold", ""))


func test_every_font_file_has_its_licence_text_and_an_entry() -> void:
	var entry := FileAccess.get_file_as_string(FONTS.path_join("LICENSE.md"))
	var folders := DirAccess.get_directories_at(FONTS)
	assert_int(folders.size()).is_greater(1)
	for folder in folders:
		var files := DirAccess.get_files_at(FONTS.path_join(folder))
		(
			assert_bool(files.has("OFL.txt"))
			. override_failure_message(folder + " has no OFL.txt")
			. is_true()
		)
		for file in files:
			if file.get_extension() == "ttf":
				assert_str(entry).contains(file)


func test_the_credits_fit_one_screen_with_the_fonts_listed() -> void:
	UIRouter.reset(CREDITS, UITransition.Kind.CUT)
	await UIRouter.idle
	for _i in 3:
		await get_tree().process_frame
	var screen := UIRouter.top() as UIScreen
	var panel := screen.find_children("*", "UIPanel", true, false)[0] as Control
	var canvas := screen.get_viewport().get_visible_rect().size
	assert_float(panel.size.y).is_less_equal(canvas.y)
	assert_float(panel.size.x).is_less_equal(canvas.x)
	var back := screen.find_child("Back", true, false) as Control
	assert_bool(canvas.y >= back.get_global_rect().end.y).is_true()


## Relative luminance contrast, WCAG 2.
func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(colour: Color) -> float:
	var channels: Array[float] = []
	for value in [colour.r, colour.g, colour.b]:
		channels.append(value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4))
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


func _show_menu() -> MainMenu:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	var menu := UIRouter.top() as MainMenu
	if not menu.has_entered():
		await menu.entered
	for _i in 3:
		await get_tree().process_frame
	return menu
