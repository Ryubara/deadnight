extends GdUnitTestSuite
## A button that grows when hovered stays whole: on every menu screen, at 720p, 1080p and the
## phone's canvas, each button hovered (and focused by the keyboard, with its ring) is measured
## against the nearest ancestor that clips it. The maintainer saw the lobby's "Copy the link"
## grow and lose its left edge under the panel's side (#628).

const TEST_PATH := "user://hover_room_test.cfg"
## Window pixels and the interface factor: 720p, 1080p, and a phone held sideways, whose factor
## doubles the units so that the canvas is 1168 x 540 of them.
const CANVASES := {
	"720p": [Vector2i(1280, 720), 1.0],
	"1080p": [Vector2i(1920, 1080), 1.0],
	"phone": [Vector2i(844, 390), 2.0],
}
## Longer than the entrance of any screen: its rows have risen and settled by then.
const SETTLE_SECONDS := 0.8
const SETTLE_TIME_SCALE := 10.0
const PLAY := "res://ui/screens/play_screen.tscn"
const TOGETHER := "res://ui/screens/together_screen.tscn"
const LOBBY := "res://ui/screens/lobby_screen.tscn"
const JOIN := "res://ui/screens/join_screen.tscn"
const SETTINGS := "res://ui/screens/settings_screen.tscn"
const CUSTOMIZE := "res://ui/screens/customize_screen.tscn"
const CREDITS := "res://ui/screens/credits_screen.tscn"

var _saved_path: String
var _saved_size: Vector2i
var _saved_factor: float
var _holder: CanvasLayer


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	UIInputMode.reset()
	_saved_size = get_window().size
	_saved_factor = get_window().content_scale_factor


func after_test() -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(_holder):
		_holder.free()
	await RouterFixture.clear(get_tree())
	get_window().size = _saved_size
	get_window().content_scale_factor = _saved_factor
	LobbyScreen.opener = Callable()
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _canvas(name: String) -> void:
	var canvas: Array = CANVASES[name]
	get_window().size = canvas[0]
	get_window().content_scale_factor = canvas[1]


func _settle() -> void:
	Engine.time_scale = SETTLE_TIME_SCALE
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	Engine.time_scale = 1.0
	for i in 2:
		await get_tree().process_frame


func _open(path: String, params := {}) -> Control:
	await RouterFixture.clear(get_tree())
	UIRouter.reset(path, UITransition.Kind.CUT, params)
	await UIRouter.idle
	await _settle()
	return UIRouter.top()


## Both looks of every button under `root`, as lines to report.
func _report(what: String, canvas: String, root: Node) -> Array[String]:
	var lines: Array[String] = []
	for ring in [false, true]:
		for line in HoverSweep.overflows(root, ring):
			lines.append("%s at %s: %s" % [what, canvas, line])
	return lines


func _expect_none(lines: Array[String], buttons_seen: int) -> void:
	assert_int(buttons_seen).is_greater(0)
	assert_array(lines).is_empty()


func _count(root: Node) -> int:
	return HoverSweep.buttons(root).size()


func _api(me: String) -> LobbyFixture.FakeApi:
	var api := LobbyFixture.FakeApi.new(self)
	api.me = me
	return api


func _members(count: int) -> Array:
	var names := ["Ann", "Bo", "Cy", "Di"]
	var out: Array = []
	for i in count:
		out.append(LobbyFixture.member("abcd"[i], names[i], i + 1, i == 0, i == 2))
	return out


## A button whose own guard is taken away, in a scroll area with no room: the measure sees it stick
## out, so that a test that reported nothing would not pass for the wrong reason.
class Unguarded:
	extends UIButton

	func _room_factor() -> Vector2:
		return Vector2.INF


func test_the_sweep_sees_a_button_that_sticks_out() -> void:
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(400.0, 200.0)
	add_child(scroll)
	var button := Unguarded.new()
	button.text = "Edge to edge"
	button.custom_minimum_size = Vector2(400.0, 60.0)
	scroll.add_child(button)
	await get_tree().process_frame
	await get_tree().process_frame
	var found := HoverSweep.overflows(scroll, false)
	scroll.free()
	assert_array(found).is_not_empty()


