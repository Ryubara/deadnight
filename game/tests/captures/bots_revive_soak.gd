extends Node
## The revive soak of the bots plan (phase 5): hosted bots alone in the lot (no person) play a night
## against the real zombie mix, and what they did about each other's falls is printed: per bot the
## revive attempts, successes, holds let go of, deaths at a revive, downs, the callout lines, and
## for the team the most bots on an errand at once and how long two or more were. A local or nightly
## measurement, not a test (`tests/night/test_bot_revive.gd` holds the scenarios).
##
## `godot --headless --path game res://tests/captures/bots_revive_soak.tscn
##   -- --seed=1 --minutes=10`
## Arguments after `--`: `--seed=N`, `--minutes=M` (game minutes), `--bots=N` (default 4),
## `--parallel` (the errands do not wait for a turn: what the turn costs),
## `--human` (a stand-in person at seat 1 stands in the lot: the bots stay with it and raise it),
## `--tough=X` (every player's health, a multiple of the shipped),
## `--profile=rookie|regular|veteran|mixed` (default mixed), `--trace` (a line every 15 s),
## `--forced=S` (every S game seconds a seeded pick of the players on their feet is put on the
## ground while at least two others stand, so the revive is tried often, in the real fight),
## `--flares=1` (every bot starts with the flare gun beside its pistol; the soak that measures the
## flare rule, #646, is run with `--flares=0` and `--flares=1` on the same seeds),
## `--log` (a line for each fall, revive, flare and death, with what each bot is doing),
## `--no-flare-rule` (the bots carry the flare gun but never fire it: the control of `--flares=1`).
## Prints `REVIVE {json}` at the end.

## Ticks between the physics frames the engine is given (a bought door needs one).
const FRAME_EVERY := 30
## Ticks between the samples of what each bot's revive rule says about the bodies on the ground.
const SAMPLE_EVERY := 6

var _args := {}
var _night: SeatedNight
var _downs: Dictionary = {}
var _raised: Dictionary = {}
var _died: Dictionary = {}
var _both_errands := 0
var _most_errands := 0
var _ticks_in_round := 0
var _rounds := 0
var _pick := RandomNumberGenerator.new()
var _forced := 0
var _last_at: Dictionary = {}
var _max_step := 0.0
var _tick := 0
var _bleeds: Array[Dictionary] = []
## Victim id to `{bot id: {why: seconds}}`, over the fall: what each bot's revive rule said about
## this body at every sample, so a bleed-out shows the whole 45 s and not only its last think.
var _tally: Dictionary = {}


func _ready() -> void:
	_args = _parse_args()
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.health.max_health *= float(_args.get("tough", 1.0))
	BotRevive.stage_on = not _args.has("no-stage")
	BotRevive.stall_on = not _args.has("no-stall")
	var seed_value := int(_args.get("seed", 1))
	var bots := int(_args.get("bots", 4))
	var people := 1 if _args.has("human") else 0
	_night = await SeatedNight.start(self, bots + people, tuning, seed_value, true)
	if people > 0:
		_night.human(1)
	var profiles := _profiles(bots)
	for i in profiles.size():
		_night.seat(people + i + 1, profiles[i], 1000 + 100 * seed_value + i)
	_night.gather()
	_night.host.team.flares = not _args.has("no-flare-rule")
	if int(_args.get("flares", 0)) > 0:
		for bot in _night.host.bots:
			var id := bot.state.player_id
			_night.server.combat.apply(CombatAction.give_weapon(id, &"flare_gun"))
			_night.server.combat.apply(CombatAction.equip(id, &"pistol"))
	_night.on_event = _on_event
	_pick.seed = seed_value
	_night.host.team.one_errand_at_a_time = not _args.has("parallel")
	_night.start_round()
	var limit := int(float(_args.get("minutes", 10)) * 60.0 * 60.0)
	var ticks := 0
	while ticks < limit and _night.server.rules.phase != GameRules.Phase.OVER:
		_night.tick()
		ticks += 1
		_tick = ticks
		if ticks % SAMPLE_EVERY == 0:
			_sample_falls()
		if (
			_args.has("probe")
			and ticks % 60 == 0
			and absf(float(ticks) / 60.0 - float(_args["probe"])) < 4.0
		):
			for bot in _night.host.bots:
				print(
					(
						"PROBE t=%d bot=%d pos=%s goal=%s r=%s wish=%s note=%s report=%s stuck=%s"
						% [
							ticks / 60,
							bot.state.player_id,
							_night.server.body_of(bot.state.player_id).global_position,
							bot.intent.goal,
							bot.intent.goal_radius,
							bot.legs.wish,
							bot.intent.note,
							bot.legs.report,
							bot.legs.stuck.longest()
						]
					)
				)
		_watch_errands()
		_watch_steps()
		var every := int(float(_args.get("forced", 0.0)) * 60.0)
		if every > 0 and ticks % every == 0 and _night.server.rules.phase == GameRules.Phase.ACTIVE:
			_put_one_down()
		if _args.has("trace") and ticks % 900 == 0:
			_trace(ticks)
		if ticks % FRAME_EVERY == 0:
			await get_tree().physics_frame
	_report(ticks)
	for _i in 600:
		if not _night.world.navigation.is_busy():
			break
		await get_tree().process_frame
	_night.dispose()
	await get_tree().process_frame
	get_tree().quit()


