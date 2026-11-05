extends Node
## Stills and a clip of the Server Browser (#1180). Run through the no-focus launcher, not headless:
##
## gds godot -- --path game res://tests/captures/server_browser_tour.tscn --windowed --resolution
## 1920x1080
##       -- --out=<folder> --label=desktop
##
## `--mode=stills` (default): the Play tab, the list of nights of both kinds with the focus on a
## row, a press on its way, an empty list, a failed one and one still loading, each into
## `<--out>/<--label>-<n>-<step>.png` (the backend's answers come from `BrowserFixture`, so every
## state is on demand). `--mode=jump`: the real backend (Node, `BackendFixture`) with other players'
## nights on it, and one player who jumps from the menu into a waiting lobby, from that lobby into
## another, and then presses a night in progress. Run it under Movie Maker for the clip:
## `--write-movie <out>.png --fixed-fps 10 --quit-after N`; it ends by itself.
##
## A phone page is `--resolution 1688x780 -- --factor=2` (the canvas of an 844 x 390 CSS pixel page
## at ratio 2, with the phone scale the menu is meant to run at: the window's own test for a phone
## does not see it until #1197 lands); `--resolution 844x390` is the pixel ratio 1 worst case and
## needs no factor.

const MENU := "res://ui/screens/main_menu.tscn"
const SETTLE := 0.9

var _out := "user://server_browser_tour"
var _label := "desktop"
var _mode := "stills"
var _factor := 0.0
var _api: BrowserFixture.FakeApi
var _shots := 0
var _backend: BackendFixture


func _ready() -> void:
	PlayerLevel.use(10)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--label="):
			_label = arg.trim_prefix("--label=")
		elif arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--factor="):
			_factor = float(arg.trim_prefix("--factor="))
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://server_browser_capture.cfg"
	Settings.reset_defaults()
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _mode == "jump":
		await _jump()
	else:
		await _stills()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.reset_defaults()
	PlayerLevel.reset()
	# A lambda left in a static variable crashes the engine at quit (docs/godot/exit-code-139.md).
	MainMenu.board_factory = Callable()
	ServerBrowserScreen.api_factory = Callable()
	ServerBrowserScreen.opener = Callable()
	if _backend != null:
		_backend.stop()
	get_tree().quit()


# --- Stills ---


func _stills() -> void:
	_use_fake(BrowserFixture.nights())
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	if _factor == 0.0:
		await _still("play-tab")
	var menu := UIRouter.top() as MainMenu
	(menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel).button(&"browser").pressed.emit()
	await UIRouter.idle
	await _wait(0.5)
	await _still("many")
	var browser := UIRouter.top() as ServerBrowserScreen
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _still("focus-on-a-lobby")
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _still("focus-on-a-full-night")
	# A press on its way.
	_api.hold_join = true
	browser.row_of("MOTH05").grab_focus()
	await _key(KEY_ENTER)
	await _still("joining")
	_api.hold_join = false
	_api.released.emit()
	await _wait(0.3)
	_pop()
	await UIRouter.idle
	# Many nights: the list scrolls and the focus follows.
	var crowd := BrowserFixture.nights()
	for index in 9:
		crowd.append(
			BrowserFixture.row(
				"NITE%02d" % index,
				"drive_in" if index % 2 == 0 else "small_indoor",
				"match" if index % 3 == 0 else "lobby",
				1 + index % 6,
				"Player %d" % (index + 1),
				index % 4,
				2 + index if index % 3 == 0 else null
			)
		)
	_api.nights = crowd
	await _open_browser_over_menu()
	for _i in 8:
		await _key(KEY_DOWN)
	await _still("fourteen-nights-scrolled")
	_pop()
	await UIRouter.idle
	# An empty list, a failed one, one still loading.
	_use_fake([])
	await _open_browser_over_menu()
	await _still("empty")
	_pop()
	await UIRouter.idle
	_use_fake([])
	_api.list_failure = "network"
	await _open_browser_over_menu()
	await _still("failed")
	_pop()
	await UIRouter.idle
	_use_fake(BrowserFixture.nights())
	_api.hold_list = true
	await _open_browser_over_menu()
	await _still("loading")
	_api.hold_list = false
	_api.released.emit()


func _use_fake(nights: Array) -> void:
	_api = BrowserFixture.FakeApi.new(self)
	_api.nights = nights
	for night: Dictionary in nights:
		_api.by_code[night["code"]] = BrowserFixture.lobby_of(
			night["code"], night["kind"] == "match", night["map"]
		)
	var held := _api
	ServerBrowserScreen.api_factory = func(_parent: Node) -> TogetherApi: return held
	ServerBrowserScreen.opener = func() -> void: pass


func _open_browser_over_menu() -> void:
	var menu := UIRouter.top() as MainMenu
	menu.shell.context.request(&"browser")
	await UIRouter.idle
	await _wait(0.5)


func _pop() -> void:
	UIRouter.pop()


# --- The jump, on the real backend ---


