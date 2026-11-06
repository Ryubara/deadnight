extends Node
## Stills of the lobby's Private switch (#1186), at the window's real pixel size, one PNG each into
## `--out=<folder>`: the host with the night public (the default), the host with it private (the
## switch pressed with the keyboard, as a player would), and a guest reading each, read only.
## `--factor=<n>` is the content scale the screen under test runs at (the menu's phone factor 2 on
## a phone, `MenuScale.factor`), `--tag=<text>` is put in the file names. Each still prints the
## window, the factor and the canvas in units, so nobody reads a layout at a scale it never had.
## Run through the no-focus launcher: `gds godot -- --path game
## res://tests/captures/lobby_private_tour.tscn --windowed --resolution 1688x780 -- --out=<folder>
## --factor=2 --tag=phone-page`.

const SCREEN := "res://ui/screens/lobby_screen.tscn"
const SETTLE := 1.2


## A backend that answers from here: `refresh` with the lobby the tour holds, the switch as a host
## sends it.
class StandIn:
	extends TogetherApi
	var me := "a"

	func my_id() -> String:
		return me

	func refresh(held: Dictionary) -> Dictionary:
		return {"ok": true, "lobby": held}

	func set_visibility(held: Dictionary, public_night: bool) -> Dictionary:
		var next := held.duplicate()
		next["visibility"] = TogetherApi.visibility_word(public_night)
		return {"ok": true, "lobby": next}

	func leave(_held: Dictionary) -> Dictionary:
		return {"ok": true}

	func detached(_parent: Node) -> TogetherApi:
		return self


var _out := "user://lobby_private_tour"
var _tag := ""
## `--before`: a lobby that says nothing of visibility (the backend before the switch), so no row:
## the lobby as it was.
var _before := false


func _ready() -> void:
	var factor := -1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--factor="):
			factor = float(arg.trim_prefix("--factor="))
		elif arg == "--before":
			_before = true
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute(_out)
	var window := get_window()
	window.content_scale_factor = (factor if factor > 0.0 else MenuScale.factor(window.size, 1.0))
	await get_tree().process_frame
	var ann := _member("a", "Ann", 1, true)
	var bo := _member("b", "Bo", 2)
	var cy := _member("c", "Cy", 3)
	if _before:
		await _still("host-before", "a", _lobby([ann, bo, cy], ""), false)
		get_tree().quit()
		return
	await _still("host-public", "a", _lobby([ann, bo, cy], "public"), false)
	await _still("host-private", "a", _lobby([ann, bo, cy], "public"), true)
	await _still("guest-public", "b", _lobby([ann, bo, cy], "public"), false)
	await _still("guest-private", "b", _lobby([ann, bo, cy], "private"), false)
	get_tree().quit()


func _still(label: String, me: String, lobby: Dictionary, press: bool) -> void:
	var api := StandIn.new(self)
	api.me = me
	await RouterFixture.clear(get_tree())
	UIRouter.reset(SCREEN, UITransition.Kind.CUT, {"api": api, "lobby": lobby})
	await UIRouter.idle
	var screen := UIRouter.top() as LobbyScreen
	screen.watch.every = 3600.0
	await get_tree().create_timer(SETTLE).timeout
	if press:
		# The keyboard, as a player at a desk would.
		screen.private_switch.toggle.grab_focus()
		for down in [true, false]:
			var key := InputEventKey.new()
			key.keycode = KEY_ENTER
			key.physical_keycode = KEY_ENTER
			key.pressed = down
			get_viewport().push_input(key)
			await get_tree().process_frame
		await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var name_part := "%s-%s" % [_tag, label] if _tag != "" else label
	var path := "%s/%s.png" % [_out, name_part]
	get_viewport().get_texture().get_image().save_png(path)
	print(
		(
			"saved %s window %s factor %s canvas %s private=%s editable=%s row=%s"
			% [
				path,
				get_window().size,
				get_window().content_scale_factor,
				get_viewport().get_visible_rect().size,
				screen.private_switch.is_private(),
				screen.private_switch.editable,
				(
					screen.private_switch.row.get_global_rect()
					if screen.private_switch.row.visible
					else "none"
				)
			]
		)
	)


func _member(id: String, member_name: String, seat: int, host := false) -> Dictionary:
	return {"userId": id, "name": member_name, "seat": seat, "host": host, "away": false}


func _lobby(members: Array, visibility: String) -> Dictionary:
	var held := {
		"id": "l1",
		"code": "K7QM4X",
		"hostId": "a",
		"maxPlayers": 8,
		"settings": null,
		"members": members,
		"state": "open",
		"round": null,
		"players": null,
	}
	if visibility != "":
		held["visibility"] = visibility
	return held
