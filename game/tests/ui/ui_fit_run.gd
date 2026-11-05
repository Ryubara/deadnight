class_name UiFitRun
extends RefCounted
## Opens every menu screen and tab at a window size and asks `UiFit` whether it fits. One driver
## for the test suite (`test_ui_fit.gd`) and the capture tour (`ui_fit_tour`), so the tour prints
## what the suite fails on (#980).
##
## A subject is `{name, root, area, zones, canvas}`: the node to look under, the rectangle its
## content belongs in (empty: none), the keep-out rectangles and the screen. Each `open_*` is a
## coroutine that leaves the subject laid out and idle.

const MENU := "res://ui/screens/main_menu.tscn"
const PLAY := "res://ui/screens/play_screen.tscn"
const TOGETHER := "res://ui/screens/together_screen.tscn"
const JOIN := "res://ui/screens/join_screen.tscn"
const LOBBY := "res://ui/screens/lobby_screen.tscn"
const SETTINGS := "res://ui/screens/settings_screen.tscn"
const CREDITS := "res://ui/screens/credits_screen.tscn"
const CARDS := "res://ui/screens/cards_screen.tscn"
const SETTINGS_TABS := [0, 1, 2, 3, 4]

## The windows a player has: a laptop, a desktop, a big desktop, the shortest window that is not
## a phone (500 px high: a 1920 x 1000 canvas), the web canvas of a Discord Activity, and phones
## held sideways: a common one (844 x 390, a 1169 x 540 canvas), a long one (932 x 430) and the
## narrowest (667 x 375, a 960 x 540 canvas). A phone held upright shows the rotate prompt.
const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(1000, 500),
	Vector2i(960, 540),
	Vector2i(844, 390),
	Vector2i(932, 430),
	Vector2i(667, 375),
]
## The canvases a phone's web page really has: [canvas, pixel ratio]. A page of 844 x 390 CSS pixels
## is a 1688 x 780 canvas at the ratio of 2 the game reports on a touch device (`PhoneRender`) and a
## 2532 x 1170 one at the phone's own 3. The window is the canvas; the page is the canvas over the
## ratio, and the menu must lay out as it does in a 844 x 390 window (#1197).
const PAGES: Array = [
	[Vector2i(1688, 780), 2.0],
	[Vector2i(2532, 1170), 3.0],
	[Vector2i(1864, 860), 2.0],
	[Vector2i(1334, 750), 2.0],
]
## Frames a screen is given to lay out after it is shown.
const SETTLE_FRAMES := 4

var tree: SceneTree
var board: FakeChallengeBoard
## Whether the menu is laid out for a phone: `MenuScale.is_phone` of the window.
var phone := false
## The player's interface size (Settings, Accessibility): 0.8, 1 or 1.25.
var ui_scale := 1.0
var _holder: CanvasLayer
var _asking: TogetherScreen
var _saved_size := Vector2i.ZERO
var _saved_scale := 1.0


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree


## Remembers the window, so `restore` puts it back.
func begin() -> void:
	var window := tree.root
	_saved_size = window.size
	_saved_scale = window.content_scale_factor
	UIMotion.reduced = true


func restore() -> void:
	var window := tree.root
	window.size = _saved_size
	window.content_scale_factor = _saved_scale
	PageSize.css_override = null
	UIMotion.reduced = false


## Sizes the window as a player's is, and applies the menu's phone factor when the short side
## calls for it. `page_ratio` over 1 makes it a touch device's web page: the window is the canvas
## and the page's size in CSS pixels the canvas over the ratio.
func set_window(size: Vector2i, interface_scale := 1.0, page_ratio := 1.0) -> void:
	var window := tree.root
	window.size = size
	if page_ratio > 1.0:
		TouchMode.device_is_touch = true
		PageSize.css_override = Vector2(size) / page_ratio
	else:
		PageSize.css_override = null
	phone = MenuScale.is_phone(size)
	ui_scale = interface_scale
	Settings.set_value(SettingsService.UI_SCALE, interface_scale)
	_scale_window()
	await tree.process_frame
	await tree.process_frame


## The menu's phone factor, which the shell leaves when it is freed but a screen over the menu
## keeps in the game (the menu stays below it).
func _scale_window() -> void:
	var window := tree.root
	window.content_scale_factor = MenuScale.factor(window.size, ui_scale)


func canvas() -> Rect2:
	return tree.root.get_visible_rect()


func ring() -> float:
	var tokens := UITokens.active()
	return float(tokens.focus_gap + tokens.focus_border)


func frames(count := SETTLE_FRAMES) -> void:
	for _i in count:
		await tree.process_frame


## The sentences of a subject that breaks a rule.
func problems(subject: Dictionary) -> Array[String]:
	var zones: Array[UiFit.Zone] = []
	zones.assign(subject["zones"])
	var found := UiFit.check(subject["root"], subject["canvas"], subject["area"], zones, ring())
	var lines: Array[String] = []
	for line in found:
		lines.append("%s: %s" % [subject["name"], line])
	return lines


