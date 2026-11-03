extends Node
## Stills of the bots' skill and cast (#230), at the window's real pixel size, one PNG each into
## `--out=<folder>` named `<--label=><step>`: Solo's Play screen with the Bots count and the skill
## beside it, the same with 3 veteran bots chosen, the room host's lobby with 3 veteran bots asked
## for and 2 people in it (the 2 open seats show the veterans by name), and the night that starts
## with 3 veteran bots, in the break and a few seconds into round 1. Run it through the no-focus
## launcher, not headless: `gds godot -- --path game res://tests/captures/bots_slots_tour.tscn
## --windowed --resolution 1280x720 -- --out=<folder> --label=desktop`. Never moves the real
## mouse.

const MENU := "res://ui/screens/main_menu.tscn"
const LOBBY := "res://ui/screens/lobby_screen.tscn"
const SETTLE := 2.4
const NIGHT_WAIT := 6.0
const NIGHT_PLAY := 14.0

var _out := "user://bots_slots_tour"
var _label := "after"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--label="):
			_label = arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://bots_slots_capture.cfg"
	Settings.reset_defaults()
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await get_tree().create_timer(SETTLE).timeout
	await _room()
	var menu := UIRouter.top() as MainMenu
	var solo := (menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel).button(&"solo")
	await _press(solo)
	await _still("1-solo")
	var screen := UIRouter.top()
	var panel: MatchSettingsPanel = screen.get("panel")
	panel.bots_selector.select(3, true)
	panel.skill_selector.select(MatchSettings.SKILL_VETERAN, true)
	await _still("2-solo-3-veterans")
	await _press(screen.get("start_button"))
	await get_tree().create_timer(NIGHT_WAIT).timeout
	await _still("4-night-break")
	var night: Night = (UIRouter.top() as NightScreen).night
	print("bots seated: ", night.bots.count(), " players: ", night.server.rules.players.size())
	for bot in night.bots.host.bots:
		print(
			"  seat ",
			bot.state.player_id,
			" ",
			night.bots.names()[bot.state.player_id],
			" ",
			bot.profile.title
		)
	# Round 1 begins (the HUD hears it as a client would) and the player turns to the nearest bot.
	night.state.apply_events(night.server.rules.apply(RulesAction.skip_break()))
	await get_tree().create_timer(NIGHT_PLAY).timeout
	_look_at_nearest_bot(night)
	await _still("5-night-round-1")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.reset_defaults()
	MainMenu.board_factory = Callable()
	get_tree().quit()


## The host's lobby over the menu: three bots asked for, two shown in the open seats; back to the
## menu after.
func _room() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	UIRouter.push(LOBBY, UITransition.Kind.CUT, {"api": api, "lobby": api.lobby})
	await UIRouter.idle
	var lobby := UIRouter.top() as LobbyScreen
	lobby.watch.every = 3600.0
	lobby.rules.bots_selector.select(3, true)
	lobby.rules.skill_selector.select(MatchSettings.SKILL_VETERAN, true)
	await _still("3-lobby", false)
	UIRouter.pop()
	await UIRouter.idle


## Turns the player's view to the closest bot, so the still shows who the player plays with.
func _look_at_nearest_bot(night: Night) -> void:
	var me := night.server.body_of(Night.PLAYER_ID).global_position
	var best := INF
	var yaw := 0.0
	for id in night.bots.seats():
		var to := night.server.body_of(id).global_position - me
		if to.length() < best:
			best = to.length()
			yaw = atan2(-to.x, -to.z)
	night.player().camera_rig.yaw = yaw
	print("nearest bot ", snappedf(best, 0.1), " m")


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
	for node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control is ColorRect:
			continue
		var rect := control.get_global_rect()
		if rect.size.x > 0.0 and rect.size.y > 0.0 and not canvas.grow(0.5).encloses(rect):
			cut += 1
			print("  outside the window: ", control.get_class(), " ", control.name, " ", rect)
	print("  fit: ", "ok" if cut == 0 else "%d controls outside the %s window" % [cut, canvas.size])