## The farthest a bot moved in one tick: a bot that is teleported would show.
func _watch_steps() -> void:
	for bot in _night.host.bots:
		var id := bot.state.player_id
		var at := _night.server.body_of(id).global_position
		if _last_at.has(id):
			_max_step = maxf(_max_step, (at - _last_at[id]).length())
		_last_at[id] = at


## A seeded pick of the bots on their feet goes down, if two others stay up.
func _put_one_down() -> void:
	var up: Array[int] = []
	for id: int in _night.server.rules.players:
		var player: PlayerState = _night.server.rules.players[id]
		if not player.downed and not player.dead:
			up.append(id)
	up.sort()
	if up.size() < 3:
		return
	var id := up[_pick.randi() % up.size()]
	if id == 1 and _args.has("human"):
		return
	_forced += 1
	_night.host.hear(_night.server.rules.apply(RulesAction.set_downed(id, true)))


## One line for a body that bled out: for each bot what it was doing, how far it was, and what
## `BotRevive` said about this body at its last think (verdict, claim, why it did not go).
func _sample_falls() -> void:
	for victim: int in _night.server.rules.players:
		var player: PlayerState = _night.server.rules.players[victim]
		if not player.downed or player.dead:
			_tally.erase(victim)
			continue
		var per_bot: Dictionary = _tally.get(victim, {})
		_tally[victim] = per_bot
		for bot in _night.host.bots:
			var id: int = bot.state.player_id
			var mate: PlayerState = _night.server.rules.players[id]
			if id == victim:
				continue
			var key := "down"
			if not mate.downed and not mate.dead:
				var revive := (bot.brain as BotFightBrain).revive
				var why: String = revive.account.get(victim, {}).get("why", "no_account")
				var mode: String = BotRevive.Mode.keys()[revive.mode]
				key = "%s/%s" % [why, mode]
			if key.begins_with("unsafe"):
				var shown: Dictionary = (bot.brain as BotFightBrain).revive.account[victim]
				key += "/n%d/k%d" % [shown["count"], roundi(shown["kill_s"])]
			var body := _night.server.body_of(victim).global_position
			var at := _night.server.body_of(id).global_position
			var apart := Vector2(at.x - body.x, at.z - body.z).length()
			var seconds: Dictionary = per_bot.get(id, {})
			var near_key := "closest_m"
			if not mate.downed and not mate.dead:
				seconds[near_key] = snappedf(minf(float(seconds.get(near_key, INF)), apart), 0.1)
			per_bot[id] = seconds
			seconds[key] = snappedf(float(seconds.get(key, 0.0)) + float(SAMPLE_EVERY) / 60.0, 0.1)


func _log_bleed_out(victim: int) -> void:
	var body := _night.server.body_of(victim).global_position
	var line := {
		"t": snappedf(float(_tick) / 60.0, 0.1),
		"victim": victim,
		"seconds": _tally.get(victim, {}),
		"bots": []
	}
	_tally.erase(victim)
	for bot in _night.host.bots:
		var id: int = bot.state.player_id
		if id == victim:
			continue
		var brain := bot.brain as BotFightBrain
		var rules_player: PlayerState = _night.server.rules.players[id]
		var at := _night.server.body_of(id).global_position
		(
			line["bots"]
			. append(
				{
					"bot": id,
					"state":
					"down" if rules_player.downed else ("dead" if rules_player.dead else "up"),
					"note": bot.intent.note,
					"mode": BotRevive.Mode.keys()[brain.revive.mode],
					"apart": snappedf(Vector2(at.x - body.x, at.z - body.z).length(), 0.1),
					"account": brain.revive.account.get(victim, {"why": "never_looked"}),
				}
			)
		)
	_bleeds.append(line)
	print("BLEED ", JSON.stringify(line))


func _watch_errands() -> void:
	var on := 0
	for bot in _night.host.bots:
		var brain := bot.brain as BotFightBrain
		if brain != null and brain.on_errand:
			on += 1
	_most_errands = maxi(_most_errands, on)
	if on >= 2:
		_both_errands += 1


## What each bot is doing at the moment: `seat:note/revive mode`.
func _bots_now() -> String:
	var line := ""
	for bot in _night.host.bots:
		var brain := bot.brain as BotFightBrain
		var down: bool = _night.server.rules.players[bot.state.player_id].downed
		line += (
			" %d:%s%s/%d"
			% [bot.state.player_id, "DOWN " if down else "", bot.intent.note, brain.revive.mode]
		)
	return line


