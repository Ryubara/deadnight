extends Node
## What `XpAward` costs by itself, in microseconds (#1059): a kill's events one after another, the
## events it ignores, the end of a tick with four seats to tell, and a burst of 120 kills in one
## tick (a grenade into a horde). No server, no sockets: the events are made by hand with the keys
## the rules give them, so the numbers are the award's alone and repeat run to run. Prints one
## `XP_AWARD_MICRO {json}` line. Run headless: `godot --headless --path game
## res://tools/bench/xp_award_micro.tscn`. Not part of the play.

const KILLS := 20000
const WARM := 2000
const BURST := 120
const BURSTS := 200


func _ready() -> void:
	var award := _award()
	# A kill as the rules say it: a few hits that pay, the removal, the points the kill pays.
	var hit := {"type": &"points_changed", "player_id": 1, "delta": 10, "reason": &"hit"}
	var kill := _kill(1)
	var pay := {"type": &"points_changed", "player_id": 1, "delta": 100, "reason": &"kill"}
	var shot := {"type": &"shot_fired", "shooter_id": 1, "weapon_id": &"pistol"}
	var heard := [hit, hit, hit, kill, pay]
	for _i in WARM:
		for event: Dictionary in heard:
			award.observe(event)
	award.end_tick()
	var report := {"kills": KILLS, "events_a_kill": heard.size()}
	var began := Time.get_ticks_usec()
	for i in KILLS:
		var seat := 1 + (i & 3)
		for event: Dictionary in heard:
			event["player_id" if event["type"] == &"points_changed" else "killer_id"] = seat
			award.observe(event)
	report["us_a_kill"] = snappedf(float(Time.get_ticks_usec() - began) / KILLS, 0.01)
	# The events it passes over cost one dictionary read each.
	began = Time.get_ticks_usec()
	for _i in KILLS:
		award.observe(shot)
	report["us_an_ignored_event"] = snappedf(float(Time.get_ticks_usec() - began) / KILLS, 0.001)
	# The end of a tick: nothing to tell, and four seats to tell.
	award.end_tick(true)
	began = Time.get_ticks_usec()
	for _i in KILLS:
		award.end_tick()
	report["us_a_quiet_tick"] = snappedf(float(Time.get_ticks_usec() - began) / KILLS, 0.001)
	began = Time.get_ticks_usec()
	var told := 0
	for i in KILLS:
		for id in 4:
			hit["player_id"] = id + 1
			award.observe(hit)
		told += award.end_tick().size()
	report["us_a_tick_telling_four_seats"] = snappedf(
		float(Time.get_ticks_usec() - began) / KILLS, 0.01
	)
	report["events_told"] = told
	# A burst of kills in one tick, spread over the four seats, then the tick's end.
	var spent := PackedFloat32Array()
	for _b in BURSTS:
		var burst := Time.get_ticks_usec()
		for i in BURST:
			var seat := 1 + (i & 3)
			var removal := _kill(seat)
			var paid := {
				"type": &"points_changed", "player_id": seat, "delta": 100, "reason": &"kill"
			}
			award.observe(removal)
			award.observe(paid)
		award.end_tick()
		spent.append(float(Time.get_ticks_usec() - burst))
	spent.sort()
	report["us_a_burst_of_120_kills_median"] = spent[spent.size() / 2]
	report["us_a_burst_of_120_kills_worst"] = spent[spent.size() - 1]
	# The client's side: a ClientState hearing the events the award makes, nothing else listening.
	var state := ClientState.new()
	state.player_id = 1
	var gained := {
		"type": &"xp_gained",
		"player_id": 1,
		"hundredths": 130,
		"xp": 40,
		"total": 340,
		"sources": {&"points_earned": 130},
	}
	var batch: Array = [gained]
	began = Time.get_ticks_usec()
	for _i in KILLS:
		state.apply_events(batch)
	report["client_us_applying_an_xp_gained"] = snappedf(
		float(Time.get_ticks_usec() - began) / KILLS, 0.01
	)
	report["xp_gained_bytes"] = var_to_bytes(gained).size()
	report["calibration_ms"] = PerfSampler.calibrate()
	print("XP_AWARD_MICRO ", JSON.stringify(report))
	get_tree().quit()


func _award() -> XpAward:
	var award := XpAward.new()
	for id in range(1, 5):
		award.register(id, "micro-%d" % id, 0, 0)
	return award


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
