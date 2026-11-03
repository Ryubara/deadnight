extends Node
## Stills of the map picker (#624), at the window's real pixel size, one PNG each into
## `--out=<folder>` named `<--label=><step>`: the menu's Play tab (what the picker sits beside),
## Solo's Play screen with the picker, the keyboard on the card that is not built yet (a press
## chooses nothing), the room host's lobby (the picker beside the other rules), a guest's lobby
## (the host's map, read only), a code looked at, and Quick join having found a night. It prints
## the screen each step shows and whether its controls fit the window. Run through the no-focus
## launcher, not headless: `gds godot -- --path game res://tests/captures/map_picker_tour.tscn
## --windowed --resolution 1280x720 -- --out=<folder> --label=desktop`; a phone is
## `--resolution 844x390` (the menu's phone factor applies, as on a phone held sideways). Never
## moves the real mouse.

const MENU := "res://ui/screens/main_menu.tscn"
const LOBBY := "res://ui/screens/lobby_screen.tscn"
const SETTLE := 2.2

var _out := "user://map_picker_tour"
var _label := "after"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--label="):
			_label = arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://map_picker_capture.cfg"
	Settings.reset_defaults()
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await _still("1-play-tab")
	var menu := UIRouter.top() as MainMenu
	var solo := (menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel).button(&"solo")
	await _press(solo)
	await _still("2-solo")
	var screen := UIRouter.top() as PlayScreen
	if screen != null:
		# The keyboard walks onto the card of the map that is not built and presses it.
		# The locked card is under the lot's on the desktop and beside it on a phone.
		screen.panel.map_picker.card_for("drive_in").grab_focus()
		await _key(KEY_RIGHT if MenuScale.is_phone(get_window().size) else KEY_DOWN)
		await _key(KEY_ENTER)
		print("  after Enter on the locked card the map is ", screen.panel.map_picker.selected_id)
		await _still("3-solo-locked-card")
		UIRouter.pop()
		await UIRouter.idle
	await _room(true, "4-host-lobby")
	await _room(false, "5-guest-lobby")
	await _preview()
	await _quick_join()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.reset_defaults()
	# A lambda left in a static variable crashes the engine at quit (docs/godot/exit-code-139.md).
	MainMenu.board_factory = Callable()
	get_tree().quit()


## A lobby over the menu: the host's, or a guest's (read only); back to the menu after.
func _room(host: bool, step: String) -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.me = "a" if host else "b"
	var members := [LobbyFixture.member("a", "Ann", 1, true)]
	if not host:
		members.append(LobbyFixture.member("b", "Bo", 2))
	api.lobby = LobbyFixture.lobby(members)
	UIRouter.push(LOBBY, UITransition.Kind.CUT, {"api": api, "lobby": api.lobby})
	await UIRouter.idle
	var lobby := UIRouter.top() as LobbyScreen
	lobby.watch.every = 3600.0
	await get_tree().process_frame
	# The rules are below the seats: scroll to the picker, as a focus on it does.
	await get_tree().process_frame
	var scroll := lobby._scroll
	scroll.scroll_vertical = int(
		(
			lobby.rules.map_row.global_position.y
			- scroll.global_position.y
			+ scroll.scroll_vertical
			- 24.0
		)
	)
	await _still(step)
	UIRouter.pop()
	await UIRouter.idle


## A code looked at: the room's map as a ticket under the seats.
func _preview() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.preview_answer = LobbyFixture.preview("open", null, 2)
	UIRouter.push(LOBBY, UITransition.Kind.CUT, {"api": api, "preview": api.preview_answer})
	await UIRouter.idle
	var lobby := UIRouter.top() as LobbyScreen
	lobby.watch.every = 3600.0
	await _still("6-code-preview")
	UIRouter.pop()
	await UIRouter.idle


## Quick join pressed with a backend that answers at once: the card names the map of the night it
## found for the moment before the night opens (held here, so the capture can see it).
func _quick_join() -> void:
	var menu := UIRouter.top() as MainMenu
	QuickJoinOverlay.api_factory = func(_parent: Node) -> TogetherApi: return _SlowApi.new(self)
	QuickJoinOverlay.opener = func() -> void: pass
	var play := menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel
	play.button(&"quick_join").pressed.emit()
	await get_tree().create_timer(0.6).timeout
	await _still("7-quick-join")
	# Let the slow ticket give up, so the overlay is gone before the program quits.
	await get_tree().create_timer(_SlowApi.TICKET_SECONDS + 1.0).timeout
	QuickJoinOverlay.api_factory = Callable()
	QuickJoinOverlay.opener = Callable()


## The backend a Quick join talks to, found a night and slow to give the ticket.
class _SlowApi:
	extends TogetherApi
	const TICKET_SECONDS := 3.0

	func sign_in(_display_name: String = "") -> Dictionary:
		return {"ok": true}

	func quick() -> Dictionary:
		return {"ok": true, "lobby": {"id": "q1", "code": "QUICK1", "state": "started"}}

	func ticket(_held: Dictionary) -> Dictionary:
		await _parent.get_tree().create_timer(TICKET_SECONDS).timeout
		return {"ok": false, "text": "never"}

	func leave(_held: Dictionary) -> Dictionary:
		return {"ok": true}

	func detached(_parent_node: Node) -> TogetherApi:
		return self


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().create_timer(0.1).timeout


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


func _still(step: String) -> void:
	await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var path := "%s/%s-%s.png" % [_out, _label, step]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, " window ", get_window().size, " top ", UIRouter.top().name)
	_check_fit(UIRouter.top())


## Prints what of the screen's controls lies outside the window (real fonts, so the real heights).
## A lobby scrolls: only the controls it shows are asked to fit.
func _check_fit(screen: Node) -> void:
	var canvas := get_viewport().get_visible_rect()
	var cut := 0
	var tokens := UITokens.active()
	var ring := float(tokens.focus_gap + tokens.focus_border)
	for node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control is ColorRect or screen is LobbyScreen:
			continue
		var rect := control.get_global_rect()
		if control is BaseButton:
			rect = rect.grow(ring)  # the focus ring is drawn outside the button
		if rect.size.x > 0.0 and rect.size.y > 0.0 and not canvas.grow(0.5).encloses(rect):
			cut += 1
			print("  outside the window: ", control.get_class(), " ", control.name, " ", rect)
	print("  fit: ", "ok" if cut == 0 else "%d controls outside the %s window" % [cut, canvas.size])
