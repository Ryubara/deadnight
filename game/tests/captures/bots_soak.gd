extends Node
## The nightly soak and parity batch of the bots plan (phase 7): whole nights played by hosted bots
## in
## the real server, one cell (a profile and a team size) at a time, night after night, with the
## numbers a night is judged by printed one line each. `tools/bots/soak_report.py` runs the cells in
## chunks, sets them beside the balance simulator's matching cells and writes the report.
##
## `godot --headless --path game res://tests/captures/bots_soak.tscn --fixed-fps 60 --
## --profile=regular
## --bots=4 --nights=10 --seed=1`
## Arguments after `--`: `--profile=rookie|regular|veteran` (every bot's), `--bots=N` (bots in the
## night, default 4), `--nights=N`, `--seed=S` (night n uses S + n), `--order=roam|follow|hold` (the
## standing order, given once at the start by the person if there is one, default roam),
## `--person` (a stand-in for a person, the old autopilot, takes seat 1 and the bots take the seats
## after it: the Follow and Hold gates need one), `--max-round=R` (a night that starts round R is
## counted as reaching it and stopped, default 30, the simulator's cap), `--max-minutes=M` (game
## minutes after which a night is stopped, default 45), `--budget=S` (wall seconds after which no
## new night starts, default 0: none), `--watch=SEAT` (a line a second of what that seat is doing,
## from
## `--from=TICK` and every `--every=TICKS`, for finding out why a gate broke) and `--quiet` (no
## trace line a minute).
## Prints `SOAKNIGHT {json}` for each night and `SOAKCELL {json}` at the end.

const STEP := Night.STEP
## Ticks between the physics frames the engine is given (a bought door's mesh needs one).
const FRAME_EVERY := 30
## Seat of the person stand-in.
const PERSON := 1
## Frames waited for the last bake before a night is freed.
const BAKE_WAIT_FRAMES := 600
## Game seconds between two trace lines.
const TRACE_EVERY := 60

var _args := {}


func _ready() -> void:
	_args = _parse_args()
	var title := String(_args.get("profile", "regular"))
	var nights := int(_args.get("nights", 10))
	var first_seed := int(_args.get("seed", 1))
	var budget := float(_args.get("budget", 0.0))
	var started := Time.get_ticks_msec()
	var summary := {
		"profile": title,
		"bots": int(_args.get("bots", 4)),
		"order": String(_args.get("order", "roam")),
		"person": _args.has("person"),
		"seed_start": first_seed,
		"nights": 0,
		"rounds": [],
		"failed": [],
	}
	for n in nights:
		if budget > 0.0 and float(Time.get_ticks_msec() - started) / 1000.0 > budget:
			break
		var report := await _play(first_seed + n)
		summary["nights"] += 1
		summary["rounds"].append(report["round"])
		if not report["broken"].is_empty():
			summary["failed"].append({"seed": first_seed + n, "broken": report["broken"]})
		print("SOAKNIGHT ", JSON.stringify(report))
	summary["wall_seconds"] = snappedf(float(Time.get_ticks_msec() - started) / 1000.0, 0.1)
	print("SOAKCELL ", JSON.stringify(summary))
	get_tree().quit()


