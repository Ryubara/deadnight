extends Node
## The lobby with every button it can show, and a real mouse hovering one at a time: a PNG of the
## window each, and a close-up of the button, into `--out=<folder>` (#628). The backend is a
## stand-in.
## On the web (this scene exported as the main scene) it publishes where each button is as
## `window.hoverRects` (canvas pixels) and a browser moves the real mouse there; see
## `docs/research/menu-shell.md`. Run through the no-focus launcher, not headless:
## `gds godot -- --path game res://tests/captures/lobby_hover_tour.tscn --windowed --resolution
## 1280x720 -- --out=<folder>`.

const SCREEN := "res://ui/screens/lobby_screen.tscn"
const SETTLE := 1.2
const NAMES: Array[String] = [
	"copy_link_button", "copy_code_button", "start_button", "leave_button"
]
## Pixels around the button kept in a close-up.
const CLOSE_UP := 48


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
	var out := "user://lobby_hover"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
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
	UIRouter.reset(SCREEN, UITransition.Kind.CUT, {"lobby": lobby, "api": api})
	await UIRouter.idle
	var screen := UIRouter.top() as LobbyScreen
	screen.watch.every = 3600.0
	# What the page shows inside a Discord Activity: the invite link and the share button.
	screen.link_label.text = "https://deadnight.example/index.html?room=K7QM4X"
	screen.link_label.visible = true
	screen.copy_link_button.visible = true
	screen._shares.visible = true
	await get_tree().create_timer(SETTLE).timeout
	# Scrolled so that the copy buttons are in the middle of the area.
	var scroll := screen._scroll
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await get_tree().create_timer(0.3).timeout
	if OS.has_feature("web"):
		_publish(screen)
		return
	for node_name in NAMES:
		var button: UIButton = screen.get(node_name)
		await _hover(button, out, node_name)
	get_tree().quit()


## Where each button's centre is in canvas pixels, for a browser to put the mouse on.
func _publish(screen: LobbyScreen) -> void:
	var rects := {}
	for node_name in NAMES:
		var button: UIButton = screen.get(node_name)
		var centre := get_viewport().get_final_transform() * (button.get_global_rect().get_center())
		rects[node_name] = {"x": centre.x, "y": centre.y}
	JavaScriptBridge.eval("window.hoverRects = %s" % JSON.stringify(rects))


func _hover(button: UIButton, out: String, label: String) -> void:
	var at := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)
	await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [out, label])
	# The button as the window's pixels show it: the canvas units go through the stretch.
	var rect := (
		get_viewport().get_final_transform()
		* (button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, button.size))
	)
	var close := Rect2i(rect.grow(CLOSE_UP)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var crop := image.get_region(close)
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s_close.png" % [out, label])
	print("saved ", label, " scale ", button.scale, " window ", get_window().size)