## A scroll area with room at its sides only (what the theme gave before #644) around a button
## that fills the area's height, or the theme's own: the measure reads the focus ring all round.
func _ring_found(sides_only: bool) -> Array[String]:
	var scroll := ScrollContainer.new()
	scroll.theme = UIThemeBuilder.build()
	if sides_only:
		var room := StyleBoxEmpty.new()
		room.content_margin_left = UITokens.active().hover_room
		room.content_margin_right = UITokens.active().hover_room
		scroll.add_theme_stylebox_override(&"panel", room)
	add_child(scroll)
	var button := UIButton.new()
	button.text = "Only row"
	scroll.add_child(button)
	scroll.size = Vector2(400.0, button.get_combined_minimum_size().y + UIScroll.margins(scroll).y)
	await get_tree().process_frame
	await get_tree().process_frame
	var found := HoverSweep.overflows(scroll, true)
	scroll.free()
	return found


func test_the_sweep_sees_a_ring_cut_above_and_below_the_only_row() -> void:
	var cut := await _ring_found(true)
	assert_array(cut).is_not_empty()
	assert_str(cut[0]).contains("focused")
	assert_array(await _ring_found(false)).is_empty()


func test_a_scroll_area_keeps_room_for_the_ring_above_and_below() -> void:
	var tokens := UITokens.active()
	var ring := float(tokens.focus_gap + tokens.focus_border)
	assert_float(float(tokens.scroll_room)).is_greater(ring)
	var scroll := ScrollContainer.new()
	scroll.theme = UIThemeBuilder.build()
	add_child(scroll)
	var margins := UIScroll.margins(scroll)
	scroll.free()
	assert_vector(margins).is_equal(Vector2(tokens.hover_room * 2.0, tokens.scroll_room * 2.0))


func test_the_last_row_of_the_lobby_keeps_its_ring_at_the_end() -> void:
	# The maintainer's capture: "Share in Discord", the last row of a lobby in an Activity, focused
	# with the keyboard, its ring cut off at the bottom by the scroll area.
	for canvas: String in CANVASES:
		_canvas(canvas)
		var api := _api("a")
		api.lobby = LobbyFixture.lobby(_members(2))
		var screen := (await _open(LOBBY, {"lobby": api.lobby, "api": api})) as LobbyScreen
		screen.watch.every = 3600.0
		screen.link_label.visible = true
		screen.copy_link_button.visible = true
		screen._shares.visible = true
		await _settle()
		var scroll := screen._scroll
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)
		var tokens := UITokens.active()
		var ring := float(tokens.focus_gap + tokens.focus_border)
		for button: UIButton in [screen.share_button]:
			button.preview_state = UIButton.Preview.FOCUS
			button.snap_to_targets()
			var rect := (
				scroll.get_global_transform().affine_inverse()
				* button.get_global_transform()
				* Rect2(Vector2.ZERO, button.size).grow(ring)
			)
			button.preview_state = UIButton.Preview.NONE
			button.snap_to_targets()
			(
				assert_float(rect.end.y)
				. override_failure_message(
					(
						"%s '%s' ring ends at %s of %s"
						% [canvas, button.text, rect.end.y, scroll.size.y]
					)
				)
				. is_less_equal(scroll.size.y + HoverSweep.TOLERANCE)
			)


## A list of buttons in a scroll area under the real theme, taller than the area, the first
## focused: the way a player starts.
func _list(rows: int) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.theme = UIThemeBuilder.build()
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(500.0, 260.0)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	for index in rows:
		var button := UIButton.new()
		button.text = "Row %d" % index
		box.add_child(button)
	await get_tree().process_frame
	await get_tree().process_frame
	return scroll


func test_the_focus_walks_a_list_with_its_whole_ring_from_the_first_row_to_the_last() -> void:
	# Down and Up through a list taller than its area: each row the area follows to is whole with
	# its ring, the first and the last too (the area stops at the row's edge, not the ring's).
	var scroll := await _list(8)
	var lines: Array[String] = await HoverSweep.walk(scroll)
	var rows := scroll.get_child(0).get_children()
	rows.reverse()
	for row: UIButton in rows:
		row.grab_focus()
		await get_tree().process_frame
		await get_tree().process_frame
	var first := scroll.get_child(0).get_child(0) as UIButton
	first.snap_to_targets()
	var tokens := UITokens.active()
	var top := (
		scroll.get_global_transform().affine_inverse()
		* first.get_global_transform()
		* Rect2(Vector2.ZERO, first.size).grow(float(tokens.focus_gap + tokens.focus_border))
	)
	scroll.free()
	assert_array(lines).is_empty()
	assert_float(top.position.y).is_greater_equal(-HoverSweep.TOLERANCE)


