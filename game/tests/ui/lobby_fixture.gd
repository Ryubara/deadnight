class_name LobbyFixture
extends RefCounted
## What the lobby suites share: a backend that answers from the test, and the lobbies and
## previews it answers with.


## The backend's answers, from the test: no network.
class FakeApi:
	extends TogetherApi
	var me := "a"
	var lobby := {}
	var refreshed := {}
	var started: Dictionary = {}
	var start_failure := ""
	var joined: Array[String] = []
	var left: Array[String] = []
	var tickets := 0
	var preview_answer := {}

	func my_id() -> String:
		return me

	func sign_in(_display_name: String = "") -> Dictionary:
		return {"ok": true}

	func refresh(_held: Dictionary) -> Dictionary:
		return {"ok": true, "lobby": refreshed if not refreshed.is_empty() else lobby}

	func start(_held: Dictionary) -> Dictionary:
		if start_failure != "":
			return TogetherApi._failed(start_failure)
		return {"ok": true, "lobby": started}

	func preview(_code: String) -> Dictionary:
		if preview_answer.has("ok"):
			return preview_answer
		return {"ok": true, "preview": preview_answer}

	func join_code(code: String) -> Dictionary:
		joined.append(code)
		return {"ok": true, "lobby": lobby}

	func leave(held: Dictionary) -> Dictionary:
		left.append(str(held["id"]))
		return {"ok": true}

	func detached(_parent: Node) -> TogetherApi:
		return self

	func ticket(_held: Dictionary) -> Dictionary:
		tickets += 1
		return {
			"ok": true,
			"url": "ws://127.0.0.1:1",
			"activity_path": "/server",
			"ticket": "t-%d" % tickets,
			"match": "m1",
		}


## Every answer says the player is not a member any more.
class FailingApi:
	extends FakeApi

	func refresh(_held: Dictionary) -> Dictionary:
		return TogetherApi._failed("not_member")


static func member(
	id: String, member_name: String, seat: int, host := false, away := false
) -> Dictionary:
	return {"userId": id, "name": member_name, "seat": seat, "host": host, "away": away}


static func lobby(members: Array, state := "open", round_number: Variant = null) -> Dictionary:
	return {
		"id": "l1",
		"code": "ABC234",
		"hostId": members[0]["userId"],
		"maxPlayers": 4,
		"members": members,
		"state": state,
		"round": round_number,
		"players": null,
	}


static func preview(
	state: String, round_number: Variant, players: int, full := false
) -> Dictionary:
	return {
		"code": "ABC234",
		"state": state,
		"round": round_number,
		"players": players,
		"maxPlayers": 4,
		"full": full,
		"hostName": "Ann",
		"names": ["Ann", "Bo", "Cy", "Di"].slice(0, players),
	}
