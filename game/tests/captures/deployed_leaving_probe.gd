extends Node
## Leaving a night on a DEPLOYED backend and game server (Deadnight #1177), with two real
## clients: each is a `TogetherApi` with a session of its own plus a `Night` on a real WebSocket
## to the game server. `--backend=<https address>`; `--ended` also waits for a night to end by
## itself (no bots, an idle player, a 5x crowd: a few minutes) and checks the reopened lobby
## holds nobody. Not part of the game.
##
## Run: godot --headless --path game res://tests/captures/deployed_leaving_probe.tscn --
## --backend=https://... Prints `PROBE ...` lines; the last is `PROBE RESULT passed=N failed=M`.

var _backend := ""
var _passed := 0
var _failed := 0
var _nights: Array[Night] = []


func _ready() -> void:
	var with_end := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--backend="):
			_backend = arg.trim_prefix("--backend=")
		elif arg == "--ended":
			with_end = true
	var ann := await _client("Ann")
	var bo := await _client("Bo")
	# Bo waits in a lobby of his own on the lobby screen (polling it), as a friend would.
	var waiting: Dictionary = (await bo.api.create_lobby())["lobby"]
	var waiting_code: String = waiting["code"]
	await _leave_then_move(ann, bo, waiting, waiting_code, "button", "join")
	await _leave_then_move(ann, bo, waiting, waiting_code, "tab", "quick")
	await _leave_then_move(ann, bo, waiting, waiting_code, "tab", "create")
	if with_end:
		await _ended_night(ann, bo)
	print("PROBE RESULT passed=%d failed=%d" % [_passed, _failed])
	for night in _nights:
		if is_instance_valid(night) and night.link != null:
			night.link.close()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(1 if _failed > 0 else 0)


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
		"quick":
			answer = await client.api.quick()
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
	if next == "join" and answer["ok"]:
		var seen := await watcher.api.refresh(waiting)
		var names: Array = seen["lobby"]["members"].map(
			func(m: Dictionary) -> String: return m["name"]
		)
		_check(names.has(client.name), "%s: Bo's waiting room lists Ann (%s)" % [tag, names])
		await client.api.leave(answer["lobby"])
	elif answer["ok"] and next != "join":
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
	while not ann.night.state.closed and Time.get_ticks_msec() - began < 480000:
		await get_tree().create_timer(1.0).timeout
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
