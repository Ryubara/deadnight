extends Node
## A walk through the real menus with sound (#894): a mouse over the Play column and a fast sweep,
## the keyboard on the same rows, the tabs by Q and E and by click, the shop's real and "Coming"
## rows, the challenge chips, the wardrobe, the settings screen (a tab, a slider dragged, a toggle,
## an option) and back, Credits, and the Play screen of Solo. Every control is reached with the
## events a player sends (mouse motion and buttons, keys); nothing here plays a sound.
##
## Windowed, through the no-focus launcher, with Movie Maker (the picture and the mix of the menu):
## `gds godot -- --path game res://tests/captures/menu_sfx_tour.tscn --write-movie <abs>/tour.avi
## --fixed-fps 30 --resolution 1280x720`. Prints `SFX <seconds> <sound id>` for every sound the
## service starts and `MARK <seconds> <label>` for each beat, which `tools/audio/menu_levels.py`
## reads with the recording. `-- --pad` walks the tabs with the bumpers and the pad's accept.

const MENU := "res://ui/screens/main_menu.tscn"
const FILE := "user://menu_sfx_tour.cfg"

var _t0 := 0
var _pad := false


func _ready() -> void:
	_pad = OS.get_cmdline_user_args().has("--pad")
	Audio.seed_random(11)
	Audio.played.connect(_on_played)
	Settings.path = FILE
	Settings.reset_defaults()
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()
	UIRouter.reset(MENU, UITransition.Kind.FADE)
	await UIRouter.idle
	_t0 = Engine.get_frames_drawn()
	_mark("menu in: the sign lights")
	await _wait(2.2)

	var menu := UIRouter.top() as MainMenu
	var shell := menu.shell
	var play := shell.panel(MenuTab.Id.PLAY) as PlayPanel
	var together := play.button(&"together")
	var browser := play.button(&"browser")
	var solo := play.button(&"solo")

	_mark("mouse over the three starts, slowly")
	for target: Control in [together, browser, solo, browser, together]:
		await _move_to(target)
		await _wait(0.45)
	_mark("mouse sweep over the starts, fast, three times")
	for _i in 3:
		for target: Control in [together, browser, solo, browser]:
			await _move_to(target)
			await _wait(0.06)
	await _wait(0.6)
	_mark("keyboard Down and Up over the starts")
	together.grab_focus()
	await _wait(0.4)
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _key(KEY_UP)
	await _wait(0.5)

	_mark("tabs by E, then Q")
	for _i in 4:
		await _tab_key(KEY_E)
	for _i in 4:
		await _tab_key(KEY_Q)
	_mark("tabs by click: Shop, Challenges, Loadout, Play")
	for id: MenuTab.Id in [
		MenuTab.Id.SHOP, MenuTab.Id.CHALLENGES, MenuTab.Id.LOADOUT, MenuTab.Id.PLAY
	]:
		await _click(shell.tab_bar.button(id))
		await _wait(0.7)

	_mark("shop: a row, a coming row")
	await _click(shell.tab_bar.button(MenuTab.Id.SHOP))
	await _wait(0.6)
	var shop := shell.panel(MenuTab.Id.SHOP) as ShopPanel
	var rows := shop.rows()
	await _move_to(rows[0])
	await _wait(0.4)
	await _click(rows[0])
	await _wait(0.5)
	await _move_to(rows[rows.size() - 1])
	await _wait(0.4)
	await _click(rows[rows.size() - 1])
	await _wait(0.6)

	_mark("challenges: the chips")
	await _click(shell.tab_bar.button(MenuTab.Id.CHALLENGES))
	await _wait(0.6)
	var board := shell.panel(MenuTab.Id.CHALLENGES) as ChallengesPanel
	for family: ChallengesPanel.Family in [
		ChallengesPanel.Family.DAILY, ChallengesPanel.Family.ORDER, ChallengesPanel.Family.ALL
	]:
		await _click(board.chip(family))
		await _wait(0.45)

	_mark("loadout: the wardrobe")
	await _click(shell.tab_bar.button(MenuTab.Id.LOADOUT))
	await _wait(0.8)
	var loadout := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	var selector := loadout.selector()
	for _i in 3:
		await _click(selector)
		await _wait(0.4)
	for strip in loadout.find_children("*", "ChoiceStrip", true, false):
		for _i in 3:
			await _key_on(strip, KEY_RIGHT)
			await _wait(0.2)
		break

	_mark("more: Settings")
	await _click(shell.tab_bar.button(MenuTab.Id.MORE))
	await _wait(0.6)
	var more := shell.panel(MenuTab.Id.MORE) as MorePanel
	await _move_to(more.find_child("settings", true, false))
	await _wait(0.4)
	await _click(more.find_child("settings", true, false))
	await _wait(1.4)

	var settings := UIRouter.top() as SettingsScreen
	_mark("settings: the Audio tab, a slider drag, a toggle")
	var tab_buttons := settings.find_children("*", "UIButton", true, false)
	for button in tab_buttons:
		if (button as UIButton).variant == UIButton.Variant.GHOST:
			if (button as UIButton).text == "Audio":
				await _click(button)
				break
	await _wait(0.6)
	# The last slider of the page is the interface volume: the drag is heard through itself.
	var sliders := settings.find_children("*", "UISlider", true, false).filter(
		func(node: Node) -> bool: return (node as Control).is_visible_in_tree()
	)
	await _drag_slider(sliders[sliders.size() - 1])
	await _wait(0.5)
	_mark("settings: Accessibility toggle and an option")
	for button in tab_buttons:
		if (button as UIButton).text == "Accessibility":
			await _click(button)
			break
	await _wait(0.6)
	for toggle in settings.find_children("*", "UIToggle", true, false):
		if toggle.is_visible_in_tree():
			await _click(toggle)
			await _wait(0.4)
			await _click(toggle)
			await _wait(0.4)
			break
	for option in settings.find_children("*", "UIOptionSelector", true, false):
		if option.is_visible_in_tree():
			await _click(option)
			await _wait(0.4)
			break
	_mark("settings: back")
	await _key(KEY_ESCAPE)
	await UIRouter.idle
	await _wait(1.0)

	_mark("credits and back")
	await _click(more.find_child("credits", true, false))
	await _wait(2.2)
	await _key(KEY_ESCAPE)
	await UIRouter.idle
	await _wait(1.0)

	_mark("play: Solo, the Play screen, back")
	await _click(shell.tab_bar.button(MenuTab.Id.PLAY))
	await _wait(0.6)
	await _click(solo)
	await UIRouter.idle
	await _wait(1.6)
	await _key(KEY_ESCAPE)
	await UIRouter.idle
	await _wait(1.0)
	_mark("end")
	await _wait(0.5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	MainMenu.board_factory = Callable()
	Audio.played.disconnect(_on_played)
	Audio.stop_all()
	await get_tree().process_frame
	get_tree().quit()


func _seconds() -> float:
	return (Engine.get_frames_drawn() - _t0) / 30.0


func _mark(label: String) -> void:
	print("MARK %.3f %s" % [_seconds(), label])


func _on_played(id: StringName, _position: Variant) -> void:
	print("SFX %.3f %s" % [_seconds(), id])


func _wait(seconds: float) -> void:
	for _i in int(round(seconds * 30.0)):
		await get_tree().process_frame


func _centre(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


func _motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	get_viewport().push_input(event, true)


func _move_to(control: Control) -> void:
	UIInputMode.pointer = true
	_motion(_centre(control) + Vector2(-3, 0))
	await get_tree().process_frame
	_motion(_centre(control))
	await get_tree().process_frame


func _click(control: Control) -> void:
	await _move_to(control)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = _centre(control)
	down.global_position = down.position
	get_viewport().push_input(down, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	get_viewport().push_input(up, true)
	await get_tree().process_frame
	await _wait(0.1)


func _key(keycode: Key) -> void:
	UIInputMode.pointer = false
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := down.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await _wait(0.25)


func _key_on(control: Control, keycode: Key) -> void:
	control.grab_focus()
	await _key(keycode)


func _tab_key(keycode: Key) -> void:
	await _key(keycode)
	await _wait(0.5)


## A drag of the slider's knob from the left to the right and back, in pointer events.
func _drag_slider(slider: Control) -> void:
	var rect := slider.get_global_rect()
	var y := rect.get_center().y
	await _move_to(slider)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(rect.position.x + rect.size.x * 0.5, y)
	down.global_position = down.position
	get_viewport().push_input(down, true)
	await get_tree().process_frame
	for step in 24:
		var fraction := 0.5 + 0.45 * (float(step) / 23.0)
		_motion(Vector2(rect.position.x + rect.size.x * fraction, y))
		await get_tree().process_frame
	for step in 24:
		var fraction := 0.95 - 0.15 * (float(step) / 23.0)
		_motion(Vector2(rect.position.x + rect.size.x * fraction, y))
		await get_tree().process_frame
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	get_viewport().push_input(up, true)
	await get_tree().process_frame
