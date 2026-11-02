extends Node
## Four players, each starting a night of their own on the deployed backend: the game server takes
## three (`ROOM_CAPACITY`) and the backend gives the fourth no ticket (`no_server`). The three
## stand in their rooms for `--seconds` (default 90) under a 5x night with 120 asked alive; the
## server's `stats` log lines (`railway logs`) say what the rooms cost. Not part of the game.
## `--backend=<https address>`.

var _nights: Array[Night] = []


func _ready() -> void:
	var backend := ""
	var seconds := 90.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--backend="):
			backend = arg.trim_prefix("--backend=")
		elif arg.begins_with("--seconds="):
			seconds = float(arg.trim_prefix("--seconds="))
	var settings := MatchSettings.new()
	settings.count_multiplier = 5.0
	settings.max_alive = 120
	var refused := 0
	for index in 4:
		var api := TogetherApi.new(self, backend)
		api.isolated = true
		var signed := await api.sign_in("probe%d" % index)
		if not signed["ok"]:
			print("PROBE sign-in failed ", signed)
			get_tree().quit(1)
			return
		var made := await api.create(settings)
		if not made["ok"]:
			print("PROBE player %d create: %s" % [index, made])
			refused += 1
			continue
		var ticket := await api.ticket(made["lobby"])
		if not ticket["ok"]:
			print("PROBE player %d ticket: %s" % [index, ticket])
			refused += 1
			continue
		var viewport := SubViewport.new()
		viewport.own_world_3d = true
		viewport.size = Vector2i(64, 64)
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var night := Night.new()
		viewport.add_child(night)
		var link := WebSocketLink.new()
		link.ticket = ticket["ticket"]
		var joined := await night.start_remote(ticket["url"], Night.Mode.MANUAL, 30.0, link)
		print("PROBE player %d joined=%s url=%s" % [index, joined, ticket["url"]])
		if joined:
			_nights.append(night)
	print("PROBE joined=%d refused=%d" % [_nights.size(), refused])
	var began := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - began) / 1000.0 < seconds:
		await get_tree().create_timer(10.0).timeout
		print(
			(
				"PROBE t=%ds, %d players connected"
				% [(Time.get_ticks_msec() - began) / 1000, _nights.size()]
			)
		)
	print("PROBE done")
	get_tree().quit()
