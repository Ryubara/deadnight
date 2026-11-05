class_name BrowserFixture
extends RefCounted
## What the Server Browser's suites and captures share: a backend that answers the list from the
## test, and the rows it answers with (`{id, code, map, hostName, players, maxPlayers, bots, kind,
## state, round, full}`).


## The backend's answers, from the test: no network. The list is `nights`; a code joins the lobby
## `by_code` holds (else `lobby`); `list_failure` and `join_failure` are the backend's reasons.
class FakeApi:
	extends LobbyFixture.FakeApi
	signal released
	var nights: Array = []
	var list_failure := ""
	var list_calls := 0
	var join_failure := ""
	var by_code := {}
	var created := 0
	var refreshes := 0
	## Held until `released` when set: a list or a join that is slow.
	var hold_join := false
	var hold_list := false
	var sign_in_failure := ""

	func sign_in(_display_name: String = "") -> Dictionary:
		if sign_in_failure != "":
			return TogetherApi._failed(sign_in_failure)
		return {"ok": true}

	func list_nights() -> Dictionary:
		list_calls += 1
		if hold_list:
			await released
		if list_failure != "":
			return TogetherApi._failed(list_failure)
		return {
			"ok": true, "maxPlayers": 8, "total": nights.size(), "nights": nights.duplicate(true)
		}

	func join_code(code: String) -> Dictionary:
		joined.append(code)
		if hold_join:
			await released
		if join_failure != "":
			return TogetherApi._failed(join_failure)
		return {"ok": true, "lobby": by_code.get(code, lobby)}

	func refresh(_held: Dictionary) -> Dictionary:
		refreshes += 1
		return {"ok": true, "lobby": refreshed if not refreshed.is_empty() else lobby}

	func create_lobby() -> Dictionary:
		created += 1
		var host := LobbyFixture.member(me, "Me", 1, true)
		return {"ok": true, "lobby": LobbyFixture.lobby([host])}


## One row of the list.
static func row(
	code: String,
	map: String,
	kind: String,
	players: int,
	host: String,
	bots := 0,
	round_number: Variant = null,
	full := false
) -> Dictionary:
	var started := kind == "match"
	return {
		"id": "id-%s" % code,
		"code": code,
		"map": map,
		"hostName": host,
		"players": players,
		"maxPlayers": 8,
		"bots": bots,
		"kind": kind,
		"state": "started" if started else "open",
		"round": round_number if started else null,
		"full": full or players >= 8,
	}


## Several nights of both kinds on both maps, room first and the full one last, as the backend
## orders them.
static func nights() -> Array:
	return [
		row("KITE42", "drive_in", "match", 3, "Ann the Projectionist", 2, 6),
		row("LAMP77", "small_indoor", "lobby", 2, "Bo", 0),
		row("ROSE19", "drive_in", "lobby", 1, "Cy", 3),
		row("MOTH05", "small_indoor", "match", 5, "Di", 0, 11),
		row("FULL88", "drive_in", "match", 8, "Ed", 1, 3),
	]


## The lobby a join of `code` answers: open, or started with a round.
static func lobby_of(code: String, started := false, map := "drive_in") -> Dictionary:
	var host := LobbyFixture.member("h-%s" % code, "Host", 1, true)
	var held := LobbyFixture.lobby([host], "started" if started else "open", 3 if started else null)
	held["id"] = "id-%s" % code
	held["code"] = code
	held["maxPlayers"] = 8
	held["map"] = map
	return held
