extends GdUnitTestSuite
## Every interactive control of the menus has a place in the sound table (#894): walking the
## screens (every tab of the main menu and of Settings, the Play, Together, Join, Customize,
## Credits and lobby screens) finds each control that can be hovered, focused, pressed or moved,
## and each one has a role with the rows its events need, a sound or a written silence. A control
## built without one, or a cue sent with no source, fails here and not as a quiet menu. A control
## of the menu's own is also driven with the events a player sends, and the cues it sends are the
## ones its role has rows for.

const TEST_PATH := "user://ui_sound_roles_test.cfg"
const MENU := "res://ui/screens/main_menu.tscn"
const PLAY := "res://ui/screens/play_screen.tscn"
const TOGETHER := "res://ui/screens/together_screen.tscn"
const LOBBY := "res://ui/screens/lobby_screen.tscn"
const JOIN := "res://ui/screens/join_screen.tscn"
const SETTINGS := "res://ui/screens/settings_screen.tscn"
const CUSTOMIZE := "res://ui/screens/customize_screen.tscn"
const CREDITS := "res://ui/screens/credits_screen.tscn"
const SETTLE_SECONDS := 0.5
const SETTLE_TIME_SCALE := 10.0

var _saved_path: String
var _cues: Array = []


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	UIInputMode.reset()
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()
	_cues.clear()


func after_test() -> void:
	Engine.time_scale = 1.0
	await RouterFixture.clear(get_tree())
	MainMenu.board_factory = Callable()
	LobbyScreen.opener = Callable()
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Audio.install_ui_hook()


func _settle() -> void:
	Engine.time_scale = SETTLE_TIME_SCALE
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	Engine.time_scale = 1.0
	await get_tree().process_frame


func _open(path: String, params := {}) -> Control:
	await RouterFixture.clear(get_tree())
	UIRouter.reset(path, UITransition.Kind.CUT, params)
	await UIRouter.idle
	await _settle()
	return UIRouter.top()


## A control a player can hover, focus, press or move (the scroll bars inside a scroll area are
## not).
static func is_interactive(node: Node) -> bool:
	if not node is Control or node is ScrollBar:
		return false
	var control := node as Control
	# The sign and the screens are sources of a cue, not controls a player uses.
	if UiSounds.role_of(control) == &"any":
		return false
	if control.has_meta(UiSounds.ROLE_META) or control.has_method(&"ui_sound_role"):
		return true
	return (
		control is BaseButton
		or control is Range
		or control is LineEdit
		or control.focus_mode == Control.FOCUS_ALL
	)


## The cues a control of this role has to have rows for.
static func cues_of(control: Control, role: StringName) -> Array[StringName]:
	var cues: Array[StringName] = []
	if role == &"tab_bar":
		return [&"tab"]
	if role == &"stage":
		return [&"hover", &"focus", &"press"]
	cues.append(&"hover")
	cues.append(&"focus")
	if role == &"toggle":
		cues.append_array([&"on", &"off"])
	elif role == &"slider":
		cues.append(&"tick")
	elif role == &"option" or role == &"choice_strip":
		cues.append(&"select")
	elif role == &"list":
		cues.append_array([&"tick", &"press"])
	elif control is BaseButton:
		cues.append(&"press")
	return cues


## One line for each interactive control under `root` that the table does not know.
func _unknown(root: Node, where: String) -> Array[String]:
	var found: Array[String] = []
	var seen := 0
	for node in root.find_children("*", "Control", true, false):
		if not is_interactive(node):
			continue
		seen += 1
		var control := node as Control
		var role := UiSounds.role_of(control)
		var label := "%s %s '%s'" % [where, control.get_class(), control.name]
		if role == &"" or not UiSoundTable.has_role(role):
			found.append("%s has no role in the table (%s)" % [label, role])
			continue
		for cue in cues_of(control, role):
			if UiSoundTable.row(role, cue).is_empty():
				found.append("%s: role %s has no row for %s" % [label, role, cue])
	if seen == 0:
		found.append("%s: no interactive control found" % where)
	return found


