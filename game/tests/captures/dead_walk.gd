extends Node
## A person runs laps of the lot through a night the bots fight (#914): how the dead meet the body
## of  someone who does not steer round them. The person is a `HumanWalker` (a straight run along
## the navigation path, sprinting, never stopping to shoot) at seat 1, and three bots hold the lot;
## the numbers are the person's: laps and their time, seconds held by the dead, traps, seconds the
## walker stood still with somewhere to go.
##
## `godot --headless --path game res://tests/captures/dead_walk.tscn --fixed-fps 60 -- --dead=timed
## --seed=1 --nights=2 --minutes=6 --bots=3` Arguments: `--dead=off|hard|timed|wade|ramp` (as
## `bots_soak.gd`), `--seen=0`, `--seed=S` (night n uses S + n), `--nights=N`, `--minutes=M` (game
## minutes after the first round starts), `--bots=N`, `--sprint=0` (run, not sprint). Prints
## `DEADWALK {json}` for each night.

const STEP := Night.STEP
const PERSON := 1
const FRAME_EVERY := 30
## Seconds the walker stood still with somewhere to go that count as a stall.
const STALL := 1.0

var _args := {}


func _ready() -> void:
	_args = _parse_args()
	var first := int(_args.get("seed", 1))
	for n in int(_args.get("nights", 2)):
		var report := await _night(first + n)
		print("DEADWALK ", JSON.stringify(report))
	get_tree().quit()


func _night(seed_value: int) -> Dictionary:
	var began := Time.get_ticks_msec()
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	var night := await SeatedNight.start(
		self, 1 + int(_args.get("bots", 3)), tuning, seed_value, true
	)
	_set_dead(night)
	var walker := night.human(PERSON)
	walker.sprint = String(_args.get("sprint", "1")) != "0"
	night.server.rules.apply(RulesAction.grant_points(PERSON, 0))
	for i in int(_args.get("bots", 3)):
		night.seat(PERSON + 1 + i, BotProfile.regular(), 1000 + 100 * seed_value + i)
	var hurt := [0.0, 0]
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"player_damaged" and event["player_id"] == PERSON:
			hurt[0] += float(event["damage"])
			hurt[1] += 1
	var stats := DeadStats.new(night)
	stats.only = [PERSON]
	# Four spots of the lot's open field, a lap of about 150 m.
	var marks: Array[Vector3] = [
		Vector3(-30.0, 0.0, -30.0),
		Vector3(30.0, 0.0, -30.0),
		Vector3(30.0, 0.0, -15.0),
		Vector3(-30.0, 0.0, -15.0),
	]
	if _args.has("marks"):
		for i in marks.size():
			print("MARK ", i, marks[i])
		for spot in night.world.shop_spots():
			print("MARK shop ", spot["kind"], spot["position"])
		print("MARK zombie ", night.world.spawn_points().slice(0, 6))
	night.start_round()
	var lap_marks := 0
	var lap_began := 0
	var laps: Array[float] = []
	var ticks := 0
	var stall_run := 0.0
	var stalls := 0
	var stalled_seconds := 0.0
	var limit := int(float(_args.get("minutes", 6)) * 3600.0)
	var down_ticks := 0
	walker.goto(marks[0])
	while ticks < limit and night.server.rules.phase != GameRules.Phase.OVER:
		night.tick()
		walker.tick()
		stats.tick()
		ticks += 1
		var player: PlayerState = night.server.rules.players[PERSON]
		if player.downed:
			down_ticks += 1
		if walker.arrived():
			lap_marks += 1
			if lap_marks % marks.size() == 0:
				laps.append(float(ticks - lap_began) * STEP)
				lap_began = ticks
			walker.goto(marks[lap_marks % marks.size()])
		if player.downed:
			walker.stalled = 0.0
		if walker.stalled >= STALL:
			stalled_seconds += STEP
			if stall_run < STALL:
				stalls += 1
				if _args.has("stalls"):
					var nearest := INF
					for zombie: ZombieBody in night.server.sim.zombies.values():
						nearest = minf(nearest, zombie.position.distance_to(walker.position()))
					print(
						(
							"STALL t=%.0f at=%s goal=%s nearest=%.2f dead_ids=%s downed=%s dead=%s hp=%.0f"
							% [
								float(ticks) / 60.0,
								walker.position().snappedf(0.1),
								walker.goal,
								nearest,
								night.server.dead_field_of(PERSON).ids.size(),
								player.downed,
								night.server.rules.is_dead(PERSON),
								player.health,
							]
						)
					)
			stall_run = walker.stalled
		else:
			stall_run = 0.0
		if _args.has("trace") and ticks % 300 == 0:
			print(
				(
					"TRACE t=%d walker=%s goal=%s stalled=%.1f"
					% [ticks / 60, walker.position().snappedf(0.1), walker.goal, walker.stalled]
				)
			)
		if ticks % FRAME_EVERY == 0:
			await get_tree().physics_frame
	var report := stats.report()
	report["seed"] = seed_value
	report["dead_variant"] = String(_args.get("dead", "timed"))
	report["laps"] = laps.size()
	report["lap_seconds"] = snappedf(_mean(laps), 0.1)
	report["stalls"] = stalls
	report["stalled_seconds"] = snappedf(stalled_seconds, 0.1)
	report["down_seconds"] = snappedf(float(down_ticks) * STEP, 0.1)
	report["round"] = night.server.rules.round_number
	report["downs"] = night.server.rules.downs_of(PERSON)
	report["damage"] = snappedf(hurt[0], 0.1)
	report["blows"] = hurt[1]
	night.on_event = Callable()
	report["wall_seconds"] = snappedf(float(Time.get_ticks_msec() - began) / 1000.0, 0.1)
	for _i in 600:
		if not night.world.navigation.is_busy():
			break
		await get_tree().process_frame
	night.dispose()
	await get_tree().process_frame
	return report


func _set_dead(night: SeatedNight) -> void:
	var tuning := night.server.dead_tuning
	match String(_args.get("dead", "timed")):
		"off":
			tuning.enabled = false
		"hard":
			tuning.policy = DeadContactTuning.Policy.TIMED
			tuning.hold_seconds = 1.0e6
		"straight":
			tuning.lateral = 0.0
		"wade":
			tuning.policy = DeadContactTuning.Policy.WADE
		"ramp":
			tuning.policy = DeadContactTuning.Policy.RAMP
			tuning.hold_seconds = 0.3
		_:
			tuning.policy = DeadContactTuning.Policy.TIMED
	night.server.dead_as_seen = String(_args.get("seen", "1")) != "0"


static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
