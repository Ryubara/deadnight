extends Node
## Leaving a night on a DEPLOYED backend and game server (Deadnight #1177), with two real
## clients: each is a `TogetherApi` with a session of its own plus a `Night` on a real WebSocket
## to the game server. `--backend=<https address>`; `--ended` also waits for a night to end by
## itself (no bots, an idle player, a 5x crowd: a few minutes) and checks the reopened lobby
## holds nobody. Not part of the game.
##
## Run: godot --headless --path game res://tests/captures/deployed_leaving_probe.tscn --
## --backend=https://... Prints `PROBE ...` lines; the last is `PROBE RESULT passed=N failed=M`.
##
## Lobbies live in the memory of one backend, and production deploys the backend every few minutes
## as main merges (#1240): a deploy during the run wipes every lobby it holds, so a check that
## reads one cannot pass. `/health` names each run of the backend (`boot`); when it changed during
## the run, a failing run ends with `PROBE INCONCLUSIVE` and exit code 2 (run it again) instead of
## a failure nobody could have avoided.

const WAITING_ROOM_READS_EVERY := 2.0

var _backend := ""
var _passed := 0
var _failed := 0
var _nights: Array[Night] = []
var _boot := ""
var _reading := true


func _ready() -> void:
	var with_end := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--backend="):
			_backend = arg.trim_prefix("--backend=")
		elif arg == "--ended":
			with_end = true
	_boot = await _boot_of_backend()
	print("PROBE backend run ", _boot)
	var ann := await _client("Ann")
	var bo := await _client("Bo")
	# Bo waits in a lobby of his own on the lobby screen, reading it every couple of seconds as the
	# screen does: a waiting room nobody reads is left out of the Server Browser after 15 s.
	var waiting: Dictionary = (await bo.api.create_lobby())["lobby"]
	var waiting_code: String = waiting["code"]
	_keep_reading(bo, waiting)
	await _leave_then_move(ann, bo, waiting, waiting_code, "button", "join")
	await _leave_then_move(ann, bo, waiting, waiting_code, "tab", "list")
	await _leave_then_move(ann, bo, waiting, waiting_code, "tab", "create")
	if with_end:
		await _ended_night(ann, bo)
	_reading = false
	print("PROBE RESULT passed=%d failed=%d" % [_passed, _failed])
	var after := await _boot_of_backend()
	var restarted := _boot != "" and after != "" and after != _boot
	if restarted and _failed > 0:
		print(
			(
				"PROBE INCONCLUSIVE the backend was deployed during the run (%s, then %s)"
				% [_boot, after]
			)
		)
		print("PROBE its lobbies went with it; run the probe again")
	for night in _nights:
		if is_instance_valid(night) and night.link != null:
			night.link.close()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(2 if restarted and _failed > 0 else (1 if _failed > 0 else 0))


## Which run of the backend answers (`/health` `boot`); "" from a backend that does not say.
func _boot_of_backend() -> String:
	var health := await HttpJson.send(self, "GET", _backend + "/health")
	if health["status"] != 200 or not health["json"] is Dictionary:
		return ""
	return str(health["json"].get("boot", ""))


## The codes of the rows `list_nights` gave.
func _codes(listed: Dictionary) -> Array:
	var out := []
	for row: Dictionary in listed.get("nights", []):
		out.append(str(row["code"]))
	return out


## `client` reads `lobby` every `WAITING_ROOM_READS_EVERY` seconds until the probe is done.
func _keep_reading(client: Client, lobby: Dictionary) -> void:
	while _reading:
		await get_tree().create_timer(WAITING_ROOM_READS_EVERY).timeout
		if _reading:
			await client.api.refresh(lobby)


class Client:
	extends RefCounted
	var api: TogetherApi
	var name := ""
	var lobby := {}
	var night: Night


func _client(player_name: String) -> Client:
	var client := Client.new()
	client.name = player_name
	client.api = TogetherApi.new(self, _backend)
	client.api.isolated = true
	var signed := await client.api.sign_in(player_name)
	_check(signed["ok"], "%s signs in" % player_name)
	return client


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("PROBE ok   ", what)
	else:
		_failed += 1
		print("PROBE FAIL ", what)


## `client` hosts a night with `bots` bots and is in it over a real WebSocket.
func _into_a_night(client: Client, bots: int, extra: MatchSettings = null) -> bool:
	var rules := extra if extra != null else MatchSettings.new()
	rules.bots = bots
	var made := await client.api.create(rules)
	if not made["ok"]:
		print("PROBE create failed: ", made)
		return false
	client.lobby = made["lobby"]
	var pass_to := await client.api.ticket(client.lobby)
	if not pass_to["ok"]:
		print("PROBE ticket failed: ", pass_to)
		return false
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var night := Night.new()
	viewport.add_child(night)
	var link := WebSocketLink.new()
	link.ticket = pass_to["ticket"]
	var joined := await night.start_remote(pass_to["url"], Night.Mode.MANUAL, 60.0, link)
	if not joined:
		print("PROBE the night did not take ", client.name)
		return false
	client.night = night
	_nights.append(night)
	return true


func _bodies_seen(client: Client) -> int:
	return client.night.state.frame.get("players", {}).size()


