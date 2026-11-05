extends GdUnitTestSuite
## A lobby of eight seats, every one with a calling card, an emblem and a frame, still fits (#1161).
## A frame is drawn inside the seat's row, over its top and bottom edge (`LobbyScreen._show_plate`
## keeps its room clear at the two ends only: the level's icon, 24 units in a 45 unit row, is clear
## of the border's 7), so a framed seat is as tall as a plain one. This holds that: the panel
## stays inside the window, nothing is cut or put under another control (`UiFit`, the check of
## `test_ui_fit.gd`), and the numbers a player meets are the same as with no plates: the rows'
## height, the height of everything in the scrolling area, what is left to scroll (printed).
##
## The windows are the ones `test_ui_fit.gd` names that matter most here: a desktop at the usual
## interface size and at the largest (1.25: a 1536 x 864 canvas), and a phone held sideways at the
## menu's phone factor 2 (844 x 390: a 1169 x 540 canvas). Set `LOBBY_FIT_OUT` to a file to keep
## the numbers and `LOBBY_FIT_SHOTS` to a folder to keep a picture of each (windowed only;
## docs/research/level-badge-alignment.md).

const TEST_PATH := "user://lobby_framed_fit.cfg"
const SEATS := 8
## [window, interface size, pixel ratio]: the windows to read. The last is the phone as a web page
## has it (#1197): an 844 x 390 CSS pixel page at the ratio of 2 is a 1688 x 780 window, which gets
## the same 1169 x 540 canvas as the 844 x 390 window does.
const CASES: Array = [
	[Vector2i(1920, 1080), 1.0, 1.0],
	[Vector2i(1920, 1080), 1.25, 1.0],
	[Vector2i(844, 390), 1.0, 1.0],
	[Vector2i(1688, 780), 1.0, 2.0],
]

var _run: UiFitRun
var _saved_path: String
var _lines: Array[String] = []


func before_test() -> void:
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	await RouterFixture.clear(get_tree())
	_run = UiFitRun.new(get_tree())
	_run.begin()


func after_test() -> void:
	await _run.close()
	_run.restore()
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var out := OS.get_environment("LOBBY_FIT_OUT")
	if not out.is_empty() and not _lines.is_empty():
		var file := FileAccess.open(out, FileAccess.READ_WRITE)
		if file == null:
			file = FileAccess.open(out, FileAccess.WRITE)
		file.seek_end()
		file.store_string("\n".join(_lines) + "\n")
	_lines.clear()


## Eight members, the host first, each with the plate pieces of `framed` or none.
func _members(framed: bool) -> Array:
	var members: Array = []
	for i in SEATS:
		var member := LobbyFixture.member("u%d" % i, "Player %d" % (i + 1), i + 1, i == 0)
		member["level"] = [3, 7, 12, 55, 30, 41, 9, 23][i]
		member["icon"] = "level_%02d" % member["level"]
		if framed:
			member["card"] = "cartoon"
			member["emblem"] = "admit_one"
			member["frame"] = "gold"
		members.append(member)
	return members


## Keeps a picture of the window.
func _save(path: String) -> void:
	await _run.frames()
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(path)


## Opens the lobby as its host or a guest and returns the subject `UiFit` reads.
func _open(host: bool, framed: bool) -> Dictionary:
	var api := LobbyFixture.FakeApi.new(get_tree().root)
	api.me = "u0" if host else "u3"
	api.lobby = LobbyFixture.lobby(_members(framed))
	api.lobby["maxPlayers"] = SEATS
	await _run.close()
	_run._scale_window()
	UIRouter.reset(UiFitRun.LOBBY, UITransition.Kind.CUT, {"api": api, "lobby": api.lobby})
	await UIRouter.idle
	var lobby := UIRouter.top() as LobbyScreen
	lobby.watch.every = 3600.0
	await _run.frames()
	return _run.screen_subject(lobby, "lobby %s" % ("host" if host else "guest"))


## What a player meets, for one open lobby: [rows' total height, the scrolling area's content,
## the scrolling area's height, what is left to scroll, the panel's bottom edge], in canvas units.
func _numbers(lobby: LobbyScreen) -> Array[float]:
	var rows := 0.0
	for row: Dictionary in lobby.get("_seat_rows"):
		rows += (row["box"] as Control).size.y
	var scroll := lobby.get("_scroll") as ScrollContainer
	var content := (scroll.get_child(0) as Control).get_combined_minimum_size().y
	content += UIScroll.margins(scroll).y
	var panel := scroll.get_parent() as Control
	return [
		rows,
		content,
		scroll.size.y,
		maxf(content - scroll.size.y, 0.0),
		panel.global_position.y + panel.size.y
	]


## One window's reading of the lobby, as the host or a guest, with plates or without.
func _read(host: bool, framed: bool, window: Array) -> Dictionary:
	await _run.set_window(window[0], window[1], window[2])
	var subject := await _open(host, framed)
	var numbers := _numbers(subject["root"] as LobbyScreen)
	var canvas: Rect2 = subject["canvas"]
	var line := (
		(
			"lobby %s, %s seats, %dx%d x%.2f (canvas %dx%d): rows %.1f, content %.1f, scroll area %.1f,"
			+ " left to scroll %.1f, panel bottom %.1f of %.1f"
		)
		% [
			"host" if host else "guest",
			"framed" if framed else "plain",
			window[0].x,
			window[0].y,
			window[1],
			canvas.size.x,
			canvas.size.y,
			numbers[0],
			numbers[1],
			numbers[2],
			numbers[3],
			numbers[4],
			canvas.size.y
		]
	)
	print(line)
	_lines.append(line)
	var shots := OS.get_environment("LOBBY_FIT_SHOTS")
	if not shots.is_empty() and DisplayServer.get_name() != "headless":
		var stem := (
			"lobby_%s_%s_%dx%d_x%.2f"
			% [
				"host" if host else "guest",
				"framed" if framed else "plain",
				window[0].x,
				window[0].y,
				window[1]
			]
		)
		await _save(shots.path_join(stem + "_bottom.png"))
		# And scrolled to the seats.
		var lobby := subject["root"] as LobbyScreen
		var scroll := lobby.get("_scroll") as ScrollContainer
		var first := (lobby.get("_seat_rows") as Array)[0]["box"] as Control
		scroll.scroll_vertical = int(
			first.global_position.y - (scroll.get_child(0) as Control).global_position.y - 8.0
		)
		await _save(shots.path_join(stem + "_seats.png"))
	# The panel stays inside the window.
	(
		assert_float(numbers[4])
		. override_failure_message(line + ": the panel leaves the window")
		. is_less_equal(canvas.size.y)
	)
	return {"numbers": numbers, "problems": _run.problems(subject)}


## Eight framed seats fit as the lobby does with none: nothing cut or under another control, and
## no more height to scroll, whoever's view it is and whatever the window.
func _fits(host: bool) -> void:
	var problems: Array[String] = []
	for window: Array in CASES:
		var framed := await _read(host, true, window)
		var plain := await _read(host, false, window)
		problems.append_array(framed["problems"])
		(
			assert_array(framed["numbers"])
			. override_failure_message(
				"%s: a frame makes the lobby taller (rows, content, area, left, bottom)" % [window]
			)
			. is_equal(plain["numbers"])
		)
	(
		assert_array(problems)
		. override_failure_message("%d fit problems:\n%s" % [problems.size(), "\n".join(problems)])
		. is_empty()
	)


func test_a_host_lobby_of_eight_framed_seats_fits() -> void:
	await _fits(true)


func test_a_guest_lobby_of_eight_framed_seats_fits() -> void:
	await _fits(false)
