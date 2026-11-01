extends Node
## A line-up of the zombie types in the real night, for captures. Not part of the game. The night
## is the real one (the rules' spawn requests, the director, the codec, the horde); only the
## zombies' positions are held in a row in front of the camera so every type is in frame at once.
## Arguments after `--`: `--scene=types|boss|cripple`, `--seed=N`.
##
## types: round 1 with every type in it (walker, runner, brute, crawler).
## boss: the shipped boss night as round 1: a headliner among walkers.
## cripple: a walker takes a grenade blast on the legs and becomes a crawler.

const SPACING := 1.5
const ROW_Z := -4.0
const SECONDS := {"types": 7.0, "boss": 9.0, "cripple": 6.0}

var _args := {}
var _night: Night
var _ticks := 0
var _victim := -1


func _ready() -> void:
	_args = _parse_args()
	var scene := String(_args.get("scene", "types"))
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.AUTOPILOT, int(_args.get("seed", 5)), _tuning(scene))
	# The line-up is posed, not played: the bot sends nothing and the camera stays where it is.
	_night.mode = Night.Mode.MANUAL
	_night.ticked.connect(_on_tick)
	_night.server.rules.apply(RulesAction.skip_break())


func _tuning(scene: String) -> RulesTuning:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.first_spawn_delay = 0.3
	tuning.rounds.spawn_interval_start = 0.3
	tuning.rounds.speed_base = 1.6
	if scene == "boss":
		tuning.specials.first_round = 1
		tuning.specials.every = 1
		tuning.rounds.count_base = 14.0
		return tuning
	if scene == "cripple":
		tuning.rounds.count_base = 3.0
		return tuning
	tuning.rounds.count_base = 6.0
	for type in tuning.roster.types:
		if type.id in [&"runner", &"crawler", &"brute"]:
			type.first_round = 1
			type.intro_count = 2 if type.id == &"crawler" else 1
	return tuning


func _on_tick() -> void:
	_ticks += 1
	var zombies: Array[ZombieBody] = []
	for body: ZombieBody in _night.server.sim.zombies.values():
		if body.is_alive():
			zombies.append(body)
	# Biggest first, so the types in the middle stand out; the order is the type and then the id.
	zombies.sort_custom(
		func(a: ZombieBody, b: ZombieBody) -> bool:
			if a.profile.type != b.profile.type:
				return str(a.profile.type) < str(b.profile.type)
			return a.id < b.id
	)
	var origin := _night.state.position()
	var first := -0.5 * SPACING * float(zombies.size() - 1)
	for index in zombies.size():
		var body := zombies[index]
		var spot := origin + Vector3(first + SPACING * index, 0.0, ROW_Z)
		body.position = Vector3(spot.x, body.position.y, spot.z)
		body.yaw = 0.0
		body.velocity = Vector3.ZERO
		if body.mode == ZombieBody.Mode.ATTACK:
			body.enter(ZombieBody.Mode.CHASE)
	if String(_args.get("scene", "")) == "cripple":
		_cripple(zombies)
	_follow_camera()
	if _ticks / 60.0 >= float(SECONDS[String(_args.get("scene", "types"))]):
		get_tree().quit()


func _cripple(zombies: Array[ZombieBody]) -> void:
	if _victim == -1 and _ticks > 150 and not zombies.is_empty():
		_victim = zombies[0].id
		var health := _night.server.rules.zombie_health(_victim)
		var blast := {"zombie_id": _victim, "damage": health * 0.3, "leg_damage": health * 0.3}
		_night.state.apply_events(_night.server.rules.apply(RulesAction.explosion(1, [blast])))


func _follow_camera() -> void:
	var camera: Camera3D = _night.get("_spectator")
	var at := _night.state.position()
	camera.look_at_from_position(at + Vector3(0.0, 3.6, ROW_Z + 7.0), at + Vector3(0.0, 0.9, ROW_Z))


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