func test_the_keyboard_walk_shows_every_ring_whole_on_the_menu_screens() -> void:
	for canvas: String in CANVASES:
		_canvas(canvas)
		var lines: Array[String] = []
		var api := _api("a")
		api.lobby = LobbyFixture.lobby(_members(2))
		var lobby := (await _open(LOBBY, {"lobby": api.lobby, "api": api})) as LobbyScreen
		lobby.watch.every = 3600.0
		lobby.link_label.visible = true
		lobby.copy_link_button.visible = true
		lobby._shares.visible = true
		await _settle()
		var seen := _count(lobby)
		for line in await HoverSweep.walk(lobby):
			lines.append("lobby at %s: %s" % [canvas, line])
		for path: String in [PLAY, TOGETHER, JOIN, CUSTOMIZE, CREDITS]:
			var screen := await _open(path)
			seen += _count(screen)
			for line in await HoverSweep.walk(screen):
				lines.append("%s at %s: %s" % [path.get_file(), canvas, line])
		_expect_none(lines, seen)


## The hover of a button in a clipping control with `free` units around it, settled.
func _hovered_scale(free: Vector2) -> Vector2:
	var holder := Control.new()
	holder.clip_contents = true
	holder.size = Vector2(400.0, 200.0)
	add_child(holder)
	var button := UIButton.new()
	button.text = "Slot"
	holder.add_child(button)
	button.position = free
	button.size = holder.size - free * 2.0
	button.preview_state = UIButton.Preview.HOVER
	button.snap_to_targets()
	var factor := button.scale
	holder.free()
	return factor


func test_a_button_grows_by_the_room_it_has_and_never_more() -> void:
	var full := 1.0 + UITokens.active().hover_scale
	assert_vector(_hovered_scale(Vector2(30.0, 30.0))).is_equal_approx(
		Vector2(full, full), Vector2.ONE * 0.0001
	)
	# No room at the sides: it keeps its width. A little: it grows to touch the edge and no further.
	assert_vector(_hovered_scale(Vector2(0.0, 30.0))).is_equal_approx(
		Vector2(1.0, full), Vector2.ONE * 0.0001
	)
	var touch := 1.0 + 4.0 / 396.0
	assert_vector(_hovered_scale(Vector2(2.0, 30.0))).is_equal_approx(
		Vector2(touch, full), Vector2.ONE * 0.0001
	)
	# Each axis has its own room: the top and bottom as much as the sides.
	assert_vector(_hovered_scale(Vector2(30.0, 0.0))).is_equal_approx(
		Vector2(full, 1.0), Vector2.ONE * 0.0001
	)
	var near := 1.0 + 2.0 / 198.0
	assert_vector(_hovered_scale(Vector2(30.0, 1.0))).is_equal_approx(
		Vector2(full, near), Vector2.ONE * 0.0001
	)


func test_the_lobby_buttons_still_grow_by_the_full_hover() -> void:
	# The room the theme leaves in the scroll area lets the buttons keep their whole growth: the
	# guard of the button must not be what kept them whole.
	var full := 1.0 + UITokens.active().hover_scale
	for canvas: String in CANVASES:
		_canvas(canvas)
		var api := _api("a")
		api.lobby = LobbyFixture.lobby(_members(2))
		var screen := (await _open(LOBBY, {"lobby": api.lobby, "api": api})) as LobbyScreen
		screen.watch.every = 3600.0
		screen.link_label.visible = true
		screen.copy_link_button.visible = true
		screen._shares.visible = true
		await _settle()
		for button: UIButton in [
			screen.start_button,
			screen.leave_button,
			screen.copy_link_button,
			screen.copy_code_button,
			screen.share_button
		]:
			HoverSweep.scroll_to_middle(button)
			button.preview_state = UIButton.Preview.HOVER
			button.snap_to_targets()
			(
				assert_float(button.scale.x)
				. override_failure_message(
					"%s '%s' grows to %s" % [canvas, button.text, button.scale.x]
				)
				. is_equal_approx(full, 0.0001)
			)
			button.preview_state = UIButton.Preview.NONE
			button.snap_to_targets()