## The sentences for the text under 14 CSS pixels and the targets under 44 that a person with a
## ruler finds on the subject's screen (`UiAudit`, #1197). A tab's subject is read with its header
## and footer: the whole shell.
func floor_problems(subject: Dictionary) -> Array[String]:
	var root: Node = subject.get("shell", subject["root"])
	var audit := UiAudit.scan(root, PageSize.css_per_pixel(tree.root.size))
	var lines: Array[String] = []
	if not audit.text_small.is_empty():
		lines.append(
			"%s: text under %d px: %s" % [subject["name"], UiAudit.MIN_TEXT_PX, audit.text_small]
		)
	if not audit.tap_small.is_empty():
		lines.append(
			"%s: target under %d px: %s" % [subject["name"], UiAudit.MIN_TAP_PX, audit.tap_small]
		)
	return lines


# ------------------------------------------------------------------------------ the menu's tabs


## The tab shell on a tab, with the board's rows as long as a goal can make them when `extreme`.
## Returns the subject of the tab's panel.
func open_tab(tab: MenuTab.Id, extreme := false) -> Dictionary:
	await close()
	board = FakeChallengeBoard.new()
	board.extreme = extreme
	var shell := MenuShell.new()
	shell.manual_stage = true
	shell.phone_mode = 1 if phone else 0
	shell.context.board = board
	# The plate with the longest name the game allows and the biggest numbers, in the long-rows case.
	shell.context.profile = MenuProfile.from_json(
		MenuProfile.to_json(
			"WWWWWWWWWWWWWWWW" if extreme else "Ann",
			MenuProfile.xp_at(60 if extreme else 7) + 90,
			99999999 if extreme else 1250,
			{"rifle": 900}
		)
	)
	# The router's stage gives the menu its theme (the scroll areas' room, the bars): so does this.
	var layer := CanvasLayer.new()
	layer.layer = 100
	tree.root.add_child(layer)
	_holder = layer
	var stage := Control.new()
	stage.theme = UIThemeBuilder.build(UITokens.active())
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(stage)
	stage.add_child(shell)
	await frames(2)
	shell.show_tab(tab, false)
	await frames()
	return shell_subject(shell, tab, extreme)


## What the shell keeps clear of the panel: the header (tab bar and plate), the footer (the key
## hints), the screen's edge. The panel's own rectangle is the area its content belongs in.
func shell_subject(shell: MenuShell, tab: MenuTab.Id, extreme := false) -> Dictionary:
	var panel := shell.panel(tab)
	var screen := canvas()
	var compact := shell.is_compact()
	var top := MenuShell.TOP_COMPACT if compact else MenuShell.TOP
	var bottom := MenuShell.BOTTOM_COMPACT if compact else MenuShell.BOTTOM
	var zones: Array[UiFit.Zone] = [
		UiFit.Zone.make(
			"header", Rect2(0.0, 0.0, screen.size.x, top), [shell.tab_bar, shell.plate]
		),
		UiFit.Zone.make(
			"footer", Rect2(0.0, screen.size.y - bottom, screen.size.x, bottom), [shell.hints]
		),
	]
	return {
		"name":
		"menu/%s%s %s" % [MenuTab.label(tab), " (long rows)" if extreme else "", _tag(screen)],
		"root": panel,
		"area": panel.get_global_rect(),
		"zones": zones,
		"canvas": screen,
		"shell": shell,
	}


## Whether the chrome stays in its bands: the tab bar and plate above the panel, the hints below.
func chrome_problems(subject: Dictionary) -> Array[String]:
	var shell: MenuShell = subject["shell"]
	var area: Rect2 = subject["area"]
	var screen: Rect2 = subject["canvas"]
	var found: Array[String] = []
	for part: Control in [shell.tab_bar, shell.plate]:
		var rect := part.get_global_rect()
		if rect.end.y > area.position.y + UiFit.TOLERANCE or not screen.grow(1.0).encloses(rect):
			found.append(
				(
					"%s: %s %s is not in the header (the panel starts at %d)"
					% [subject["name"], part.name, rect, roundi(area.position.y)]
				)
			)
	if shell.tab_bar.get_global_rect().intersects(shell.plate.get_global_rect()):
		found.append(
			(
				"%s: the tab bar %s and the name plate %s overlap"
				% [subject["name"], shell.tab_bar.get_global_rect(), shell.plate.get_global_rect()]
			)
		)
	if shell.hints.visible:
		var hint_rect := shell.hints.get_global_rect()
		if (
			hint_rect.position.y < area.end.y - UiFit.TOLERANCE
			or not screen.grow(1.0).encloses(hint_rect)
		):
			found.append(
				(
					"%s: the key hints %s are not in the footer (the panel ends at %d)"
					% [subject["name"], hint_rect, roundi(area.end.y)]
				)
			)
	return found


# ----------------------------------------------------------------------------- the other screens