## One night: the lot, the server, the bots, played to the end (everyone down), the round cap or
## the time cap. Returns the night's report with the gates it broke under `broken`.
func _play(seed_value: int) -> Dictionary:
	var began := Time.get_ticks_msec()
	var catcher := ErrorCatcher.new()
	catcher.start()
	var order := StringName(String(_args.get("order", "roam")))
	var person := _args.has("person")
	var bots := int(_args.get("bots", 4))
	var seats := bots + (1 if person else 0)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	var night := await SeatedNight.start(self, seats, tuning, seed_value, true)
	var people: Array[int] = []
	var first_bot := 1
	if person:
		var stand_in := night.seat(PERSON, BotProfile.autopilot(), 7000 + seed_value, true)
		night.host.bot_ids.erase(stand_in.state.player_id)
		people.append(PERSON)
		first_bot = PERSON + 1
	for i in bots:
		var id := first_bot + i
		night.seat(id, _profile(), 1000 + 100 * seed_value + id)
	var watch := SoakWatch.new(night, people, order)
	night.on_event = watch.hear
	night.on_action = watch.act
	night.start_round()
	if order != BotOrders.ROAM and person:
		night.give_order(order, PERSON, night.server.body_of(PERSON).global_position)
	var max_round := int(_args.get("max-round", 30))
	var limit := int(float(_args.get("max-minutes", 45)) * 3600.0)
	var ticks := 0
	var reason := "over"
	while true:
		if night.server.rules.phase == GameRules.Phase.OVER:
			break
		if night.server.rules.round_number >= max_round:
			reason = "cap_round"
			break
		if ticks >= limit:
			reason = "cap_time"
			break
		night.tick()
		watch.tick()
		ticks += 1
		if not _args.has("quiet") and ticks % (TRACE_EVERY * 60) == 0:
			print(
				(
					"TRACE seed %d t=%dm round %d remaining %d"
					% [
						seed_value,
						ticks / 3600,
						night.server.rules.round_number,
						night.server.rules.zombies_remaining()
					]
				)
			)
		if (
			_args.has("watch")
			and ticks % int(_args.get("every", 60)) == 0
			and ticks >= int(_args.get("from", 0))
		):
			_print_seat(night, int(_args["watch"]), ticks)
		# The navigation server takes a bought door's mesh in only on a physics frame.
		if ticks % FRAME_EVERY == 0:
			await get_tree().physics_frame
	catcher.stop()
	var report := watch.report()
	report["seed"] = seed_value
	report["profile"] = String(_args.get("profile", "regular"))
	report["order"] = String(order)
	report["person"] = person
	report["reason"] = reason
	report["errors"] = catcher.lines.size()
	report["error_lines"] = catcher.lines.slice(0, 5)
	report["wall_seconds"] = snappedf(float(Time.get_ticks_msec() - began) / 1000.0, 0.1)
	# A night cut short is no failure of the gates it did not reach, but a cut by the round cap
	# is a survivor: its round is the cap.
	report["broken"] = SoakWatch.verdict(report, order, person)
	watch.night = null
	night.on_event = Callable()
	for _i in BAKE_WAIT_FRAMES:
		if not night.world.navigation.is_busy():
			break
		await get_tree().process_frame
	night.dispose()
	await get_tree().process_frame
	return report


func _print_seat(night: SeatedNight, id: int, ticks: int) -> void:
	for bot in night.host.bots:
		if bot.state.player_id != id:
			continue
		var me := bot.state.me()
		var body := night.server.body_of(id)
		var line := (
			"WATCH t=%d seat %d note=%s at=(%.1f,%.1f) v=%.1f weapon=%s ammo=%s/%s target=%d"
			% [
				ticks,
				id,
				bot.intent.note,
				body.global_position.x,
				body.global_position.z,
				Vector2(body.velocity.x, body.velocity.z).length(),
				me.get("weapon", ""),
				me.get("ammo", -1),
				me.get("reserve", -1),
				bot.intent.target_id
			]
		)
		var arms: Dictionary = night.frame["players"][id].get("arms", {})
		line += (
			" pts=%d round=%d arms=%s"
			% [night.server.rules.points_of(id), night.server.rules.round_number, str(arms)]
		)
		var zombie: ZombieBody = night.server.sim.zombies.get(bot.intent.target_id)
		if zombie != null:
			line += (" Z(%.1f,%.1f m%d)" % [zombie.position.x, zombie.position.z, zombie.mode])
		print(line)


func _profile() -> BotProfile:
	match String(_args.get("profile", "regular")):
		"rookie":
			return BotProfile.rookie()
		"veteran":
			return BotProfile.veteran()
	return BotProfile.regular()


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
