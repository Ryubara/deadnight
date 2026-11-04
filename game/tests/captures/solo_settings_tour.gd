extends Node
## Stills of what Solo offers (#620), at the window's real pixel size, one PNG each into
## `--out=<folder>` named `<--label=><step>`: the menu, the room host's lobby over it (the
## reference for the settings), Solo pressed (a tap with a finger when the window is a phone's, a
## click otherwise), what opens, the same with another intensity and unlimited perks chosen, and
## the night that starts.
## Run it before and after the change with the same arguments; it prints the screen each step shows
## and whether its controls fit the window. Run through the no-focus launcher, not headless:
## `gds godot -- --path game res://tests/captures/solo_settings_tour.tscn --windowed
## --resolution 1280x720 -- --out=<folder> --label=after`. Never moves the real mouse.

const MENU := "res://ui/screens/main_menu.tscn"
const LOBBY := "res://ui/screens/lobby_screen.tscn"
const SETTLE := 2.4
const NIGHT_WAIT := 6.0

var _out := "user://solo_settings_tour"
var _label := "after"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--label="):
			_label = arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://solo_settings_capture.cfg"
	Settings.reset_defaults()
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await _still("1-menu")
	await _room()
	var menu := UIRouter.top() as MainMenu
	var solo := (menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel).button(&"solo")
	await _press(solo)
	await _still("2-solo")
	var screen := UIRouter.top()
	var panel: Variant = screen.get("panel")
	if panel != null:
		var loud := MatchSettings.new()
		loud.count_multiplier = 3.0
		loud.max_alive = 12
		loud.break_seconds = 15.0
		loud.perk_limit = MatchSettings.PERKS_UNLIMITED
		panel.set_settings(loud)
		await _still("3-solo-3x")
		await _press(screen.get("start_button"))
	await get_tree().create_timer(NIGHT_WAIT).timeout
	await _still("4-night")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.reset_defaults()
	# The lambda belongs to this script, which the engine frees before the menu's static variable: a
	# variable still holding it at quit crashes the process (exit 139, #667).
	MainMenu.board_factory = Callable()
	get_tree().quit()


## The host's lobby over the menu: the settings a room offers; back to the menu after.
func _room() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	UIRouter.push(LOBBY, UITransition.Kind.CUT, {"api": api, "lobby": api.lobby})
	await UIRouter.idle
	var lobby := UIRouter.top() as LobbyScreen
	lobby.watch.every = 3600.0
	await _still("1b-room", false)
	UIRouter.pop()
	await UIRouter.idle


## A tap on `control`: a finger on a phone, a click elsewhere.
func _press(control: Control) -> void:
	var point := get_viewport().get_final_transform() * control.get_global_rect().get_center()
	var phone := MenuScale.is_phone(get_window().size)
	for pressed in [true, false]:
		var event: InputEvent
		if phone:
			var touch := InputEventScreenTouch.new()
			touch.index = 0
			touch.position = point
			touch.pressed = pressed
			event = touch
		else:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.position = point
			click.global_position = point
			click.pressed = pressed
			event = click
		Input.parse_input_event(event)
		await get_tree().create_timer(0.12).timeout


func _still(step: String, check := true) -> void:
	await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var path := "%s/%s-%s.png" % [_out, _label, step]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, " window ", get_window().size, " top ", UIRouter.top().name)
	if check:
		_check_fit(UIRouter.top())


## Prints what of the screen's controls lies outside the window (real fonts, so the real heights).
func _check_fit(screen: Node) -> void:
	var canvas := get_viewport().get_visible_rect()
	var cut := 0
	var tokens := UITokens.active()
	var ring := float(tokens.focus_gap + tokens.focus_border)
	for node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control is ColorRect:
			continue
		var rect := control.get_global_rect()
		if control is BaseButton:
			rect = rect.grow(ring)  # the focus ring is drawn outside the button
		if rect.size.x > 0.0 and rect.size.y > 0.0 and not canvas.grow(0.5).encloses(rect):
			cut += 1
			print("  outside the window: ", control.get_class(), " ", control.name, " ", rect)
	print("  fit: ", "ok" if cut == 0 else "%d controls outside the %s window" % [cut, canvas.size])