func test_the_lobby_buttons_stay_whole_when_hovered() -> void:
	for canvas: String in CANVASES:
		_canvas(canvas)
		var views := {
			"host with friends": ["a", {"lobby": LobbyFixture.lobby(_members(3))}],
			"guest waiting": ["b", {"lobby": LobbyFixture.lobby(_members(3))}],
			"preview": ["d", {"preview": LobbyFixture.preview("open", null, 2)}],
			# A page with an invite link, in a Discord Activity: every button the screen has.
			"link and share": ["a", {"lobby": LobbyFixture.lobby(_members(2))}],
		}
		for view: String in views:
			var api := _api(views[view][0])
			api.lobby = LobbyFixture.lobby(_members(3))
			var screen := (
				(await _open(LOBBY, (views[view][1] as Dictionary).merged({"api": api})))
				as LobbyScreen
			)
			screen.watch.every = 3600.0
			if view == "link and share":
				screen.link_label.text = "https://example.invalid/deadnight/index.html?room=K7QM4X"
				screen.link_label.visible = true
				screen.copy_link_button.visible = true
				screen._shares.visible = true
				await _settle()
			var seen := _count(screen)
			var lines := _report("lobby, %s" % view, canvas, screen)
			_expect_none(lines, seen)


func test_the_other_menu_screens_keep_their_buttons_whole_when_hovered() -> void:
	for canvas: String in CANVASES:
		_canvas(canvas)
		var lines: Array[String] = []
		var seen := 0
		for path: String in [PLAY, TOGETHER, JOIN, CUSTOMIZE, CREDITS]:
			var screen := await _open(path)
			seen += _count(screen)
			lines.append_array(_report(path.get_file(), canvas, screen))
		_expect_none(lines, seen)


func test_the_settings_tabs_keep_their_buttons_whole_when_hovered() -> void:
	for canvas: String in CANVASES:
		_canvas(canvas)
		var screen := (await _open(SETTINGS)) as SettingsScreen
		var lines: Array[String] = []
		var seen := 0
		for tab in screen._pages.size():
			screen.select_tab(tab, false)
			await _settle()
			seen += _count(screen)
			lines.append_array(_report("settings tab %d" % tab, canvas, screen))
		_expect_none(lines, seen)


func test_the_menu_tabs_keep_their_buttons_whole_when_hovered() -> void:
	for canvas: String in CANVASES:
		_canvas(canvas)
		var shell := await _open_shell()
		var lines: Array[String] = []
		var seen := 0
		for tab in MenuTab.ORDER:
			shell.show_tab(tab, false)
			await _settle()
			seen += _count(shell)
			lines.append_array(_report("menu tab %d" % tab, canvas, shell))
		assert_array(lines).is_empty()
		# The phone is where a button meets a strip (the desktop's tabs clip none): a run that saw
		# no button there measured nothing, as a headless shell once did.
		if canvas == "phone":
			assert_int(seen).is_greater(0)


func test_the_menu_shell_is_the_phones_in_a_phone_window_headless_or_not() -> void:
	for canvas: String in CANVASES:
		_canvas(canvas)
		var shell := await _open_shell()
		assert_bool(shell.is_compact()).is_equal(canvas == "phone")
		# The shell puts the phone factor on the window, which is what the canvas lists.
		assert_float(get_window().content_scale_factor).is_equal((CANVASES[canvas] as Array)[1])


## The menu's tab shell, told what a window of this size is. A headless shell takes every window
## for a desktop's (its own is 64 pixels), so the phone's layout was measured only in a window and
## CI never saw it (#1187): the shell is built here with the answer a window of this size gives
## (`MenuScale.is_phone`), as `UiFitRun` does, under the router's theme.
func _open_shell() -> MenuShell:
	await RouterFixture.clear(get_tree())
	if is_instance_valid(_holder):
		_holder.free()
	_holder = CanvasLayer.new()
	_holder.layer = 100
	get_tree().root.add_child(_holder)
	var stage := Control.new()
	stage.theme = UIThemeBuilder.build(UITokens.active())
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.add_child(stage)
	var shell := MenuShell.new()
	shell.manual_stage = true
	shell.phone_mode = 1 if MenuScale.is_phone(get_window().size) else 0
	shell.context.board = FakeChallengeBoard.new()
	shell.context.profile = MenuProfile.from_json(
		MenuProfile.to_json("Ann", MenuProfile.xp_at(7) + 90, 1250, {"rifle": 900})
	)
	stage.add_child(shell)
	await _settle()
	return shell
