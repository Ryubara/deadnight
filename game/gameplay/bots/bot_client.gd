class_name BotClient
extends RefCounted
## A bot as a client: the thing a socket would be for a person. It hears what the server tells its
## player (through the allow-list `BotEvents`), keeps a `ClientState` of it, looks at it through
## `BotPerception`, thinks with a `BotBrain` at its own pace, turns the thought into a
## `NightCommand` with the `BotMotor`, and sends it with the one callable it was given. It owns a
## seeded random stream and a `BotProfile`, and reports through `BotTelemetry`.
##
## It is given a `ClientState`, a profile, a seed, a callable to send with, and the static level
## (`BotLevel`): no other constructor argument, and nothing of the rules, the zombies or the
## weapons server. A test fails the build if bot code names them (`docs/research/bots.md`).
##
## The `Autopilot` is the first profile (`BotProfile.autopilot()`): its `legacy` decides every tick
## from the whole frame, as it always did, and the host only sends, counts and reports it.

## Telemetry names of the brain watchdog.
const BRAIN_FAILED := &"brain_failed"
const BRAIN_DISABLED := &"brain_disabled"

var state: ClientState
var profile: BotProfile
var level: BotLevel
var rng := RandomNumberGenerator.new()
var brain: BotBrain
var perception: BotPerception
var motor: BotMotor
## The legs: the way over the mesh, giving way, and the stuck ladder (`BotLegs`).
var legs: BotLegs
var telemetry := BotTelemetry.new()
## The old bot, when the profile is the autopilot's.
var legacy: Autopilot
## False once the brain failed too often; the motor goes on with a fallback intent.
var brain_enabled := true
## The intent in force between two thinks.
var intent := BotIntent.new()
## Ticks this client has run.
var ticks := 0
## Spreads the thinks of the bots of one host over the ticks.
var slot := 0
## Seconds on this bot's own clock (the sum of the steps it was given).
var now := 0.0
## The seats that are bots, by player id: the roster labels them (a person sees `BOT` after the
## name), so a bot may know. The host fills it; the same table is shared by every bot of a night.
var bot_ids: Dictionary = {}
## What the bots of the night share (the claims on downed players): the host hands every bot the
## same one; a bot on its own has a team of its own.
var team := BotTeam.new():
	set(value):
		team = value
		if brain is BotFightBrain:
			(brain as BotFightBrain).team = value

var _send: Callable
var _step := 1.0 / 60.0
var _failures := 0
var _damage_taken := 0.0


func _init(
	p_state: ClientState, p_profile: BotProfile, bot_seed: int, p_send: Callable, p_level: BotLevel
) -> void:
	state = p_state
	profile = p_profile
	level = p_level
	_send = p_send
	rng.seed = bot_seed
	perception = BotPerception.new(profile, level, rng)
	motor = BotMotor.new(profile, rng)
	legs = BotLegs.new(level, rng)
	legs.seat = state.player_id
	var fight := BotFightBrain.new(profile, level, bot_seed ^ 0xD0D6E)
	fight.legs = legs
	fight.telemetry = telemetry
	fight.team = team
	brain = fight
	slot = state.player_id


## What the server said this tick. Only what the allow-list lets through reaches the state.
func hear(events: Array) -> void:
	var heard := BotEvents.filter(events, state.player_id)
	for i in heard.size():
		var event := heard[i]
		match event["type"]:
			&"frame":
				# Its own copy: the zombies come out of it below, and the others hear the same frame.
				heard[i] = event.duplicate()
			&"player_hurt":
				perception.hear_blow(-float(event.get("bearing", 0.0)))
				_damage_taken += float(event.get("damage", 0.0))
			&"player_added":
				# The roster labels a bot (`bot`), whoever seated it.
				if event.get("bot", false):
					bot_ids[int(event["player_id"])] = true
			&"player_removed":
				# A seat that is left holds no claim and is no bot's any more.
				team.release(int(event["player_id"]))
				bot_ids.erase(int(event["player_id"]))
			&"revive_started":
				if int(event["player_id"]) == state.player_id:
					telemetry.count(&"revive_attempts")
			&"revive_stopped":
				if int(event["player_id"]) == state.player_id and event["reason"] == &"down":
					telemetry.count(&"deaths_reviving")
			&"player_revived":
				if int(event.get("reviver_id", -1)) == state.player_id:
					telemetry.count(&"revive_successes")
			&"purchase_denied":
				perception.beliefs.denials.append(
					{"item": event.get("item_id", &""), "result": event.get("result", -1)}
				)
				telemetry.count(&"rejected_buys")
			&"purchase_made":
				telemetry.count(&"buys")
				perception.beliefs.purchased_at = now
			&"grenade_count_changed":
				perception.beliefs.grenades = int(event.get("count", 0))
			&"round_started":
				perception.beliefs.special = event.get("special_id", &"")
			&"round_ended", &"special_round_cleared":
				perception.beliefs.special = &""
	state.apply_events(heard)


