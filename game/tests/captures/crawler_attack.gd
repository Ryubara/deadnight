extends Node
## A crawler attacks the player in the real night, filmed through the player's own camera (#971).
## The night is the real one (spawn, director, codec, horde, the sim's own swing); only the
## crawler's first place is set, a few metres in front of the player, who stands still and takes
## the blows.
## Arguments after `--`: `--seed=N`, `--seconds=S` (default 7), `--distance=M` (default 3.8),
## `--side=M` (default 2), `--stagger` (a hit every 2.5 s), `--die=S` (it dies S seconds in),
## `--debug`.

var _args := {}
var _night: Night
var _ticks := 0
var _placed := false


func _ready() -> void:
	_args = _parse_args()
	_night = Night.new()
	_night.shoulder_camera = true
	add_child(_night)
	await _night.start(Night.Mode.AUTOPILOT, int(_args.get("seed", 5)), _tuning())
	# The player's camera stays; nothing plays the player.
	_night.mode = Night.Mode.MANUAL
	_night.ticked.connect(_on_tick)
	_night.server.rules.apply(RulesAction.skip_break())


func _tuning() -> RulesTuning:
	var tuning := NightFixture.only_tuning(&"crawler")
	tuning.health.max_health *= 4.0
	return tuning


func _on_tick() -> void:
	_ticks += 1
	if not _placed:
		for body: ZombieBody in _night.server.sim.zombies.values():
			if body.profile.type == &"crawler" and body.is_alive():
				_placed = true
				# In front of the player, along where the player's camera looks, facing the player.
				var forward := -get_viewport().get_camera_3d().global_transform.basis.z
				forward = Vector3(forward.x, 0.0, forward.z).normalized()
				var player_at := _night.state.position()
				# A little to the right of the line, so the player's body does not hide the blow.
				var right := forward.cross(Vector3.UP)
				var at := (
					player_at
					+ forward * float(_args.get("distance", 3.8))
					+ right * float(_args.get("side", 2.0))
				)
				body.position = Vector3(at.x, body.position.y, at.z)
				if _args.has("debug"):
					var cam := get_viewport().get_camera_3d()
					print(
						"PLACED cam ",
						cam.global_position,
						" fwd ",
						forward,
						" player ",
						player_at,
						" at ",
						at,
						" screen ",
						cam.unproject_position(at)
					)
				body.yaw = atan2(player_at.x - at.x, player_at.z - at.z)
				body.velocity = Vector3.ZERO
				body.enter(ZombieBody.Mode.CHASE)
				break
	if _args.has("stagger") and _placed and _ticks % 150 == 0:
		# A hit that does not kill: the crawler's stagger, for the clip it plays.
		for id: int in _night.server.sim.zombies:
			_night.server.sim.react_to_hit(id)
	if _args.has("die") and _placed and _ticks == roundi(float(_args["die"]) * 60.0):
		# The rules' kill: it falls where it is.
		for id: int in _night.server.sim.zombies:
			_night.server.sim.begin_death(id)
	if _ticks % 60 == 0 and _args.has("debug"):
		var rows := []
		for body: ZombieBody in _night.server.sim.zombies.values():
			rows.append([body.profile.type, body.mode, body.position, body.mode_time])
		print(
			"T ",
			_ticks / 60,
			" phase ",
			_night.server.rules.phase,
			" player ",
			_night.state.position(),
			" ",
			rows
		)
	if float(_ticks) / 60.0 >= float(_args.get("seconds", 7.0)):
		get_tree().quit()


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
