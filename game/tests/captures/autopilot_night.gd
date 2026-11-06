extends Node
## Plays a night with the autopilot, for captures and for watching its numbers. Not part of the
## game. Arguments after `--`: `--rounds=N` (stop once round N has started, default 3),
## `--speed=N` (ticks per frame), `--seed=N`, `--seconds=S` (stop after S game seconds),
## `--log` (print every event), `--fast` (quick dead for a recording), `--trace`,
## `--count`, `--max-alive`, `--break` (the match settings, see MatchSettings),
## `--shoulder` (film through the bot's own shoulder camera), `--cheap` (a cheap door and shotgun
## and no rounds in the pistol's reserve, so a short run shows the bot shopping), `--pinned` (the
## stall of #1351: the booth's door open, both guns empty, the bot in the booth's corner with the
## first zombie in the wall beside it).

## Frames the program waits for the navigation bake a door started before it quits.
const BAKE_WAIT_FRAMES := 600

var _args := {}
var _night: Night
var _ticks := 0
var _last_round := 0
var _hud: Hud


func _ready() -> void:
	_args = _parse_args()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate()
	layer.add_child(_hud)
	_night = Night.new()
	_night.hud = _hud
	_night.match_settings = _match_settings()
	add_child(_night)
	_night.ticks_per_frame = int(_args.get("speed", 1))
	_night.shoulder_camera = _args.has("shoulder")
	await _night.start(Night.Mode.AUTOPILOT, int(_args.get("seed", Night.SEED)), _tuning())
	if _args.has("cheap"):
		_night.server.combat.state_of(1, &"pistol").reserve = 0
	if _args.has("pinned"):
		await _prepare_pin()
	_night.ticked.connect(_on_tick)
	if _args.has("log"):
		_night.state.event_received.connect(_print_event)


## The stall of the nightly (#1351), set up: both booth doors paid for, the bot's guns empty with
## 950 points left, and, when the first zombie is on the lot, the bot in the booth's north-east
## corner with that zombie in the wall at its elbow, attacking through it.
func _prepare_pin() -> void:
	var rules := _night.server.rules
	var price := 0
	for door_id in [&"door_concession", &"door_booth"]:
		price += _night.rules_tuning.economy.item(door_id).price
	rules.apply(RulesAction.grant_points(1, price + 950))
	for door_id in [&"door_concession", &"door_booth"]:
		RulesFixture.buy(rules, 1, door_id)
	await NightFixture.settle_bake(_night)
	_night.server.combat.apply(CombatAction.give_weapon(1, &"shotgun"))
	_night.server.combat.apply(CombatAction.equip(1, &"shotgun"))
	for id: StringName in [&"shotgun", WeaponCatalog.START_WEAPON]:
		var gun := _night.server.combat.state_of(1, id)
		gun.ammo = 0
		gun.reserve = 0
	var zombie_id := NightFixture.first_zombie(_night)
	_night.server.body_of(1).teleport(Vector3(5.45, 0.1, 22.6))
	var zombie: ZombieBody = _night.server.sim.zombies[zombie_id]
	zombie.position = Vector3(4.7, -0.1, 22.1)
	zombie.enter(ZombieBody.Mode.ATTACK)


## `--count=N`, `--max-alive=N`, and `--break=S`: the match settings of the night.
func _match_settings() -> MatchSettings:
	var settings := MatchSettings.new()
	settings.count_multiplier = float(_args.get("count", 1.0))
	settings.max_alive = int(_args.get("max-alive", 0))
	settings.break_seconds = float(_args.get("break", 0.0))
	return settings.clamped()


## `--fast`: the dead walk faster, so a short recording meets them.
func _tuning() -> RulesTuning:
	if not _args.has("fast") and not _args.has("cheap") and not _args.has("pinned"):
		return null
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	if _args.has("pinned"):
		# As the nightly: the dead cannot kill the bot, so the stall is a stand-still, not a death.
		tuning.health.max_health = AutopilotRun.PLAYER_HEALTH
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
	# The night's sound players keep scheduled sounds (a shot's tail, a reload's steps) that start
	# a moment later: free the night first, so nothing starts a voice after the audio is stopped.
	_night.queue_free()
	await _night.tree_exited
	# A voice stopped in the same moment the engine quits is still queued in the audio server, and
	# its stream is reported as a leak at exit; wait for the mixer to take the stopped voices off,
	# counting its steps (a loaded machine delays them by any amount of real time).
	Audio.stop_all()
	await Audio.wait_for_mixer()
	get_tree().quit()


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
