extends GdUnitTestSuite
## The Loadout tab keeps what the player picks (#489): an outfit, a colour and the showcase weapon
## are held while the panel is open, survive changing another choice and leaving for another tab,
## and are written once when the player leaves, not on every click. The menu is the real one, the
## picks are real mouse clicks, and "on disk" is the settings file read back from its path.

const TEST_PATH := "user://loadout_keeps_choices_test.cfg"

var _saved_path: String
var _window_before: Vector2i
var _motion_before: bool
var _actions: Array[StringName] = []


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_saved_path = Settings.path
	_motion_before = UIMotion.reduced
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	Settings.save()
	UIInputMode.reset()
	UIMotion.reduced = true
	_actions.clear()
	_window_before = get_window().size
	get_window().size = Vector2i(1920, 1080)


func after_test() -> void:
	get_window().size = _window_before
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	UIMotion.reduced = _motion_before
	UIInputMode.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	await RouterFixture.clear(get_tree())


func _open() -> MenuShell:
	var shell := MenuShell.new()
	shell.manual_stage = true
	shell.phone_mode = 0
	shell.context.board = FakeChallengeBoard.new()
	shell.context.profile = MenuProfile.from_json(MenuProfile.to_json("Ann", 0, 0))
	shell.context.action.connect(func(id: StringName) -> void: _actions.append(id))
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	auto_free(layer)
	layer.add_child(shell)
	await get_tree().process_frame
	await get_tree().process_frame
	return shell


func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	get_viewport().push_input(move, true)
	await get_tree().process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		get_viewport().push_input(click, true)
		await get_tree().process_frame


func _go_to(shell: MenuShell, id: MenuTab.Id) -> void:
	await _click(shell.tab_bar.button(id))
	assert_int(shell.tab).is_equal(id)


## What a player does on the tab: a face by a click on its cell and a skin colour by choosing it.
func _pick_outfit(shell: MenuShell) -> void:
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	var slot := LookCatalog.choosable_part_slots()[0]
	var colour := LookCatalog.colour_slots()[0]
	var face := panel.wardrobe.cell(CustomizeScreen.PART_PREFIX + slot, 1)
	panel.wardrobe.reveal(face)
	await get_tree().process_frame
	await _click(face)
	var next_colour := (
		(int(panel.wardrobe.look.colours[colour]) + 3) % LookCatalog.palette(colour).size()
	)
	panel.wardrobe.choose(CustomizeScreen.COLOUR_PREFIX + colour, next_colour)


func _pick_weapon(shell: MenuShell) -> StringName:
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	await _click(panel.selector())
	return panel.weapons()[panel.selector().selected]


func test_the_outfit_survives_changing_the_showcase_weapon() -> void:
	var shell := await _open()
	await _go_to(shell, MenuTab.Id.LOADOUT)
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	var before := panel.wardrobe.look.duplicate_look()
	await _pick_outfit(shell)
	var picked := panel.wardrobe.look.duplicate_look()
	assert_bool(picked.equals(before)).is_false()
	var weapon := await _pick_weapon(shell)
	assert_str(String(weapon)).is_not_equal("rifle")
	assert_bool(panel.wardrobe.look.equals(picked)).is_true()
	assert_bool(shell.view.stage.hero.look.equals(picked)).is_true()
	assert_str(String(shell.view.stage.hero.weapon_id)).is_equal(String(weapon))


func test_the_character_survives_the_weapon_another_tab_and_a_restart() -> void:
	var shell := await _open()
	await _go_to(shell, MenuTab.Id.LOADOUT)
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	await _click(panel.wardrobe.cell(CustomizeScreen.PART_PREFIX + "body", 1))
	assert_str(String(panel.wardrobe.look.body())).is_equal("female")
	var picked := panel.wardrobe.look.duplicate_look()
	await _pick_weapon(shell)
	assert_bool(panel.wardrobe.look.equals(picked)).is_true()
	# The menu's soldier is her at once, before anything is saved.
	assert_bool(shell.view.stage.hero.look.equals(picked)).is_true()
	var hero := shell.view.stage.hero.model
	assert_bool((hero.find_child("head__plain__female", true, false) as Node3D).visible).is_true()
	await _go_to(shell, MenuTab.Id.SHOP)
	await _go_to(shell, MenuTab.Id.LOADOUT)
	assert_str(String(panel.wardrobe.look.body())).is_equal("female")
	assert_bool(panel.wardrobe.cell(CustomizeScreen.PART_PREFIX + "body", 1).worn).is_true()
	# As after a restart: the file read back from its path.
	Settings.load_from_disk()
	assert_str(String(LookStore.load_look().body())).is_equal("female")
	assert_bool(LookStore.load_look().equals(picked)).is_true()


func test_every_choice_survives_another_tab_and_coming_back() -> void:
	var shell := await _open()
	await _go_to(shell, MenuTab.Id.LOADOUT)
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	await _pick_outfit(shell)
	var picked := panel.wardrobe.look.duplicate_look()
	var weapon := await _pick_weapon(shell)
	await _go_to(shell, MenuTab.Id.SHOP)
	# The soldier on the other tabs wears what was picked.
	assert_bool(shell.view.stage.hero.look.equals(picked)).is_true()
	assert_str(String(shell.view.stage.hero.weapon_id)).is_equal(String(weapon))
	await _go_to(shell, MenuTab.Id.LOADOUT)
	assert_bool(panel.wardrobe.look.equals(picked)).is_true()
	assert_str(String(panel.weapons()[panel.selector().selected])).is_equal(String(weapon))
	assert_bool(shell.view.stage.hero.look.equals(picked)).is_true()


