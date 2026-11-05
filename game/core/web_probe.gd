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

## Whether the page asked for the probes (see `asked`): -1 not yet read, 0 no, 1 yes.
static var _asked := -1

var _object: JavaScriptObject
var _since := 0.0
## The costs of the frames since the last publish, summed (`_add_costs`), averaged over `_frames`.
var _frames := 0
var _cost_sums := {}
## True when the page asked for a profile (`window.deadnight_bench`, `phone_frames.py`):
## only then are the per-frame costs read, so a player's page pays nothing for them.
var _bench := false
## What the page last was told, by key: only a value that differs crosses the bridge (a property
## write is a call into the page, and a string one allocates there), so a page nobody reads gets
## about no writes.
var _published := {}


## Whether the page asks for the probes that only a browser test reads (the judder, view and pad
## probes, which cross the JavaScript bridge in every frame): `?probe` in its address
## (`?probe=flash` too), `window.deadnight_probe` set before the game starts, or a profile run
## (`window.deadnight_bench`). A player's page asks for none of them and never pays for them (#935).
## Read once; false off the web.
static func asked() -> bool:
	if not OS.has_feature("web"):
		return false
	if _asked < 0:
		var script := (
			"(new URLSearchParams(location.search).has('probe') || !!window.deadnight_probe"
			+ " || window.deadnight_bench != null) ? 1 : 0"
		)
		_asked = 1 if int(JavaScriptBridge.eval(script, true)) == 1 else 0
	return _asked == 1


## The entries of `data` whose value differs from `last` (or that `last` lacks).
static func changed(last: Dictionary, data: Dictionary) -> Dictionary:
	var out := {}
	for key: String in data:
		if not last.has(key) or typeof(last[key]) != typeof(data[key]) or last[key] != data[key]:
			out[key] = data[key]
	return out


## Writes `label` into `window.deadnight_marks` with the page's clock, so a browser run can line the
## frames and the GL programs it recorded up with what the game was doing (the loading steps). Does
## nothing outside a browser.
static func mark(label: String) -> void:
	if not OS.has_feature("web"):
		return
	var push := "(window.deadnight_marks = window.deadnight_marks || []).push([%s, performance.now()])"
	JavaScriptBridge.eval(push % JSON.stringify(label))


func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	if not asked():
		# A player's page publishes nothing: no object, no snapshot of the screen (a walk of its
		# nodes four times a second), no probes (#983). A browser test asks with `?probe`.
		set_process(false)
		return
	_object = JavaScriptBridge.create_object("Object")
	JavaScriptBridge.get_interface("window").deadnight = _object
	_bench = JavaScriptBridge.get_interface("window").deadnight_bench != null
	if _bench:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	add_child(JudderProbe.new())
	add_child(FlashWebProbe.new())
	add_child(ViewWebProbe.new())
	add_child(PadWebProbe.new())


func _process(delta: float) -> void:
	if _bench:
		_add_costs()
	_since += delta
	if _since < PERIOD:
		return
	_since = 0.0
	var data := snapshot(UIRouter.top())
	var news := changed(_published, data)
	for key: String in news:
		_object[key] = news[key]
		_published[key] = news[key]
	if _bench:
		_publish_render_cost()
		_follow_bench_switch()


## What the frame costs the renderer and the scripts, for a phone-class profile (#689): draw calls,
## triangles and objects the last frame drew, and the time the engine spent in the script
## and physics callbacks, in milliseconds. A browser test reads them next to the frame times.
func _publish_render_cost() -> void:
	var rendering := RenderingServer
	_object["draw_calls"] = rendering.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	var view := get_viewport()
	_object["draw_calls_3d"] = int(
		view.get_render_info(
			Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME
		)
	)
	_object["primitives"] = rendering.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
	)
	_object["objects"] = rendering.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
	)
	_publish_memory()
	for key: String in _cost_sums:
		_object[key] = _cost_sums[key] / maxf(_frames, 1.0)
	_cost_sums = {}
	_frames = 0
	var window_size := DisplayServer.window_get_size()
	_object["canvas_w"] = window_size.x
	_object["canvas_h"] = window_size.y


## A profile run (`tools/web_smoke/phone_frames.py`) flips the 3D anti-aliasing while the page
## runs, to compare it in the same minutes: `window.deadnight_msaa` is 0 (off) or 2 (2x). With
## `?batch=toggle`, `window.deadnight_batch` (0 or 1) draws the map from its batches or from the
## nodes they replace.
func _follow_bench_switch() -> void:
	var window := JavaScriptBridge.get_interface("window")
	var asked: Variant = window.deadnight_msaa
	if asked == null:
		return
	var mode := Viewport.MSAA_DISABLED if int(asked) == 0 else Viewport.MSAA_2X
	if get_viewport().msaa_3d != mode:
		get_viewport().msaa_3d = mode
	var batch: Variant = window.deadnight_batch
	if batch != null:
		LotBatcher.switch(int(batch) != 0)