func _lobby_exists(looker: Client, code: String) -> bool:
	return (await looker.api.preview(code))["ok"]


## `client` is alone in a night with bots, leaves it as `how` says (`button`: says leave,
## then closes the socket; `tab`: only the socket goes) and does `next` at once. Checks the
## move was not refused, how long it took, and that the lobby left is gone and the one
## moved to lists the client.
func _leave_then_move(
	client: Client,
	watcher: Client,
	waiting: Dictionary,
	waiting_code: String,
	how: String,
	next: String
) -> void:
	var tag := "%s then %s" % [how, next]
	if not await _into_a_night(client, 3):
		_check(false, "%s: Ann is in a night with bots" % tag)
		return
	var old_code: String = client.lobby["code"]
	# Wait until the bots are seated (more than the one body).
	var seated := false
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 15000 and not seated:
		seated = _bodies_seen(client) > 1
		await get_tree().create_timer(0.2).timeout
	_check(seated, "%s: bots are in the night (%d bodies)" % [tag, _bodies_seen(client)])
	var left_at := Time.get_ticks_msec()
	if how == "button":
		_check((await client.api.leave(client.lobby))["ok"], "%s: leave says ok" % tag)
	client.night.link.close()
	var answer: Dictionary
	match next:
		"join":
			answer = await client.api.join_code(waiting_code)
		"list":
			# The Server Browser's way in: read the list, then join the row by its code. The row is
			# Bo's waiting room (read every couple of seconds, so listed), never the first row: that
			# is the night she has just left, which the game server's word that the seat is empty
			# takes out of the list a moment after (#1240), and on production anyone else's night.
			var listed := await client.api.list_nights()
			var codes := _codes(listed)
			var row_there: bool = codes.has(waiting_code)
			_check(
				row_there,
				"%s: the Server Browser lists Bo's waiting room (%d nights)" % [tag, codes.size()]
			)
			answer = await client.api.join_code(waiting_code) if row_there else listed
		_:
			answer = await client.api.create_lobby()
	var moved_ms := Time.get_ticks_msec() - left_at
	_check(
		answer["ok"],
		"%s: %s straight away (%d ms), %s" % [tag, next, moved_ms, answer.get("error", "")]
	)
	# The lobby she left has no person in it: it is gone, and she is not listed in it.
	var gone_at := Time.get_ticks_msec()
	var gone := false
	while Time.get_ticks_msec() - gone_at < 12000 and not gone:
		gone = not await _lobby_exists(watcher, old_code)
		if not gone:
			await get_tree().create_timer(0.2).timeout
	_check(
		gone,
		(
			"%s: the lobby left (%s) is gone after %d ms"
			% [tag, old_code, Time.get_ticks_msec() - left_at]
		)
	)
	if next == "list":
		# And the night she left is out of the list from the very next call.
		var again := await watcher.api.list_nights()
		_check(
			not _codes(again).has(old_code),
			"%s: the night left (%s) is out of the Server Browser" % [tag, old_code]
		)
	if next != "create" and answer["ok"]:
		var seen := await watcher.api.refresh(waiting)
		var names: Array = seen["lobby"]["members"].map(
			func(m: Dictionary) -> String: return m["name"]
		)
		_check(names.has(client.name), "%s: Bo's waiting room lists Ann (%s)" % [tag, names])
		await client.api.leave(answer["lobby"])
	elif answer["ok"]:
		# Whatever the move made is left too, so the next scenario starts from the menu.
		await client.api.leave(answer["lobby"])


## No bots, an idle player and a heavy crowd: the night ends by itself. Neither client
## says leave; the lobby opens again for them, and Ann creates a night at once.
func _ended_night(ann: Client, bo: Client) -> void:
	var rules := MatchSettings.new()
	rules.count_multiplier = 5.0
	rules.break_seconds = 1.0
	if not await _into_a_night(ann, 0, rules):
		_check(false, "ended: Ann is in a night")
		return
	var code: String = ann.lobby["code"]
	var began := Time.get_ticks_msec()
	var dropped := [false]
	ann.night.connection_ended.connect(func() -> void: dropped[0] = true)
	while not ann.night.state.closed and not dropped[0] and Time.get_ticks_msec() - began < 480000:
		await get_tree().create_timer(1.0).timeout
	if dropped[0] and not ann.night.state.closed:
		print("PROBE the game server dropped Ann before the night closed (a deploy of it?)")
	_check(
		ann.night.state.over,
		"ended: the night ended by itself after %d s" % ((Time.get_ticks_msec() - began) / 1000)
	)
	if not ann.night.state.over:
		return
	var opened := false
	var waited := Time.get_ticks_msec()
	while Time.get_ticks_msec() - waited < 40000 and not opened:
		var seen := await bo.api.preview(code)
		opened = seen["ok"] and seen["preview"]["state"] == "open"
		if not opened:
			await get_tree().create_timer(0.5).timeout
	_check(opened, "ended: the lobby opened again for Ann (nobody read it)")
	var made := await ann.api.create_lobby()
	_check(made["ok"], "ended: Ann creates another night at once, %s" % made.get("error", ""))
	if made["ok"]:
		await ann.api.leave(made["lobby"])
