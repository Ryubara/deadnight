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
const WINDOW := Vector2i(1280, 720)

var _window_before: Vector2i


func before_test() -> void:
	_window_before = get_tree().root.size
	get_tree().root.size = WINDOW
	await RouterFixture.clear(get_tree())


func after_test() -> void:
	get_tree().root.size = _window_before
	await RouterFixture.clear(get_tree())


func test_the_sign_wears_the_game_face_and_fits_the_play_column() -> void:
	var menu := await _show_menu()
	var sign := menu.find_child("Sign", true, false) as NeonSign
	assert_str(sign._font.base_font.get_font_name()).is_equal("Bungee Inline")
	var play := menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel
	assert_float(sign.custom_minimum_size.x).is_less_equal(play.width(false))


func test_the_tabs_and_tickets_wear_the_games_faces() -> void:
	var menu := await _show_menu()
	var tokens := UITokens.active()
	var wide := MenuLook.wide_font() as FontVariation
	assert_str(wide.base_font.get_font_name()).starts_with("Barlow Condensed")
	assert_str(tokens.font_display.get_font_name()).is_equal("Bungee Inline")
	# Every label the shell builds names one of the two faces.
	for node in menu.shell.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text == "":
			continue
		var face := label.get_theme_font(&"font")
		var name := (
			(face as FontVariation).base_font.get_font_name()
			if face is FontVariation
			else face.get_font_name()
		)
		(
			assert_bool(name.begins_with("Barlow Condensed") or name == "Bungee Inline")
			. override_failure_message("'%s' is set in %s" % [label.text, name])
			. is_true()
		)


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
	for _i in 3:
		await get_tree().process_frame
	return menu