## What the engine holds, to tell a leak from the browser's garbage collector (#728): the engine's
## own heap (only in a debug export; 0 in a release one), the objects, nodes, orphan nodes and
## resources, and the video memory of textures and buffers, in megabytes. A page's `usedJSHeapSize`
## rises and falls with the collector and says nothing of these.
func _publish_memory() -> void:
	_object["mem_static_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	_object["mem_objects"] = Performance.get_monitor(Performance.OBJECT_COUNT)
	_object["mem_nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	_object["mem_orphans"] = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	_object["mem_resources"] = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	_object["mem_texture_mb"] = (
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	)
	_object["mem_buffer_mb"] = (
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0
	)


## Adds this frame's script, physics and render times (ms) to the sums the next publish averages.
func _add_costs() -> void:
	var rid := get_viewport().get_viewport_rid()
	_frames += 1
	var costs := {
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(rid),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(rid),
	}
	if PerfProbe.enabled:
		# What the labelled pieces of code took (`PerfProbe`, on with `?perf=1` in a bench).
		var usec: Dictionary = PerfProbe.take()["usec"]
		for label: StringName in usec:
			costs["perf." + String(label)] = float(usec[label]) / 1000.0
	for key: String in costs:
		_cost_sums[key] = float(_cost_sums.get(key, 0.0)) + float(costs[key])


## What the top screen shows: its scene name, and for a night the round, the zombies still to
## kill, the zombies alive on the lot, the players in the frame, the player's own id and (online)
## the round trip, whether the menu is open, the mouse mode, the camera's yaw (radians) and whether
## the player's body is drawn between physics ticks and whether the view is through the player's own
## camera (`view_is_players`). Plain values only, so a page can read them.
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
		# The account the run signed in to, and whether the credential of a visit before found it.
		"account_id": TogetherApi.account_id(),
		"account_returning": TogetherApi.returned_to_account(),
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
		"bots": 0,
		"notices": "",
		"code_text": "",
		"notice_log": "",
		"touch": false,
		"reticle": false,
		"weapon": "",
		"weapon_slots": "",
		"weapon_slot_held": 0,
		"settings_open": false,
		"menu_buttons": "",
		"menu_button_sizes": "",
		"tab": "",
		"stage": "",
		"quick_join": "",
		"gamepad": "",
		"signed_in": TogetherApi.signed_in(),
		"controller_hint": false,
		"clipboard": "",
		"clipboard_detail": "",
		"focus": "",
		"fields": "",
		"lift": 0.0
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
	data["fields"] = _field_spots(top)
	data["lift"] = UIRouter.offset.y
	data["gamepad"] = GamepadProbe.note(GamepadProbe.read())
	var clipboard := WebClipboard.read()  # what the page layer saw of copy and paste
	data["clipboard"] = WebClipboard.note(clipboard)
	data["clipboard_detail"] = WebClipboard.detail(clipboard)
	var tree := top.get_tree()
	var hint: ControllerHint = (
		tree.root.find_child("ControllerHint", true, false) as ControllerHint
		if tree != null
		else null
	)
	data["controller_hint"] = hint != null and hint.label.is_visible_in_tree()
	if top is MainMenu or top is PlayScreen or top is LobbyScreen or top is TogetherScreen:
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
		# The lobby: its code, the seats as `1 Ann HOST|2  Bo|...`, the standing line, the last
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
	# The helicopter drop of the arrival is on this screen (#1057).
	data["arriving"] = night_screen.night.is_arriving()
	data["hud_visible"] = night_screen.hud_shown()
	data["arrival_seconds"] = (
		night_screen.night.arrival_show.plan.seconds() if night_screen.night.is_arriving() else 0.0
	)
	if night_screen.night.server != null:
		# The rules the night runs under (solo's come from the Play screen's panel).
		var rules := night_screen.night.server.rules
		data["night_rules"] = MatchSettingsPanel.text_for(
			rules.settings, rules.settings.break_for(rules.tuning.rounds)
		)
		data["night_map"] = night_screen.night.world.map_info.id
	elif night_screen.night.world != null:
		# A night on a game server: the rules and the map its WELCOME carried (Deadnight #944).
		var held := night_screen.night.match_settings
		data["night_rules"] = MatchSettingsPanel.text_for(
			held, held.break_for(night_screen.night.rules_tuning.rounds)
		)
		data["night_map"] = night_screen.night.world.map_info.id
	# The menu is open, and what the engine says the mouse is (2 is captured: a browser's pointer
	# lock), so a browser test sees the first Esc open the menu.
	data["paused"] = night_screen.night.is_paused()
	data["mouse_mode"] = Input.mouse_mode
	var player: Player = night_screen.night.player() if night_screen.night.server != null else null
	if player != null:
		data["yaw"] = player.camera_rig.yaw  # so a browser test can see the mouse turn the view
		# So a browser test can see the view is the person's own soldier, not a bot's (#702).
		data["view_is_players"] = (
			player.get_viewport().get_camera_3d() == player.camera_rig.camera()
		)
		# So a browser test can see the body is drawn between ticks (a screen can switch that off).
		data["interpolated"] = player.is_physics_interpolated_and_enabled()
	data["over"] = state.over
	if night_screen.night.hud != null:
		# Bots in the night, as the roster labels them.
		var bots := 0
		for member: Dictionary in night_screen.night.hud.state.team.values():
			bots += 1 if member.get("bot", false) else 0
		data["bots"] = bots
		# Who joined or left, as the night's notices say it.
		data["notices"] = "|".join(night_screen.night.hud.notices.texts())
		data["notice_log"] = "|".join(night_screen.night.hud.notices.history)
		# The weapon slot strip: what is carried by slot, and which slot is in hand.
		var hud_state := night_screen.night.hud.state
		data["weapon"] = String(hud_state.weapon_id)
		data["weapon_slots"] = ",".join(PackedStringArray(hud_state.slot_ids))
		data["weapon_slot_held"] = hud_state.slot_held
	data["touch"] = night_screen.touch_active()
	data["reticle"] = night_screen.reticle_shown()
	data["settings_open"] = night_screen.settings_open()
	data["menu_buttons"] = _button_spots(night_screen)
	data["menu_button_sizes"] = _button_sizes(night_screen)
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


## The screen's shown, editable text fields as `name:x,y,w,h`: the centre and the size, as fractions
## of the window, so a browser test taps a field with a finger without knowing the layout.
static func _field_spots(screen: Control) -> String:
	if not screen.is_inside_tree():
		return ""
	var size := screen.get_viewport().get_visible_rect().size
	var spots: Array[String] = []
	for node in screen.find_children("*", "LineEdit", true, false):
		var field := node as LineEdit
		if not field.is_visible_in_tree() or not field.editable:
			continue
		# Where the field is drawn: the lift of the keyboard (`KeyboardLift`) moves the router's layer.
		var rect := Rect2(field.get_global_transform_with_canvas().origin, field.size)
		var at := rect.get_center() / size
		var fraction := rect.size / size
		spots.append("%s:%.4f,%.4f,%.4f,%.4f" % [field.name, at.x, at.y, fraction.x, fraction.y])
	return "|".join(spots)


## The night's shown buttons as `text:w,h`: the size as fractions of the window, so a browser test
## reads the size a finger meets in CSS pixels (#1192).
static func _button_sizes(screen: NightScreen) -> String:
	if not screen.is_inside_tree():
		return ""
	var size := screen.get_viewport().get_visible_rect().size
	var found: Array[String] = []
	for node in screen.find_children("*", "UIButton", true, false):
		var button := node as UIButton
		if button.is_visible_in_tree():
			var share := button.get_global_rect().size / size
			found.append("%s:%.5f,%.5f" % [button.text, share.x, share.y])
	return "|".join(found)


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
		var at := button.get_global_transform_with_canvas() * (button.size / 2.0) / size
		spots.append("%s:%.4f,%.4f" % [text, at.x, at.y])
	var play := screen as PlayScreen
	var lobby := screen as LobbyScreen
	var panel: MatchSettingsPanel = (
		play.panel if play != null else (lobby.rules if lobby != null else null)
	)
	if panel != null and panel.is_visible_in_tree():
		# Each setting's control: its centre, and `key:end` a little inside its right end (an option
		# selector's next arrow). The control is the one named by the key (`bots` and `bot_skill`
		# share a row, and each has its own selector), else the row's.
		for key: String in panel.setting_keys():
			var control := panel.find_child(key, true, false) as Control
			if control == null:
				control = panel.row_for(key).control
			var rect := control.get_global_rect()
			var middle := rect.get_center() / size
			var end := Vector2(rect.end.x - ARROW_INSET, rect.get_center().y) / size
			spots.append("%s:%.4f,%.4f" % [key, middle.x, middle.y])
			spots.append("%s:end:%.4f,%.4f" % [key, end.x, end.y])
		# Each map's card, to tap it: `map_<id>`.
		for card in panel.map_picker.cards:
			var middle := card.get_global_rect().get_center() / size
			spots.append("map_%s:%.4f,%.4f" % [card.info.id, middle.x, middle.y])
	return "|".join(spots)
