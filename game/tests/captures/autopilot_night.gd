extends Node
## Plays a night with the autopilot, for captures and for watching its numbers. Not part of the
## game. Arguments after `--`: `--rounds=N` (stop once round N has started, default 3),
## `--speed=N` (ticks per frame), `--seed=N`, `--seconds=S` (stop after S game seconds),
## `--log` (print every event), `--fast` (quick dead for a recording), `--trace`,
## `--shoulder` (film through the bot's own shoulder camera), `--cheap` (a cheap door and shotgun
## and no rounds in the pistol's reserve, so a short run shows the bot shopping).

## Real seconds the audio mixer gets to drop stopped voices before the program quits.
const QUIT_SETTLE_SECONDS := 0.3
## Frames the program waits for the navigation bake a door started before it quits.
const BAKE_WAIT_FRAMES := 600

var _args := {}
var _night: Night
var _ticks := 0
var _last_round := 0
var _hud: Hud


func _ready() -> void:
	_args = _parse_args()
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate()
	layer.add_child(_hud)
	_night = Night.new()
	_night.hud = _hud
	add_child(_night)
	_night.ticks_per_frame = int(_args.get("speed", 1))
	_night.shoulder_camera = _args.has("shoulder")
	await _night.start(Night.Mode.AUTOPILOT, int(_args.get("seed", Night.SEED)), _tuning())
	if _args.has("cheap"):
		_night.server.combat.state_of(1, &"pistol").reserve = 0
	_night.ticked.connect(_on_tick)
	if _args.has("log"):
		_night.state.event_received.connect(_print_event)


## `--fast`: the dead walk faster, so a short recording meets them.
func _tuning() -> RulesTuning:
	if not _args.has("fast") and not _args.has("cheap"):
		return null
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	if _args.has("fast"):
		tuning.rounds.speed_base = 2.2
		tuning.rounds.first_spawn_delay = 0.5
		tuning.rounds.intro_seconds = 3.0
	if _args.has("cheap"):
		tuning.economy.item(&"door_concession").price = 250
		tuning.economy.item(&"weapon_shotgun").price = 150
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
	# A bake the last door bought started runs on a worker thread, and quitting under it kills the
	# engine (`corrupted size vs. prev_size in fastbins`, exit 134): let it land first.
	for _i in BAKE_WAIT_FRAMES:
		if not _night.world.navigation.is_busy():
			break
		await get_tree().process_frame
	# A voice stopped in the same moment the engine quits is still queued in the audio server, and
	# its stream is reported as a leak at exit; let the mixer take the stopped voices off first.
	Audio.stop_all()
	await get_tree().create_timer(QUIT_SETTLE_SECONDS).timeout
	get_tree().quit()


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
