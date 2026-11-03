extends Node
## A button focused with the keyboard in the first or the last row of a scroll area, to see whether
## the focus ring is whole (#644). One shot per run, named by `--shot=`:
## `lobby_last` (the lobby's "Share in Discord" at the end of its area, the maintainer's capture),
## `list_first` and `list_last` (a plain list of buttons in a panel, at its top and at its end).
## `--phone` puts the interface at the factor a phone gets (844 x 390 window = 1168 x 540 units).
## Windowed, through the no-focus launcher, writes `<out>/<tag>_<shot>.png` (the window) and
## `<out>/<tag>_<shot>_close.png` (the row, 2x):
## `gds godot -- --path game res://tests/captures/scroll_ring_tour.tscn --windowed --resolution
## 1280x720 -- --shot=lobby_last --out=<folder> --tag=after`.
## On the web (this scene exported as the main scene) the page's query gives the same options
## (`?shot=lobby_last&phone=1`) and the scene publishes the row's place as `window.ringRect`
## (canvas pixels) for a browser to take the picture; see `docs/research/menu-shell.md`.

const LOBBY := "res://ui/screens/lobby_screen.tscn"
const SETTLE := 1.5
## Pixels around the row kept in a close-up.
const CLOSE_UP := 48
const PHONE_FACTOR := 2.0
const LIST_ROWS := 6
const LIST_HEIGHT := 260.0
const LIST_WIDTH := 460.0
const MAX_KEY_PRESSES := 40


## A backend that answers `refresh` with the lobby the tour holds.
class StandIn:
	extends TogetherApi

	func my_id() -> String:
		return "a"

	func refresh(held: Dictionary) -> Dictionary:
		return {"ok": true, "lobby": held}

	func leave(_held: Dictionary) -> Dictionary:
		return {"ok": true}

	func detached(_parent: Node) -> TogetherApi:
		return self


func _ready() -> void:
	var options := _options()
	if options.has("phone"):
		get_window().content_scale_factor = PHONE_FACTOR
	# The last input was a key: the ring shows (a mouse hides it).
	UIInputMode.pointer = false
	var row: UIButton
	var scroll: ScrollContainer
	match options.get("shot", "lobby_last"):
		"lobby_last":
			var screen := await _lobby()
			scroll = screen._scroll
			row = screen.share_button
		"list_first":
			scroll = await _list()
			row = scroll.get_child(0).get_child(0) as UIButton
		_:
			scroll = await _list()
			row = scroll.get_child(0).get_child(LIST_ROWS - 1) as UIButton
	await get_tree().create_timer(SETTLE).timeout
	# The way a player gets there: the focus starts on the first row and the Down key walks it to
	# the last (and the Up key back to the first): the scroll area follows the focus.
	var buttons := scroll.find_children("*", "Button", true, false).filter(
		func(node: Node) -> bool: return (node as Control).is_visible_in_tree()
	)
	(buttons[0] as Control).grab_focus()
	await get_tree().create_timer(0.3).timeout
	var last := buttons[buttons.size() - 1] as Control
	for step in MAX_KEY_PRESSES:
		if last.has_focus():
			break
		await _press(&"ui_down")
	for step in MAX_KEY_PRESSES:
		if row.has_focus():
			break
		await _press(&"ui_up")
	await get_tree().create_timer(SETTLE).timeout
	if OS.has_feature("web"):
		var centre := get_viewport().get_final_transform() * row.get_global_rect().get_center()
		JavaScriptBridge.eval(
			"window.ringRect = %s" % JSON.stringify({"x": centre.x, "y": centre.y})
		)
		return
	await _save(row, str(options.get("out", "user://scroll_ring")), options)
	get_tree().quit()


## One key press of a UI action, with a frame to move the focus and the scroll.
func _press(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout


func _options() -> Dictionary:
	var found := {}
	var args := Array(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("window.location.search")).trim_prefix("?")
		args = Array(query.split("&"))
		args = args.map(func(item: String) -> String: return "--" + item)
	for arg: String in args:
		var pair := arg.trim_prefix("--").split("=", true, 1)
		found[pair[0]] = pair[1] if pair.size() > 1 else true
	return found


func _lobby() -> LobbyScreen:
	var api := StandIn.new(self)
	var members := [
		{"userId": "a", "name": "Ann", "seat": 1, "host": true, "away": false},
		{"userId": "b", "name": "Bo", "seat": 2, "host": false, "away": false},
	]
	var lobby := {
		"id": "l1",
		"code": "K7QM4X",
		"hostId": "a",
		"maxPlayers": 4,
		"members": members,
		"state": "open",
		"round": null,
		"players": null,
	}
	UIRouter.reset(LOBBY, UITransition.Kind.CUT, {"lobby": lobby, "api": api})
	await UIRouter.idle
	var screen := UIRouter.top() as LobbyScreen
	screen.watch.every = 3600.0
	# What the page shows inside a Discord Activity: the invite link and the share button.
	screen.link_label.text = "https://deadnight.example/index.html?room=K7QM4X"
	screen.link_label.visible = true
	screen.copy_link_button.visible = true
	screen._shares.visible = true
	return screen


## A list of buttons in a panel, in a plain scroll area like the screens use.
func _list() -> ScrollContainer:
	var tokens := UITokens.active()
	var holder := UIScreen.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(centre)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	centre.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, LIST_HEIGHT)
	panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"separation", tokens.space_sm)
	scroll.add_child(rows)
	for index in LIST_ROWS:
		var button := UIButton.new()
		button.text = "Row %d" % (index + 1)
		button.variant = UIButton.Variant.SECONDARY
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(button)
	return scroll


func _save(row: UIButton, out: String, options: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var label := "%s_%s" % [options.get("tag", "shot"), options.get("shot", "lobby_last")]
	image.save_png("%s/%s.png" % [out, label])
	var rect := (
		get_viewport().get_final_transform()
		* (row.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, row.size))
	)
	var close := Rect2i(rect.grow(CLOSE_UP)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var crop := image.get_region(close)
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s_close.png" % [out, label])
	print("saved ", label, " focus ", row.has_focus(), " window ", get_window().size)
