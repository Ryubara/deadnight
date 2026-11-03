class_name WebProbe
extends Node
## On the web, publishes what the game is doing as `window.deadnight`, so a browser test (the CI
## smoke run, `tools/web_smoke/`) can wait for the main menu and a running night instead of
## guessing from pixels. Does nothing elsewhere. It only reads; no game code depends on it.

## How often the object is refreshed, in seconds (a JS property write per field is not free).
const PERIOD := 0.25
## How far inside the right end of a setting's control a tap lands on an option selector's next
## arrow, in units.
const ARROW_INSET := 24.0

var _object: JavaScriptObject
var _since := 0.0


## Writes `label` into `window.deadnight_marks` with the page's clock, so a browser run can line the
## frames and the GL programs it recorded up with what the game was doing (the loading steps).
## Does nothing outside a browser.
static func mark(label: String) -> void:
	if not OS.has_feature("web"):
		return
	var push := "(window.deadnight_marks = window.deadnight_marks || []).push([%s, performance.now()])"
	JavaScriptBridge.eval(push % JSON.stringify(label))


func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	_object = JavaScriptBridge.create_object("Object")
	JavaScriptBridge.get_interface("window").deadnight = _object
	add_child(JudderProbe.new())
	add_child(FlashWebProbe.new())
	add_child(ViewWebProbe.new())
	add_child(PadWebProbe.new())


func _process(delta: float) -> void:
	_since += delta
	if _since < PERIOD:
		return
	_since = 0.0
	var data := snapshot(UIRouter.top())
	for key in data:
		_object[key] = data[key]


## What the top screen shows: its scene name, and for a night the round, the zombies still to
## kill, the zombies alive on the lot, the players in the frame, the player's own id and (online)
## the round trip, whether the menu is open, the mouse mode, the camera's yaw (radians) and whether
## the player's body is drawn between physics ticks. Plain values only, so a page can read them.
static func snapshot(top: Control) -> Dictionary:
	var data := {
		"screen": "none",
		"night": false,
		"running": false,
		"paused": false,
		"mouse_mode": 0,
		"over": false,
		"round": 0,
		"remaining": 0,
		"alive": 0,
		"players": 0,
		"player_id": 0,
		"rtt_ms": -1.0,
		"body_x": 0.0,
		"body_z": 0.0,
		"server_x": 0.0,
		"server_z": 0.0,
		"stalls": 0,
		"stall_longest_ms": 0.0,
		"yaw": 0.0,
		"interpolated": false,
		"room_code": "",
		"room_status": "",
		"naming": false,
		"lobby_seats": "",
		"lobby_note": "",
		"share_says": "",
		"share_line": "",
		"lobby_buttons": "",
		"lobby_rules": "",
		"lobby_rules_editable": false,
		"play_rules": "",
		"play_map": "",
		"lobby_map": "",
		"spots": "",
		"night_rules": "",
		"night_map": "",
		"notices": "",
		"code_text": "",
		"notice_log": "",
		"touch": false,
		"reticle": false,
		"settings_open": false,
		"menu_buttons": "",
		"tab": "",
		"stage": "",
		"quick_join": "",
		"gamepad": "",
		"activity_room": "",
		"activity_code": "",
		"controller_hint": false,
		"clipboard": "",
		"clipboard_detail": "",
		"focus": ""
	}
	if top == null:
		return data
	data["screen"] = top.scene_file_path.get_file().get_basename()
	if top.is_inside_tree():
		# The control that has the keyboard, so a browser test walks to a button by its name (a
		# button's inner control has no name of its own: the nearest ancestor that has one).
		var focus: Node = top.get_viewport().gui_get_focus_owner()
		while focus != null and String(focus.name).begins_with("@"):
			focus = focus.get_parent()
		data["focus"] = String(focus.name) if focus != null else ""
	data["gamepad"] = GamepadProbe.note(GamepadProbe.read())
	var clipboard := WebClipboard.read()  # what the page layer saw of copy and paste
	data["clipboard"] = WebClipboard.note(clipboard)
	data["clipboard_detail"] = WebClipboard.detail(clipboard)
	var room := ActivityRoom.current
	if room != null:
		data["activity_room"] = ActivityRoom.State.keys()[room.state].to_lower()
		data["activity_code"] = str(room.preview.get("code", ""))
	var tree := top.get_tree()
	var hint: ControllerHint = (
		tree.root.find_child("ControllerHint", true, false) as ControllerHint
		if tree != null
		else null
	)
	data["controller_hint"] = hint != null and hint.label.is_visible_in_tree()
	if top is MainMenu or top is PlayScreen:
		# Where a finger taps each start and button, as fractions of the window.
		data["spots"] = _spots(top)
	var menu := top as MainMenu
	if menu != null and menu.shell != null:
		data["tab"] = MenuTab.label(menu.shell.tab)
		data["stage"] = ["live", "half", "still"][menu.shell.view.level]
		# Quick join's card over the menu: what it says while it searches or after it failed.
		var card := menu.find_child("QuickJoin", false, false) as QuickJoinOverlay
		data["quick_join"] = card.text() if card != null and card.visible else ""
	var together := top as TogetherScreen
	if together != null:
		# What the screen says (a browser test reads it); the code is the lobby screen's.
		data["room_status"] = together.status.text
		# The name prompt is up (a browser test types a name into it).
		data["naming"] = together.name_field.is_visible_in_tree()
		data["code_text"] = together.code_field.text  # what a paste put into the code field
	var lobby := top as LobbyScreen
	if lobby != null:
		# The lobby: its code, the seats as `1  Ann  HOST|2  Bo|...`, the standing line, the last
		# thing that happened and which buttons are up (`Start`, `Play`, `Join`).
		data["room_code"] = lobby.code_label.text
		data["room_status"] = lobby.status.text
		data["lobby_seats"] = "|".join(lobby.seat_texts())
		data["lobby_note"] = lobby.note.text
		data["share_says"] = lobby.share_says.text
		data["share_line"] = lobby.share_probe.text
		var buttons: Array[String] = []
		for button: UIButton in [lobby.start_button, lobby.play_button, lobby.join_button]:
			if button.is_visible_in_tree():
				buttons.append(button.name)
		data["lobby_buttons"] = "|".join(buttons)
		data["lobby_rules"] = lobby.rules_text() if lobby.rules.is_visible_in_tree() else ""
		data["lobby_rules_editable"] = lobby.rules_editable()
		# The map the lobby shows: the picker's choice in a lobby, the ticket of a code looked at.
		data["lobby_map"] = (
			lobby.rules.map_picker.selected_id
			if lobby.rules.is_visible_in_tree()
			else (lobby.map_card.info.id if lobby.map_card.visible and lobby.map_card.info else "")
		)
	var play := top as PlayScreen
	if play != null:
		# Solo's Play screen: the rules on its panel (the same panel the room host's lobby has).
		data["play_rules"] = play.rules_text()
		data["play_map"] = play.panel.map_picker.selected_id
	var night_screen := top as NightScreen
	if night_screen == null or night_screen.night == null or night_screen.night.state == null:
		return data
	var state := night_screen.night.state
	data["night"] = true
	data["running"] = night_screen.night.running
	if night_screen.night.server != null:
		# The rules the night runs under (solo's come from the Play screen's panel).
		var rules := night_screen.night.server.rules
		data["night_rules"] = MatchSettingsPanel.text_for(
			rules.settings, rules.settings.break_for(rules.tuning.rounds)
		)
		data["night_map"] = night_screen.night.world.map_info.id
	# The menu is open, and what the engine says the mouse is (2 is captured: a browser's pointer
	# lock), so a browser test sees the first Esc open the menu.
	data["paused"] = night_screen.night.is_paused()
	data["mouse_mode"] = Input.mouse_mode
	var player: Player = night_screen.night.player() if night_screen.night.server != null else null
	if player != null:
		data["yaw"] = player.camera_rig.yaw  # so a browser test can see the mouse turn the view
		# So a browser test can see the body is drawn between ticks (a screen can switch that off).
		data["interpolated"] = player.is_physics_interpolated_and_enabled()
	data["over"] = state.over
	if night_screen.night.hud != null:
		# Who joined or left, as the night's notices say it.
		data["notices"] = "|".join(night_screen.night.hud.notices.texts())
		data["notice_log"] = "|".join(night_screen.night.hud.notices.history)
	data["touch"] = night_screen.touch_active()
	data["reticle"] = night_screen.reticle_shown()
	data["settings_open"] = night_screen.settings_open()
	data["menu_buttons"] = _button_spots(night_screen)
	if state.has_frame():
		data["round"] = state.round_number()
		data["remaining"] = state.frame.get("remaining", 0)
		data["alive"] = state.zombies.size()
		data["players"] = (state.frame.get("players", {}) as Dictionary).size()
	data["player_id"] = state.player_id
	var link := night_screen.night.link as WebSocketLink
	if link != null:
		data["rtt_ms"] = link.rtt_ms
	if night_screen.night.remote:
		# Online: where this client's own body is and where the server has the player, and the
		# freezes of the page the client noticed, so a browser test can stall the page and see the
		# body come back (`tools/web_smoke/freeze.py`).
		var body := night_screen.night.player()
		if body != null:
			data["body_x"] = body.state.position.x
			data["body_z"] = body.state.position.z
		if state.has_frame() and not state.me().is_empty():
			data["server_x"] = state.position().x
			data["server_z"] = state.position().z
		data["stalls"] = night_screen.night.stalls.stalls
		data["stall_longest_ms"] = night_screen.night.stalls.longest_ms
	return data