func _trace(ticks: int) -> void:
	var line := (
		"TRACE t=%d round=%d remaining=%d"
		% [ticks / 60, _night.server.rules.round_number, _night.server.rules.zombies_remaining()]
	)
	for bot in _night.host.bots:
		var id := bot.state.player_id
		var at := _night.server.body_of(id).global_position
		line += (
			" | %d hp=%d%s %s (%d,%d)"
			% [
				id,
				_night.server.rules.health_of(id),
				" DOWN" if _night.server.rules.players[id].downed else "",
				bot.intent.note,
				at.x,
				at.z
			]
		)
	print(line)


func _profiles(count: int) -> Array[BotProfile]:
	var found: Array[BotProfile] = []
	var kind := String(_args.get("profile", "mixed"))
	for i in count:
		match kind:
			"rookie":
				found.append(BotProfile.rookie())
			"regular":
				found.append(BotProfile.regular())
			"veteran":
				found.append(BotProfile.veteran())
			_:
				found.append(
					[BotProfile.regular(), BotProfile.veteran(), BotProfile.rookie()][i % 3]
				)
	return found


func _on_event(event: Dictionary) -> void:
	if (
		_args.has("log")
		and (
			event["type"]
			in [
				&"player_downed",
				&"player_died",
				&"player_revived",
				&"lure_started",
				&"revive_started",
				&"revive_stopped"
			]
		)
	):
		print(
			(
				"LOG t=%.1f %s %s"
				% [float(_night.server.tick_count) / 60.0, event["type"], _bots_now()]
			)
		)
	match event["type"]:
		&"player_downed":
			_downs[event["player_id"]] = int(_downs.get(event["player_id"], 0)) + 1
		&"player_revived":
			_tally.erase(event.get("player_id", 0))
			if int(event["reviver_id"]) > 0:
				_raised[event["reviver_id"]] = int(_raised.get(event["reviver_id"], 0)) + 1
		&"player_died":
			_died[event["player_id"]] = int(_died.get(event["player_id"], 0)) + 1
			_log_bleed_out(int(event["player_id"]))
		&"round_started":
			_rounds += 1


func _report(ticks: int) -> void:
	var bots: Array[Dictionary] = []
	var attempts := 0
	var successes := 0
	var deaths := 0
	var aborts := 0
	var stalls := 0
	var flares := 0
	var wanted := 0
	var no_spot := 0
	var lines := 0
	for bot in _night.host.bots:
		var counters := bot.telemetry.counters
		lines += int(counters.get(&"callouts", 0))
		attempts += int(counters.get(&"revive_attempts", 0))
		successes += int(counters.get(&"revive_successes", 0))
		deaths += int(counters.get(&"deaths_reviving", 0))
		aborts += int(counters.get(&"revive_aborts", 0))
		stalls += int(counters.get(&"revive_stalls", 0))
		flares += int(counters.get(&"flares_fired", 0))
		wanted += int(counters.get(&"flares_wanted", 0))
		no_spot += int(counters.get(&"flares_no_spot", 0))
		(
			bots
			. append(
				{
					"seat": bot.state.player_id,
					"profile": bot.profile.title,
					"downs": int(_downs.get(bot.state.player_id, 0)),
					"attempts": int(counters.get(&"revive_attempts", 0)),
					"successes": int(counters.get(&"revive_successes", 0)),
					"aborts": int(counters.get(&"revive_aborts", 0)),
					"flares": int(counters.get(&"flares_fired", 0)),
					"deaths_reviving": int(counters.get(&"deaths_reviving", 0)),
					"callouts": int(counters.get(&"callouts", 0)),
					"trapped": int(counters.get(&"bot_trapped", 0)),
					"role": (bot.brain as BotFightBrain).role,
					"stuck_longest": snappedf(bot.legs.stuck.longest(), 0.1),
					"think_us_p99": bot.telemetry.think_us(0.99),
				}
			)
		)
	var report := {
		"seed": int(_args.get("seed", 1)),
		"game_seconds": snappedf(float(ticks) / 60.0, 0.1),
		"round": _night.server.rules.round_number,
		"over": _night.server.rules.phase == GameRules.Phase.OVER,
		"forced_downs": _forced,
		"downs": _downs,
		"raised_by": _raised,
		"bled_out": _died,
		"bled_out_total": _bleeds.size(),
		"attempts": attempts,
		"successes": successes,
		"success_share": snappedf(float(successes) / float(maxi(attempts, 1)), 0.01),
		"aborts": aborts,
		"stalls": stalls,
		"flares_fired": flares,
		"flares_wanted": wanted,
		"flares_no_spot": no_spot,
		"deaths_reviving": deaths,
		"deaths_share": snappedf(float(deaths) / float(maxi(attempts, 1)), 0.01),
		"callouts": lines,
		"callouts_per_bot_per_10s":
		snappedf(float(lines) / (float(_night.host.bots.size()) * float(ticks) / 600.0), 0.001),
		"most_on_an_errand": _most_errands,
		"max_step_m_per_tick": snappedf(_max_step, 0.01),
		"ticks_two_on_errands": _both_errands,
		"bots": bots,
	}
	print("REVIVE ", JSON.stringify(report))


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