func test_every_choice_is_on_disk_after_leaving_the_tab() -> void:
	var shell := await _open()
	await _go_to(shell, MenuTab.Id.LOADOUT)
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	await _pick_outfit(shell)
	var picked := panel.wardrobe.look.duplicate_look()
	var weapon := await _pick_weapon(shell)
	await _go_to(shell, MenuTab.Id.CHALLENGES)
	Settings.load_from_disk()
	assert_bool(LookStore.load_look().equals(picked)).is_true()
	assert_str(String(MenuHero.saved_weapon())).is_equal(String(weapon))


func test_a_visit_writes_the_file_once_not_once_per_click() -> void:
	var shell := await _open()
	var writes := Settings.write_count
	await _go_to(shell, MenuTab.Id.LOADOUT)
	await _pick_outfit(shell)
	await _pick_weapon(shell)
	await _pick_weapon(shell)
	await _pick_outfit(shell)
	assert_int(Settings.write_count).is_equal(writes)
	await _go_to(shell, MenuTab.Id.SHOP)
	assert_int(Settings.write_count).is_equal(writes + 1)
	# Going on to other tabs, and a visit with no change, write nothing more.
	await _go_to(shell, MenuTab.Id.LOADOUT)
	await _go_to(shell, MenuTab.Id.MORE)
	assert_int(Settings.write_count).is_equal(writes + 1)


func test_asking_for_a_screen_from_the_loadout_tab_saves_first() -> void:
	var shell := await _open()
	await _go_to(shell, MenuTab.Id.LOADOUT)
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	await _pick_outfit(shell)
	var picked := panel.wardrobe.look.duplicate_look()
	var weapon := await _pick_weapon(shell)
	var writes := Settings.write_count
	shell.context.request(&"solo")
	assert_array(_actions).is_equal([&"solo"])
	assert_int(Settings.write_count).is_equal(writes + 1)
	Settings.load_from_disk()
	assert_bool(LookStore.load_look().equals(picked)).is_true()
	assert_str(String(MenuHero.saved_weapon())).is_equal(String(weapon))


func test_closing_the_menu_on_the_loadout_tab_saves_what_was_picked() -> void:
	var shell := await _open()
	await _go_to(shell, MenuTab.Id.LOADOUT)
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	await _pick_outfit(shell)
	var picked := panel.wardrobe.look.duplicate_look()
	var weapon := await _pick_weapon(shell)
	var writes := Settings.write_count
	shell.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_int(Settings.write_count).is_equal(writes + 1)
	# Freed afterwards, nothing more is written.
	shell.get_parent().remove_child(shell)
	shell.free()
	assert_int(Settings.write_count).is_equal(writes + 1)
	Settings.load_from_disk()
	assert_bool(LookStore.load_look().equals(picked)).is_true()
	assert_str(String(MenuHero.saved_weapon())).is_equal(String(weapon))


func test_a_costume_put_on_by_a_click_is_kept_across_tabs_and_written_when_the_player_leaves(
) -> void:
	# A new player (level 1) owns the carhop costume: it is made of starting pieces.
	var shell := await _open()
	await _go_to(shell, MenuTab.Id.LOADOUT)
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	panel.wardrobe.show_tab(&"costumes")
	await get_tree().process_frame
	await get_tree().process_frame
	var carhop := panel.wardrobe.costume_cell(8)
	assert_bool(carhop.locked).is_false()
	panel.wardrobe.reveal(carhop)
	await get_tree().process_frame
	await _click(carhop)
	var picked := CharacterLook.from_preset(8)
	assert_bool(panel.wardrobe.look.equals(picked)).is_true()
	assert_bool(carhop.worn).is_true()
	# The menu's soldier wears her at once; nothing is on disk until the player leaves the tab.
	assert_bool(shell.view.stage.hero.look.equals(picked)).is_true()
	assert_bool(LookStore.load_look().equals(picked)).is_false()
	await _go_to(shell, MenuTab.Id.SHOP)
	await _go_to(shell, MenuTab.Id.LOADOUT)
	assert_bool(panel.wardrobe.costume_cell(8).worn).is_true()
	Settings.load_from_disk()
	assert_bool(LookStore.load_look().equals(picked)).is_true()


func test_the_plate_row_says_what_is_worn_and_asks_the_menu_for_the_cards_screen() -> void:
	var path := "user://loadout_plate_profile.json"
	var profile := Profile.new()
	profile.xp = LevelCurve.xp_for(10)
	profile.done = [&"f_dead_eye"]
	profile.equipped = {"card": "dead_eye", "emblem": "cartoon"}
	ProfileSave.write(profile, [], 1, path)
	MenuProfile.profile_path = path
	var shell := await _open()
	await _go_to(shell, MenuTab.Id.LOADOUT)
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	assert_str(panel.plate_text()).is_equal("Dead Eye + Cartoon")
	await _click(panel.plate_button())
	assert_array(_actions).contains([&"cards"])
	MenuProfile.profile_path = ProfileSave.DEFAULT_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