## The command for this tick, not sent.
func decide(delta: float) -> NightCommand:
	ticks += 1
	now += delta
	_step = delta
	var command: NightCommand
	if not profile.filtered and legacy != null:
		command = _legacy_command(delta)
	elif not state.has_frame():
		command = NightCommand.new()
	else:
		command = _hosted_command(delta)
	command.player_id = state.player_id
	return command


## Decides and sends: one tick of this bot's life.
func tick(delta: float) -> NightCommand:
	var command := decide(delta)
	var action := command.to_dict()
	telemetry.note_command(action)
	_send.call(action)
	return command


## Whether this tick is one the bot thinks on.
func is_think_tick() -> bool:
	var period := maxi(roundi(1.0 / (float(profile.think_hz) * _step)), 1)
	return (ticks + slot) % period == 0


func damage_taken() -> float:
	return _damage_taken


# --- The old bot ---


func _legacy_command(delta: float) -> NightCommand:
	telemetry.count(&"ticks")
	return legacy.decide(delta)


# --- A hosted bot ---


func _hosted_command(delta: float) -> NightCommand:
	telemetry.count(&"ticks")
	var think := is_think_tick()
	var began := Time.get_ticks_usec()
	var spent := 0
	var me := state.me()
	perception.observe(now, think, me, state.zombies, state.round_number(), motor.yaw)
	_track_crew(delta)
	# The raw list of zombies stays behind the filter: the brain and everything after read beliefs.
	state.zombies = []
	state.frame["zombies"] = PackedByteArray()
	if think:
		_think()
	var walked := Time.get_ticks_usec()
	_walk(delta, me, not think)
	spent = Time.get_ticks_usec() - walked
	telemetry.sample(&"legs_us", float(spent))
	var command := motor.command(delta, me, intent, perception.beliefs, state.shots)
	telemetry.gauge(&"grenades_thrown", float(motor.throws))
	if think:
		# The whole decision: the look (its rays), the thought and the hands. The legs, which every
		# tick pays for, are timed on their own (`legs_us`).
		telemetry.record_think(Time.get_ticks_usec() - began - spent)
	return command


func _think() -> void:
	var answer: Variant = null
	perception.beliefs.rays = perception.rays_last
	if brain_enabled:
		answer = brain.think(perception.beliefs, state)
	if not brain_enabled:
		intent = _fallback()
	elif answer is BotIntent and (answer as BotIntent).is_sane():
		intent = answer
	else:
		_fail()
		intent = _fallback()
	(
		telemetry
		. decide(
			{
				"tick": ticks,
				"contacts": perception.beliefs.contacts.size(),
				"rays": perception.rays_last,
				"intent": intent.to_dict(),
			}
		)
	)


## A thought that came back empty or broken (a script error in a function returns nothing).
func _fail() -> void:
	_failures += 1
	telemetry.event(BRAIN_FAILED, ticks, {"failures": _failures})
	if _failures >= profile.brain_failure_limit and brain_enabled:
		brain_enabled = false
		telemetry.event(BRAIN_DISABLED, ticks)


