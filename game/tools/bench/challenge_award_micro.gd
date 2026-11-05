extends Node
## What `ChallengeAward` costs by itself, in microseconds (#1076): a kill's events one after another
## through the tracker with the shipped catalogue and four fresh boards, the events it ignores, a
## frame (the weapons in the players' hands), a burst of 120 kills in one tick, and the client
## applying what it tells. No server, no sockets: the events are made by hand with the keys the
## rules give them, so the numbers are the tracker's alone and repeat run to run. Prints one
## `CHALLENGE_AWARD_MICRO {json}` line. Run headless: `godot --headless --path game
## res://tools/bench/challenge_award_micro.tscn`. Not part of the play.

const KILLS := 20000
const WARM := 2000
const BURST := 120
const BURSTS := 200
const FUEL: Array[StringName] = [&"fuel_can"]


func _ready() -> void:
	var xp := XpAward.new(FUEL)
	var award := ChallengeAward.new(xp, FUEL)
	for id in range(1, 5):
		xp.register(id, "micro-%d" % id, 0, 0)
		award.seat(id, "micro-%d" % id)
		award.arrived("micro-%d" % id, 404, ChallengeAward.NO_BOARD)
	var hit := {"type": &"points_changed", "player_id": 1, "delta": 10, "reason": &"hit"}
	var kill := _kill(1)
	var pay := {"type": &"points_changed", "player_id": 1, "delta": 100, "reason": &"kill"}
	var shot := {"type": &"shot_fired", "shooter_id": 1, "weapon_id": &"pistol"}
	var heard := [hit, hit, hit, kill, pay]
	for _i in WARM:
		for event: Dictionary in heard:
			award.observe(event)
	award.take_events()
	var report := {"kills": KILLS, "events_a_kill": heard.size()}
	var began := Time.get_ticks_usec()
	for i in KILLS:
		var seat := 1 + (i & 3)
		for event: Dictionary in heard:
			event["player_id" if event["type"] == &"points_changed" else "killer_id"] = seat
			award.observe(event)
		if i % 16 == 0:
			award.take_events()
	report["us_a_kill"] = snappedf(float(Time.get_ticks_usec() - began) / KILLS, 0.01)
	# The events it passes over cost one dictionary read each.
	began = Time.get_ticks_usec()
	for _i in KILLS:
		award.observe({"type": &"player_hurt", "player_id": 1})
	report["us_an_ignored_event"] = snappedf(float(Time.get_ticks_usec() - began) / KILLS, 0.001)
	# A shot and a frame (every tick that is sent builds one): the tally learns the weapons.
	began = Time.get_ticks_usec()
	for _i in KILLS:
		award.observe(shot)
	report["us_a_shot"] = snappedf(float(Time.get_ticks_usec() - began) / KILLS, 0.001)
	var frame := {"type": &"frame", "players": {}}
	for id in range(1, 5):
		frame["players"][id] = {"weapon": &"pistol", "pos": Vector3.ZERO}
	began = Time.get_ticks_usec()
	for _i in KILLS:
		award.observe(frame)
	report["us_a_frame_of_four"] = snappedf(float(Time.get_ticks_usec() - began) / KILLS, 0.01)
	# A burst of kills in one tick, spread over the four seats.
	var spent := PackedFloat32Array()
	for _b in BURSTS:
		var burst := Time.get_ticks_usec()
		for i in BURST:
			var seat := 1 + (i & 3)
			award.observe(_kill(seat))
			award.observe(
				{"type": &"points_changed", "player_id": seat, "delta": 100, "reason": &"kill"}
			)
		award.take_events()
		spent.append(float(Time.get_ticks_usec() - burst))
	spent.sort()
	report["us_a_burst_of_120_kills_median"] = spent[spent.size() / 2]
	report["us_a_burst_of_120_kills_worst"] = spent[spent.size() - 1]
	# A report's worth: the boards of four seats put into the entries.
	var entries: Array[Dictionary] = []
	for id in range(1, 5):
		entries.append({"user": "micro-%d" % id})
	began = Time.get_ticks_usec()
	var board_bytes := 0
	for _i in 200:
		award.fill_report(entries)
		for entry in entries:
			entry.erase("board")
		for board in award._boards.values():
			board.dirty = true
	report["us_filling_a_report_of_four_boards"] = snappedf(
		float(Time.get_ticks_usec() - began) / 200, 0.1
	)
	award.fill_report(entries)
	board_bytes = JSON.stringify(entries[0]["board"]).length()
	report["board_json_bytes"] = board_bytes
	# The client's side: a ClientState hearing the events the tracker makes, nothing else listening.
	var state := ClientState.new()
	state.player_id = 1
	var progress := {
		"type": &"challenge_progress",
		"player_id": 1,
		"id": &"d_kills_40",
		"family": 0,
		"text": "Put down 40 zombies",
		"before": 9,
		"after": 10,
		"target": 40,
		"checkpoint": 25,
		"completed": false,
		"rung": 0,
		"rungs": 0,
	}
	var batch: Array = [progress]
	began = Time.get_ticks_usec()
	for _i in KILLS:
		state.apply_events(batch)
	report["client_us_applying_a_challenge_progress"] = snappedf(
		float(Time.get_ticks_usec() - began) / KILLS, 0.01
	)
	report["challenge_progress_bytes"] = var_to_bytes(progress).size()
	report["calibration_ms"] = PerfSampler.calibrate()
	print("CHALLENGE_AWARD_MICRO ", JSON.stringify(report))
	get_tree().quit()


func _kill(killer: int) -> Dictionary:
	return {
		"type": &"zombie_removed",
		"killer_id": killer,
		"cause": &"killed",
		"zombie_type": &"walker",
		"boss": false,
		"zone": &"head",
		"melee": false,
	}