## The screens other than the menu's tabs, by the name `open` takes.
static func screen_names() -> Array[String]:
	# The wardrobe on its own (`customize_screen.tscn`) is not routed to by anything: the Loadout tab
	# hosts it embedded, which the tab sweep covers.
	var names: Array[String] = [
		"play",
		"together",
		"together name",
		"join",
		"lobby host",
		"lobby guest",
		"lobby code",
		"credits",
		"cards",
		"quick join failed",
		"quick join found",
	]
	for tab in SETTINGS_TABS:
		names.append("settings %d" % tab)
	return names


## Opens one of `screen_names` and returns its subject.
func open(screen_name: String) -> Dictionary:
	var plain := {
		"play": PLAY, "together": TOGETHER, "join": JOIN, "credits": CREDITS, "cards": CARDS
	}
	var subject: Dictionary
	if plain.has(screen_name):
		subject = await open_screen(plain[screen_name], screen_name)
	elif screen_name.begins_with("lobby"):
		subject = await _open_lobby(
			screen_name, screen_name == "lobby host", screen_name == "lobby code"
		)
	elif screen_name.begins_with("quick join"):
		subject = await _open_quick_join(screen_name, screen_name == "quick join failed")
	elif screen_name == "together name":
		subject = await open_screen(TOGETHER, screen_name)
		_asking = subject["root"] as TogetherScreen
		_asking._ask_name()
		await frames()
	else:
		subject = await open_screen(SETTINGS, screen_name)
		(subject["root"] as SettingsScreen).select_tab(int(screen_name.get_slice(" ", 1)), false)
		await frames()
	return subject


## The Quick join card in its two tall states: a failure with the longest words the backend has
## (and Create a night and Close), and the night's map found while the search goes on.
func _open_quick_join(label: String, failed: bool) -> Dictionary:
	await close()
	_scale_window()
	var layer := CanvasLayer.new()
	layer.layer = 100
	tree.root.add_child(layer)
	_holder = layer
	var stage := Control.new()
	stage.theme = UIThemeBuilder.build(UITokens.active())
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(stage)
	var overlay := QuickJoinOverlay.new()
	stage.add_child(overlay)
	if failed:
		overlay.state = QuickJoinOverlay.State.FAILED
		overlay.status.text = TogetherApi.TEXTS["not_member"]
	else:
		overlay.state = QuickJoinOverlay.State.SEARCHING
		overlay.map_card.info = MapRegistry.default_map()
		overlay.map_card.visible = true
	overlay._show_buttons()
	await frames()
	return screen_subject(overlay, label)


func _open_lobby(label: String, host: bool, code_only: bool) -> Dictionary:
	var api := LobbyFixture.FakeApi.new(tree.root)
	api.me = "a" if host else "d"
	var members := [
		LobbyFixture.member("a", "Ann the Projectionist", 1, true),
		LobbyFixture.member("b", "Bo", 2),
		LobbyFixture.member("c", "Cy", 3),
		LobbyFixture.member("d", "Di", 4),
	]
	api.lobby = LobbyFixture.lobby(members)
	var params := {"api": api, "lobby": api.lobby}
	if code_only:
		api.preview_answer = LobbyFixture.preview("open", null, 4)
		params = {"api": api, "preview": api.preview_answer}
	await close()
	_scale_window()
	UIRouter.reset(LOBBY, UITransition.Kind.CUT, params)
	await UIRouter.idle
	var lobby := UIRouter.top() as LobbyScreen
	lobby.watch.every = 3600.0
	await frames()
	return screen_subject(lobby, label)


## A screen alone on the router, over nothing, and the subject for it: the whole canvas is its
## area. `params` go to the screen.
func open_screen(path: String, label: String, params := {}) -> Dictionary:
	await close()
	_scale_window()
	UIRouter.reset(path, UITransition.Kind.CUT, params)
	await UIRouter.idle
	await frames()
	return screen_subject(UIRouter.top(), label)


func screen_subject(screen: Control, label: String) -> Dictionary:
	var screen_rect := canvas()
	return {
		"name": "%s %s" % [label, _tag(screen_rect)],
		"root": screen,
		"area": Rect2(),
		"zones": [] as Array[UiFit.Zone],
		"canvas": screen_rect,
	}


## Closes whatever a subject opened.
func close() -> void:
	# The name prompt waits for an answer; an answer lets it finish, so nothing waits for ever.
	if is_instance_valid(_asking):
		_asking.name_decided.emit()
	_asking = null
	if is_instance_valid(_holder):
		_holder.free()
	_holder = null
	await RouterFixture.clear(tree)


func _tag(screen: Rect2) -> String:
	return (
		"%dx%d%s@%dx%d"
		% [
			tree.root.size.x,
			tree.root.size.y,
			"" if is_equal_approx(ui_scale, 1.0) else "x%s" % ui_scale,
			roundi(screen.size.x),
			roundi(screen.size.y)
		]
	)