func _jump() -> void:
	_backend = BackendFixture.new()
	if BackendFixture.why_not() != "" or not await _backend.start(self):
		print("no backend here: ", BackendFixture.why_not())
		return
	await _beat([], {}, {})
	var ann := await _guest("Ann the Projectionist")
	var bo := await _guest("Bo")
	var cy := await _guest("Cy")
	var di := await _guest("Di")
	var running := await _night(ann, "drive_in", 3, true)
	var back_rooms := await _night(bo, "small_indoor", 0, false)
	var lot := await _night(cy, "drive_in", 2, false)
	var late := await _night(di, "drive_in", 1, true)
	await _beat(
		[running["matchId"], late["matchId"]],
		{running["matchId"]: 3, late["matchId"]: 5},
		{running["matchId"]: 6, late["matchId"]: 11}
	)
	var me := await _guest("You")
	ServerBrowserScreen.api_factory = func(_parent: Node) -> TogetherApi: return me
	ServerBrowserScreen.opener = func() -> void: pass
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await _wait(1.0)
	var menu := UIRouter.top() as MainMenu
	var play := menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel
	play.button(&"together").grab_focus()
	await _wait(0.8)
	# 1. Down to the Server browser, Enter: the list.
	await _key(KEY_DOWN)
	await _wait(0.6)
	await _key(KEY_ENTER)
	await _wait(1.6)
	var browser := await _top_is(ServerBrowserScreen) as ServerBrowserScreen
	# 2. Down the list to the back rooms' waiting lobby, Enter: the lobby, with the player in it.
	await _walk_to(browser, str(back_rooms["code"]))
	await _key(KEY_ENTER)
	var lobby := await _top_is(LobbyScreen) as LobbyScreen
	await _wait(2.0)
	# 3. From inside that lobby: the Server browser button, then a press on another waiting lobby.
	lobby.browse_button.grab_focus()
	await _wait(0.8)
	await _key(KEY_ENTER)
	browser = await _top_is(ServerBrowserScreen) as ServerBrowserScreen
	await _wait(1.8)
	await _walk_to(browser, str(lot["code"]))
	await _key(KEY_ENTER)
	lobby = await _top_is(LobbyScreen) as LobbyScreen
	await _wait(2.0)
	# 4. And once more, to a night in progress.
	lobby.browse_button.grab_focus()
	await _wait(0.6)
	await _key(KEY_ENTER)
	browser = await _top_is(ServerBrowserScreen) as ServerBrowserScreen
	await _wait(1.8)
	await _walk_to(browser, str(late["code"]))
	await _key(KEY_ENTER)
	await _wait(1.6)
	print("back rooms lobby ", back_rooms["code"], " lot lobby ", lot["code"])


## Waits until the screen on top is a `kind` (and the router has settled), and returns it.
func _top_is(kind: Script) -> Node:
	for _i in 300:
		if is_instance_of(UIRouter.top(), kind) and not UIRouter.busy:
			return UIRouter.top()
		await _wait(0.1)
	return null


## Presses Down until the focus is on the row of `code` (the list is read again meanwhile: the rows
## can move).
func _walk_to(browser: ServerBrowserScreen, code: String) -> void:
	browser.rows()[0].grab_focus()
	await _wait(0.5)
	for _i in 12:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is NightRow and (focus as NightRow).entry.code == code:
			break
		await _key(KEY_DOWN)
		await _wait(0.3)
	await _wait(0.4)


func _guest(player_name: String) -> TogetherApi:
	var api := TogetherApi.new(self, _backend.url)
	api.isolated = true
	api.guest_path = ""
	await api.sign_in(player_name)
	return api


## A night held by `host`: a waiting lobby, or (`started`) a match, with `bots` bots on `map`.
func _night(host: TogetherApi, map: String, bots: int, started: bool) -> Dictionary:
	var lobby: Dictionary = (await host.create_lobby())["lobby"]
	var rules := MatchSettings.new()
	rules.bots = bots
	rules.map = map
	if started:
		var begun := await host.start(lobby, rules)
		if not begun["ok"]:
			print("start failed: ", begun)
		return begun["lobby"]
	await host.set_settings(lobby, rules)
	return lobby


func _beat(matches: Array, players: Dictionary, rounds: Dictionary) -> void:
	await (
		HttpJson
		. send(
			self,
			"POST",
			_backend.url + "/internal/servers/heartbeat",
			{"Authorization": "Bearer " + BackendFixture.GAME_SERVER_SECRET},
			{
				"id": "gs-tour",
				"url": "ws://127.0.0.1:1",
				"activityPath": "/gs",
				"capacity": 8,
				"matchIds": matches,
				"players": players,
				"rounds": rounds,
			}
		)
	)


# --- Helpers ---


## A phone's scale holds on every screen but the menu, which sets its own.
func _process(_delta: float) -> void:
	if _factor > 0.0 and UIRouter.top() != null and not UIRouter.top() is MainMenu:
		get_window().content_scale_factor = _factor


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _wait(0.12)


func _still(step: String) -> void:
	await _wait(SETTLE)
	await RenderingServer.frame_post_draw
	_shots += 1
	var path := "%s/%s-%d-%s.png" % [_out, _label, _shots, step]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, " window ", get_window().size, " top ", UIRouter.top().name)
