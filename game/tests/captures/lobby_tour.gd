extends Node
## Stills of the lobby screen in each state a player meets it, at the window's real pixel size, one
## PNG each into `--out=<folder>`: the host alone, the host with friends (one away), a guest
## waiting, a guest told the night started, a night in progress read before joining (round 4), and
## a full night. The backend is a stand-in that answers from here. Run through the no-focus
## launcher, not headless: `godot --path game res://tests/captures/lobby_tour.tscn --windowed
## --resolution 1280x720 -- --out=<folder>`.

const SCREEN := "res://ui/screens/lobby_screen.tscn"
const SETTLE := 2.2


## A backend that answers `refresh` with what the tour holds.
class StandIn:
	extends TogetherApi
	var me := "a"

	func my_id() -> String:
		return me

	func refresh(held: Dictionary) -> Dictionary:
		return {"ok": true, "lobby": held}

	func leave(_held: Dictionary) -> Dictionary:
		return {"ok": true}

	func detached(_parent: Node) -> TogetherApi:
		return self


func _ready() -> void:
	var out := "user://lobby_tour"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var ann := _member("a", "Ann", 1, true)
	var bo := _member("b", "Bo", 2)
	var cy := _member("c", "Cy", 3, false, true)
	await _still(out, "host-alone", "a", {"lobby": _lobby([ann])})
	await _still(out, "host-with-friends", "a", {"lobby": _lobby([ann, bo, cy])})
	await _still(out, "guest-waiting", "b", {"lobby": _lobby([ann, bo, cy])})
	await _still(out, "guest-started", "b", {"lobby": _lobby([ann, bo, cy], "started", 0)})
	await _still(out, "preview-in-progress", "d", {"preview": _preview("started", 4, 3, false)})
	await _still(out, "preview-waiting", "d", {"preview": _preview("open", null, 2, false)})
	await _still(out, "preview-full", "d", {"preview": _preview("started", 2, 4, true)})
	# The tallest the screen gets, on the web in a frame that refuses to copy: four seats, the
	# page's link, the blocked-copy line and the selected text. It must fit a 720-high window.
	var di := _member("d", "Di", 4)
	await _still(out, "tallest", "a", {"lobby": _lobby([ann, bo, cy, di])}, _make_tallest)
	# The room's eight seats (#690): five people, the host's Bots setting at 3 in the open ones.
	var people := [ann, bo, cy, di, _member("e", "Ed", 5), _member("f", "Fay", 6)]
	await _still(
		out, "eight-seats-bots", "a", {"lobby": _lobby(people.slice(0, 5), "open", null, 8, 3)}
	)
	await _still(
		out,
		"eight-seats-tallest",
		"a",
		{"lobby": _lobby(people, "open", null, 8, 2)},
		_make_tallest
	)
	get_tree().quit()


func _make_tallest(screen: LobbyScreen) -> void:
	screen.link_label.text = "https://example.invalid/deadnight/index.html?room=K7QM4X"
	screen.link_label.visible = true
	screen.copy_link_button.visible = true
	screen.show_selected(screen.link_label.text)
	screen.note.text = TogetherScreen.COPY_BLOCKED


func _still(
	out: String, label: String, me: String, params: Dictionary, adjust := Callable()
) -> void:
	var api := StandIn.new(self)
	api.me = me
	await RouterFixture.clear(get_tree())
	UIRouter.reset(SCREEN, UITransition.Kind.CUT, params.merged({"api": api}))
	await UIRouter.idle
	var screen := UIRouter.top() as LobbyScreen
	screen.watch.every = 3600.0
	if adjust.is_valid():
		adjust.call(screen)
	await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, " window ", get_window().size)


func _member(
	id: String, member_name: String, seat: int, host := false, away := false
) -> Dictionary:
	return {"userId": id, "name": member_name, "seat": seat, "host": host, "away": away}


func _lobby(
	members: Array, state := "open", round_number: Variant = null, seats := 4, bots := 0
) -> Dictionary:
	return {
		"id": "l1",
		"code": "K7QM4X",
		"hostId": "a",
		"maxPlayers": seats,
		"settings": {"count_multiplier": 1.0, "max_alive": 0, "break_seconds": 0.0, "bots": bots},
		"members": members,
		"state": state,
		"round": round_number,
		"players": null,
	}


func _preview(state: String, round_number: Variant, players: int, full: bool) -> Dictionary:
	return {
		"code": "K7QM4X",
		"state": state,
		"round": round_number,
		"players": players,
		"maxPlayers": 4,
		"full": full,
		"hostName": "Ann",
		"names": ["Ann", "Bo", "Cy", "Di"].slice(0, players),
	}