func test_every_control_of_the_main_menus_tabs_has_a_place_in_the_table() -> void:
	var menu := (await _open(MENU)) as MainMenu
	var lines: Array[String] = []
	for tab in MenuTab.ORDER:
		menu.shell.show_tab(tab, false)
		await _settle()
		lines.append_array(_unknown(menu, "menu tab %s" % MenuTab.label(tab)))
	assert_array(lines).is_empty()


func test_every_control_of_the_settings_tabs_has_a_place_in_the_table() -> void:
	var screen := (await _open(SETTINGS)) as SettingsScreen
	var lines: Array[String] = []
	for tab in screen._pages.size():
		screen.select_tab(tab, false)
		await _settle()
		lines.append_array(_unknown(screen, "settings tab %d" % tab))
	assert_array(lines).is_empty()


func test_every_control_of_the_other_screens_has_a_place_in_the_table() -> void:
	var lines: Array[String] = []
	for path: String in [PLAY, TOGETHER, JOIN, CUSTOMIZE, CREDITS]:
		var screen := await _open(path)
		lines.append_array(_unknown(screen, path.get_file()))
	assert_array(lines).is_empty()


func test_every_control_of_the_lobby_has_a_place_in_the_table() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.me = "a"
	api.lobby = (
		LobbyFixture
		. lobby(
			[
				LobbyFixture.member("a", "Ann", 1, true, false),
				LobbyFixture.member("b", "Bo", 2, false, false),
			]
		)
	)
	var lobby := (await _open(LOBBY, {"lobby": api.lobby, "api": api})) as LobbyScreen
	lobby.watch.every = 3600.0
	lobby.link_label.visible = true
	lobby.copy_link_button.visible = true
	lobby._shares.visible = true
	await _settle()
	assert_array(_unknown(lobby, "lobby")).is_empty()


func test_the_table_names_a_reason_for_every_silence() -> void:
	var silent := 0
	for role: StringName in UiSoundTable.ROLES:
		for cue: StringName in UiSoundTable.ROLES[role]:
			var row: Dictionary = UiSoundTable.ROLES[role][cue]
			if UiSoundTable.is_silent(row):
				silent += 1
				(
					assert_str(row.get("why", ""))
					. override_failure_message("%s/%s is silent with no reason" % [role, cue])
					. is_not_empty()
				)
			else:
				(
					assert_bool(row.has("sound") and row.has("weight"))
					. override_failure_message(
						"%s/%s is neither a sound nor a silence" % [role, cue]
					)
					. is_true()
				)
	assert_int(silent).is_greater(0)


## A recorder in place of the service: the cue and the role of the control that sent it.
func _record() -> void:
	_cues.clear()
	UIAudio.handler = func(cue: StringName, source: Object = null) -> void:
		_cues.append([cue, UiSounds.role_of(source) if source != null else &""])


func _sent(cue: StringName, role: StringName) -> bool:
	return _cues.any(func(pair: Array) -> bool: return pair[0] == cue and pair[1] == role)


func _fresh(control: Control) -> Control:
	auto_free(control)
	add_child(control)
	return control


func test_a_ticket_sends_a_hover_then_a_focus_and_a_press_with_its_role() -> void:
	UIInputMode.pointer = true
	for case: Array in [
		[&"ticket", false, false],
		[&"ticket_start", true, false],
		[&"ticket_soon", false, true],
	]:
		var ticket := MenuItemButton.new()
		ticket.admit = case[1]
		ticket.placeholder = case[2]
		_fresh(ticket)
		_record()
		ticket.mouse_entered.emit()
		ticket.pressed.emit()
		var role: StringName = case[0]
		assert_bool(_sent(&"hover", role)).override_failure_message("hover " + role).is_true()
		assert_bool(_sent(&"focus", role)).override_failure_message("focus " + role).is_true()
		assert_bool(_sent(&"press", role)).override_failure_message("press " + role).is_true()