## Where the night's menu buttons are, as `Text:x,y` with x and y a fraction of the window (0 to 1),
## so a browser test taps them without knowing the layout.
static func _button_spots(screen: NightScreen) -> String:
	return _spots(screen)


## The screen's shown buttons as `text:x,y` (the centre, as fractions of the window): the
## `UIButton`s and the menu's `MenuItemButton`s (by their title).
static func _spots(screen: Control) -> String:
	if not screen.is_inside_tree():
		return ""
	var size := screen.get_viewport().get_visible_rect().size
	var spots: Array[String] = []
	for node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if not button.is_visible_in_tree():
			continue
		var text := button.text
		if button is MenuItemButton:
			text = (button as MenuItemButton).title
		elif not button is UIButton:
			continue
		var at := button.get_global_rect().get_center() / size
		spots.append("%s:%.4f,%.4f" % [text, at.x, at.y])
	var play := screen as PlayScreen
	if play != null:
		# Each setting's control: its centre, and `key:end` a little inside its right end (an option
		# selector's next arrow).
		for key: String in play.panel.setting_keys():
			var rect := play.panel.row_for(key).control.get_global_rect()
			var middle := rect.get_center() / size
			var end := Vector2(rect.end.x - ARROW_INSET, rect.get_center().y) / size
			spots.append("%s:%.4f,%.4f" % [key, middle.x, middle.y])
			spots.append("%s:end:%.4f,%.4f" % [key, end.x, end.y])
		# Each map's card, to tap it: `map_<id>`.
		for card in play.panel.map_picker.cards:
			var middle := card.get_global_rect().get_center() / size
			spots.append("map_%s:%.4f,%.4f" % [card.info.id, middle.x, middle.y])
	return "|".join(spots)
