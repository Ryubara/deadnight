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
	brain = BotFightBrain.new(profile, level)
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
	var me := state.me()
	perception.observe(now, think, me, state.zombies, state.round_number(), motor.yaw)
	# The raw list of zombies stays behind the filter: the brain and everything after read beliefs.
	state.zombies = []
	state.frame["zombies"] = PackedByteArray()
	if think:
		_think()
	var command := motor.command(delta, me, intent, perception.beliefs, state.shots)
	if think:
		# The whole decision: the look (its rays), the thought and the hands.
		telemetry.record_think(Time.get_ticks_usec() - began)
	return command


func _think() -> void:
	var answer: Variant = null
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