func test_a_tab_a_chip_a_challenge_and_a_map_card_send_their_cues() -> void:
	var tab := MenuTabBar.TabButton.new(MenuTab.Id.SHOP)
	_fresh(tab)
	_record()
	tab.mouse_entered.emit()
	tab.pressed.emit()
	assert_bool(_sent(&"hover", &"tab")).is_true()
	assert_bool(_sent(&"press", &"tab")).is_true()
	var chip := ChallengesPanel.FamilyChip.new("Orders")
	_fresh(chip)
	_record()
	chip.pressed.emit()
	assert_bool(_sent(&"press", &"chip")).is_true()
	var swap := ChallengeRow.make({"text": "Swap me", "slot": 1, "progress": 0, "target": 3}, 440.0)
	_fresh(swap)
	_record()
	swap.pressed.emit()
	assert_bool(_sent(&"press", &"sheet_row_swap")).is_true()
	var reading := ChallengeRow.make({"text": "Read me", "progress": 0, "target": 3}, 440.0)
	_fresh(reading)
	assert_str(UiSounds.role_of(reading)).is_equal("sheet_row")
	var card := MapCard.new()
	_fresh(card)
	card.info = MapRegistry.all()[0]
	_record()
	card.pressed.emit()
	assert_bool(_cues.any(func(pair: Array) -> bool: return pair[0] == &"press")).is_true()


func test_the_tab_bar_makes_one_tab_sound_for_a_change_and_none_for_the_same_tab() -> void:
	var bar := MenuTabBar.new()
	_fresh(bar)
	_record()
	bar.set_tab(MenuTab.Id.SHOP)
	assert_bool(_sent(&"tab", &"tab_bar")).is_true()
	assert_int(bar.get_meta(UiSounds.DIRECTION_META)).is_equal(1)
	_record()
	bar.set_tab(MenuTab.Id.SHOP)
	assert_array(_cues).is_empty()
	bar.set_tab(MenuTab.Id.PLAY)
	assert_int(bar.get_meta(UiSounds.DIRECTION_META)).is_equal(-1)
	# A key that wraps from the last tab to the first goes on.
	bar.set_tab(MenuTab.Id.MORE)
	_record()
	bar.set_tab(MenuTab.Id.PLAY, 1)
	assert_int(bar.get_meta(UiSounds.DIRECTION_META)).is_equal(1)


func test_the_addons_controls_send_their_cues_with_themselves() -> void:
	UIInputMode.pointer = true
	var toggle := UIToggle.new()
	_fresh(toggle)
	_record()
	toggle.button_pressed = true
	toggle.button_pressed = false
	assert_bool(_sent(&"on", &"toggle")).is_true()
	assert_bool(_sent(&"off", &"toggle")).is_true()
	var selector := UIOptionSelector.new()
	selector.options = PackedStringArray(["a", "b", "c"])
	_fresh(selector)
	_record()
	selector.step(1)
	assert_bool(_sent(&"select", &"option")).is_true()
	var button := UIButton.new()
	button.text = "Back"
	_fresh(button)
	_record()
	button.pressed.emit()
	assert_bool(_sent(&"press", &"back_button")).is_true()


func test_no_cue_is_sent_without_its_source() -> void:
	# Every `UIAudio.play` in the game's and the addon's code names who made it: a cue with no
	# source is a control that plays by its cue alone and slips past the table.
	var bare := RegEx.new()
	bare.compile('UIAudio\\.play(?:\\.bind)?\\(&"\\w+"\\)')
	var unnamed := PackedStringArray()
	for root in ["res://ui", "res://addons/gds_ui", "res://core"]:
		for path in _scripts(root):
			var text := FileAccess.get_file_as_string(path)
			if bare.search(text) != null:
				unnamed.append(path)
	assert_array(Array(unnamed)).is_empty()


func _scripts(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append("%s/%s" % [root, file])
	for sub in dir.get_directories():
		out.append_array(_scripts("%s/%s" % [root, sub]))
	return out