## With no brain the motor holds where it stands and follows the nearest zombie it can see.
func _fallback() -> BotIntent:
	var safe := BotIntent.new()
	safe.note = "fallback"
	var targets := perception.beliefs.targets(state.position())
	if not targets.is_empty():
		safe.target_id = targets[0]["id"]
	return safe


# --- The other players, and the legs ---


## The players of the frame as the beliefs keep them, with how fast each one walks.
func _track_crew(delta: float) -> void:
	var beliefs := perception.beliefs
	beliefs.me = state.player_id
	var players: Dictionary = state.frame.get("players", {})
	for id: int in players:
		var player: Dictionary = players[id]
		var before: Dictionary = beliefs.teammates.get(id, {})
		var velocity := Vector3.ZERO
		if not before.is_empty():
			var moved: Vector3 = player["pos"] - before["pos"]
			moved.y = 0.0
			velocity = before["velocity"].lerp(moved / maxf(delta, 0.0001), 0.5)
		var health: float = player.get("health", 100.0)
		var hurt_at: float = before.get("hurt_at", -INF)
		if not before.is_empty() and health < float(before["health"]) - 0.5:
			hurt_at = now
		beliefs.teammates[id] = {
			"id": id,
			"pos": player["pos"],
			"facing": player.get("facing", 0.0),
			"health": health,
			"hurt_at": hurt_at,
			"downed": player.get("downed", false),
			"dead": player.get("dead", false),
			"bot": bot_ids.has(id),
			"velocity": velocity,
			"bleed": player.get("bleed", 0.0),
			"reviver": player.get("reviver", 0),
			"revive": player.get("revive", 0.0),
		}
	for id: int in beliefs.teammates.keys():
		if not players.has(id):
			beliefs.teammates.erase(id)


## The legs turn the intent into a way to walk; the motor sends it.
func _walk(delta: float, me: Dictionary, may_query: bool) -> void:
	var beliefs := perception.beliefs
	var crew: Array[Dictionary] = []
	for id in beliefs.teammates:
		if id != state.player_id:
			crew.append(beliefs.teammates[id])
	legs.note_doors(state.frame.get("doors", []).size(), now)
	var here: Vector3 = me.get("pos", Vector3.ZERO)
	var threat := beliefs.nearest_threat(here, profile.memory_seconds)
	var asked := legs.path.queries
	legs.step(delta, now, me, intent, crew, threat, may_query)
	intent.wish = legs.wish
	intent.sprint = legs.sprint
	intent.jump = legs.jump
	intent.pace = legs.pace
	if legs.path.queries != asked:
		telemetry.count(&"path_queries", legs.path.queries - asked)
	_report_legs()
	_nearest_human(here, crew)


func _report_legs() -> void:
	var stuck := legs.stuck
	telemetry.gauge(&"stuck_seconds", stuck.stuck_seconds)
	telemetry.gauge(&"walking_seconds", stuck.walking_seconds)
	telemetry.gauge(&"longest_stuck", stuck.longest())
	telemetry.gauge(&"ladder_depth_max", float(stuck.depth_max))
	telemetry.gauge(&"yielded_seconds", legs.yielded_seconds)
	telemetry.gauge(&"blocking_seconds", legs.blocking_seconds)
	telemetry.gauge(&"unreachable_goals", float(legs.path.unreachable_marks))
	telemetry.gauge(&"path_queries", float(legs.path.queries))
	telemetry.gauge(&"path_empty", float(legs.path.empty_answers))
	if stuck.report_due:
		stuck.reported()
	var report := legs.take_report()
	if not report.is_empty():
		report["decisions"] = telemetry.recent().slice(-BotLegs.REPORT_DECISIONS)
		telemetry.event(&"bot_stuck", ticks, report)


## Once a think: how far the nearest person is.
func _nearest_human(here: Vector3, crew: Array[Dictionary]) -> void:
	if not is_think_tick():
		return
	var best := INF
	for other in crew:
		if not other.get("bot", false) and not other.get("dead", false):
			best = minf(best, Vector2(other["pos"].x - here.x, other["pos"].z - here.z).length())
	if best < INF:
		telemetry.sample(&"distance_to_human", best)
