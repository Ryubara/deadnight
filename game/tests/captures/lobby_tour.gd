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
	get_tree().quit()


func _still(out: String, label: String, me: String, params: Dictionary) -> void:
	var api := StandIn.new(self)
	api.me = me
	await RouterFixture.clear(get_tree())
	UIRouter.reset(SCREEN, UITransition.Kind.CUT, params.merged({"api": api}))
	await UIRouter.idle
	var screen := UIRouter.top() as LobbyScreen
	screen.watch.every = 3600.0
	await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, " window ", get_window().size)


func _member(
	id: String, member_name: String, seat: int, host := false, away := false
) -> Dictionary:
	return {"userId": id, "name": member_name, "seat": seat, "host": host, "away": away}


func _lobby(members: Array, state := "open", round_number: Variant = null) -> Dictionary:
	return {
		"id": "l1",
		"code": "K7QM4X",
		"hostId": "a",
		"maxPlayers": 4,
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
