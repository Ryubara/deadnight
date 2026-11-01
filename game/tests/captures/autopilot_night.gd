extends Node
## Plays a night with the autopilot, for captures and for watching its numbers. Not part of the
## game. Arguments after `--`: `--rounds=N` (stop once round N has started, default 3),
## `--speed=N` (ticks per frame), `--seed=N`, `--seconds=S` (stop after S game seconds),
## `--log` (print every event), `--fast` (quick dead for a recording), `--trace`.

var _args := {}
var _night: Night
var _ticks := 0
var _last_round := 0


func _ready() -> void:
	_args = _parse_args()
	_night = Night.new()
	add_child(_night)
	_night.ticks_per_frame = int(_args.get("speed", 1))
	await _night.start(Night.Mode.AUTOPILOT, int(_args.get("seed", Night.SEED)), _tuning())
	_night.ticked.connect(_on_tick)
	if _args.has("log"):
		_night.state.event_received.connect(_print_event)


## `--fast`: the dead walk faster, so a short recording meets them.
func _tuning() -> RulesTuning:
	if not _args.has("fast"):
		return null
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.speed_base = 2.2
	tuning.rounds.first_spawn_delay = 0.5
	tuning.rounds.intro_seconds = 3.0
	return tuning


func _print_event(event: Dictionary) -> void:
	if event["type"] != &"frame":
		print(event)


func _on_tick() -> void:
	if not _night.running:
		if _night.state.over:
			_report()
		return
	_ticks += 1
	var state := _night.state
	if _args.has("trace") and _ticks % 60 == 0:
		var near := []
		for z in state.zombies:
			near.append("%d:%s/%d" % [z["id"], z["position"].snappedf(0.1), z["mode"]])
		print(
			(
				"pos=%s hp=%.0f ammo=%s/%s zombies=%s"
				% [
					state.position().snappedf(0.1),
					state.me().get("health", 0),
					state.me().get("ammo"),
					state.me().get("reserve"),
					near
				]
			)
		)
	if state.round_number() != _last_round:
		_last_round = state.round_number()
		print(
			(
				"t=%.0fs round %d points %d kills %d"
				% [_ticks / 60.0, _last_round, state.points(), state.kills]
			)
		)
	var done := (
		state.rounds_started >= int(_args.get("rounds", 3))
		and state.phase() == GameRules.Phase.BREAK
	)
	if done or (_args.has("seconds") and _ticks / 60.0 >= float(_args["seconds"])):
		_report()


func _report() -> void:
	var s := _night.state
	var line := "REPORT ticks=%d round=%d kills=%d shots=%d earned=%d spent=%d doors=%d"
	line += " damage_taken=%.0f over=%s"
	print(
		(
			line
			% [
				_ticks,
				s.round_number(),
				s.kills,
				s.shots,
				s.points_earned,
				s.points_spent,
				s.doors_bought,
				s.damage_taken,
				s.over
			]
		)
	)
	_night.running = false
	get_tree().quit()


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
