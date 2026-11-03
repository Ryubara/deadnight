extends Node
## How the dead's swings land: hosted bots play a night on the first or the second map and what the
## zombies did at close range is printed. A swing is a zombie entering its ATTACK mode away from a
## breach; it lands when the rules answer with `player_hurt` (the server turns the sim's
## `zombie_struck` into it). Also the distance from the target at which swings begin, and the ticks
## a zombie spent within reach of its target without swinging (a swing it was not let begin).
## `--ray=body` gives the sim the ray that meets a player's body (the old swing check),
## `--ray=walls` the walls-only ray (`WorldProbe.static_callable`, the shipped one), to compare the
## two on the same night.
##
## `godot --headless --path game res://tests/captures/swing_rate.tscn --
##   --map=first|second --bots=4 --rounds=4 --ray=body|walls`
## Arguments after `--`: `--seed=N`, `--tough=X` (every player's health as a multiple of the
## shipped, default 4 so the bots live to take many swings), `--profile=mixed|regular|veteran|
## rookie`.
## Prints `SWING {json}` at the end.

const SMALL := "res://world/smallmap/smallmap_greybox.tscn"
const FRAME_EVERY := 30

var _args := {}
var _night: SeatedNight
var _modes: Dictionary = {}
var _begun := 0
var _landed := 0
var _onsets: Array[float] = []
var _waiting_ticks := 0
var _near_ticks := 0
var _damage := 0
var _downs := 0
var _ends: Dictionary = {}


func _ready() -> void:
	_args = _parse_args()
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.health.max_health *= float(_args.get("tough", 4.0))
	var seed_value := int(_args.get("seed", 1))
	var count := int(_args.get("bots", 4))
	var scene: PackedScene = load(SMALL) if String(_args.get("map", "first")) == "second" else null
	_night = await SeatedNight.start(self, count, tuning, seed_value, true, scene)
	var profiles := _profiles(count)
	for i in profiles.size():
		_night.seat(i + 1, profiles[i], 1000 + 100 * seed_value + i)
	_night.on_event = _on_event
	var probe: WorldProbe = _night.server._probe
	_night.server.sim.sight = (
		probe.static_callable() if String(_args.get("ray", "body")) == "walls" else probe.callable()
	)
	_night.start_round()
	var target_round := int(_args.get("rounds", 4))
	var limit := int(float(_args.get("minutes", 30)) * 3600.0)
	var ticks := 0
	while ticks < limit and _night.server.rules.phase != GameRules.Phase.OVER:
		_night.tick()
		ticks += 1
		_watch()
		if ticks % FRAME_EVERY == 0:
			await get_tree().physics_frame
		if _ends.has(target_round):
			break
	_report(ticks)
	_night.dispose()
	await get_tree().process_frame
	get_tree().quit()


func _watch() -> void:
	var reach := _night.server.sim.tuning.reach
	for id: int in _night.server.sim.zombies:
		var zombie: ZombieBody = _night.server.sim.zombies[id]
		var before: int = _modes.get(id, ZombieBody.Mode.EMERGING)
		_modes[id] = zombie.mode
		var body := _night.server.body_of(zombie.target_id)
		if body == null:
			continue
		var flat := (
			Vector2(
				zombie.position.x - body.global_position.x,
				zombie.position.z - body.global_position.z
			)
			. length()
		)
		var same_height := absf(zombie.position.y - body.global_position.y) < 1.0
		if (
			zombie.mode == ZombieBody.Mode.ATTACK
			and before != ZombieBody.Mode.ATTACK
			and not zombie.tearing
		):
			_begun += 1
			_onsets.append(flat)
		if zombie.mode == ZombieBody.Mode.CHASE and same_height and flat <= reach:
			_waiting_ticks += 1
		if same_height and flat <= reach:
			_near_ticks += 1


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"player_hurt":
			_landed += 1
			_damage += int(event["damage"])
		&"player_downed":
			_downs += 1
		&"round_ended":
			_ends[event["round"]] = true


func _report(ticks: int) -> void:
	_onsets.sort()
	var median := _onsets[_onsets.size() / 2] if not _onsets.is_empty() else -1.0
	var mean := 0.0
	for d in _onsets:
		mean += d
	mean = mean / maxf(1.0, float(_onsets.size()))
	var result := {
		"map": String(_args.get("map", "first")),
		"ray": String(_args.get("ray", "body")),
		"seed": int(_args.get("seed", 1)),
		"bots": int(_args.get("bots", 4)),
		"ticks": ticks,
		"round": _night.server.rules.round_number,
		"swings_begun": _begun,
		"swings_landed": _landed,
		"landing_rate": snappedf(float(_landed) / maxf(1.0, float(_begun)), 0.001),
		"onset_median_m": snappedf(median, 0.01),
		"onset_mean_m": snappedf(mean, 0.01),
		"ticks_in_reach_not_swinging": _waiting_ticks,
		"ticks_in_reach": _near_ticks,
		"damage_taken": _damage,
		"downs": _downs,
	}
	print("SWING ", JSON.stringify(result))


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


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
