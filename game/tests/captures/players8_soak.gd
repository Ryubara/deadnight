extends Node
## The soak of a full room (#690): a real `NightHost` on the drive-in lot with every one of its
## eight
## seats held for a long run of game time. `--people` of the seats are clients over real
## WebSockets, each an autopilot that shops, opens doors and fights like a person; the rest are the
## server's bots (`MatchSettings.bots`). Not part of the game, and not a test: a local or CI
## measurement of whether a full room stays whole.
##
## `godot --headless --fixed-fps 60 --path game res://tests/captures/players8_soak.tscn --
##  --minutes=10 --people=3 --seed=1 --tough=50`
## Arguments after `--`: `--minutes=M` (game minutes, default 10), `--people=N` (clients, default
## 3; the bots are the other seats), `--seed=N`, `--tough=X` (every player's health, a multiple of
## the shipped: the soak measures whether the room holds, not whether it lives; default 50) and
## `--out=FILE` (the result as JSON as well). With `--fixed-fps 60` a game minute takes a fraction
## of a minute of this machine's time.
## Prints `SOAK8 {json}` at the end and quits with 1 when a seat was lost or a peer was kicked.

## Ticks between two samples of the server's cost and the room.
const SAMPLE_EVERY := 600
## A server step slower than this (milliseconds) is reported, with the game minute it came in.
const SLOW_MS := 100.0
## Frames waited for a navigation bake a door started before quitting.
const BAKE_WAIT_FRAMES := 300

var _args := {}
var _host: NightHost
var _clients: Array[Night] = []
var _ticks := 0
var _limit := 0
var _running := false
var _finished := false
var _worst_step_ms := 0.0
## Steps over `SLOW_MS` (game minute, milliseconds), the first few: what the worst step was.
var _slow: Array[String] = []
var _slow_count := 0
var _last_worst := 0.0
var _peak_zombies := 0
var _peak_round := 0
var _min_seats := 99
var _samples: Array[Dictionary] = []
var _work_at := 0.0
var _steps_at := 0
var _bytes_out_at := 0
var _bytes_in_at := 0
var _nodes_at_start := 0
var _memory_at_start := 0.0
var _seat_losses: Array[String] = []
var _began_msec := 0


func _ready() -> void:
	_args = _parse_args()
	_began_msec = Time.get_ticks_msec()
	_limit = int(float(_args.get("minutes", 10)) * 3600.0)
	var people := clampi(int(_args.get("people", 3)), 1, NightHost.MAX_PLAYERS)
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = int(_args.get("seed", 1))
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.health.max_health *= float(_args.get("tough", 50.0))
	_host.rules_tuning = tuning
	var settings := MatchSettings.new()
	settings.bots = NightHost.MAX_PLAYERS - people
	_host.match_settings = settings
	_world().add_child(_host)
	while not _host.serving:
		await get_tree().physics_frame
	for i in people:
		var night := Night.new()
		_world().add_child(night)
		var joined := await night.start_remote(
			"ws://127.0.0.1:%d" % _host.listener.port(), Night.Mode.AUTOPILOT, 60.0
		)
		if not joined:
			push_error("client %d could not join" % (i + 1))
			get_tree().quit(1)
			return
		_clients.append(night)
	for _i in 120:
		await get_tree().physics_frame
	_nodes_at_start = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_memory_at_start = OS.get_static_memory_usage() / 1048576.0
	_work_at = _host.work_ms
	_steps_at = _host.steps
	_bytes_out_at = _host.listener.bytes_out
	_bytes_in_at = _host.listener.bytes_in
	_running = true


func _physics_process(_delta: float) -> void:
	if not _running or _finished:
		return
	_ticks += 1
	_worst_step_ms = maxf(_worst_step_ms, _host.worst_ms)
	if _host.worst_ms > SLOW_MS and _host.worst_ms != _last_worst:
		_slow_count += 1
		if _slow.size() < 10:
			_slow.append("%.2f min: %.0f ms" % [float(_ticks) * Night.STEP / 60.0, _host.worst_ms])
	_last_worst = _host.worst_ms
	var seats := _host.player_count() + _host.bots.count()
	_min_seats = mini(_min_seats, seats)
	if seats != NightHost.MAX_PLAYERS:
		_seat_losses.append("tick %d: %d seats" % [_ticks, seats])
	_peak_zombies = maxi(_peak_zombies, _host.server.rules.zombie_ids().size())
	_peak_round = maxi(_peak_round, _host.server.rules.round_number)
	if _ticks % SAMPLE_EVERY == 0:
		_sample()
	if _ticks >= _limit or _host.server.rules.phase == GameRules.Phase.OVER:
		_finish("over" if _host.server.rules.phase == GameRules.Phase.OVER else "time")


func _sample() -> void:
	var steps := _host.steps - _steps_at
	var seconds := float(steps) * Night.STEP
	(
		_samples
		. append(
			{
				"minute": snappedf(float(_ticks) * Night.STEP / 60.0, 0.1),
				"round": _host.server.rules.round_number,
				"zombies": _host.server.rules.zombie_ids().size(),
				"step_ms_mean": snappedf((_host.work_ms - _work_at) / maxf(steps, 1), 0.01),
				"down_bytes_per_s_per_person":
				roundi(
					(
						float(_host.listener.bytes_out - _bytes_out_at)
						/ seconds
						/ maxf(_clients.size(), 1)
					)
				),
				"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				"memory_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
			}
		)
	)
	_work_at = _host.work_ms
	_steps_at = _host.steps
	_bytes_out_at = _host.listener.bytes_out


func _finish(why: String) -> void:
	_finished = true
	var result := {
		"ended": why,
		"game_minutes": snappedf(float(_ticks) * Night.STEP / 60.0, 0.1),
		"wall_seconds": snappedf(float(Time.get_ticks_msec() - _began_msec) / 1000.0, 0.1),
		"people": _clients.size(),
		"bots": _host.bots.count(),
		"seats_held_min": _min_seats,
		"seat_losses": _seat_losses.slice(0, 5),
		"kicked": _host.kicked_count,
		"rounds_reached": _peak_round,
		"zombies_peak": _peak_zombies,
		"worst_step_ms": snappedf(_worst_step_ms, 0.1),
		"steps_over_100ms": _slow_count,
		"slow_steps": _slow,
		"nodes_start": _nodes_at_start,
		"nodes_end": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"memory_mb_start": snappedf(_memory_at_start, 0.1),
		"memory_mb_end": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
		"nights_built": _host.nights,
		"samples": _samples,
	}
	var text := JSON.stringify(result)
	print("SOAK8 ", text)
	if _args.has("out"):
		var file := FileAccess.open(String(_args["out"]), FileAccess.WRITE)
		if file != null:
			file.store_string(text)
			file.close()
	for _i in BAKE_WAIT_FRAMES:
		await get_tree().process_frame
	var failed := not _seat_losses.is_empty() or _host.kicked_count > 0
	get_tree().quit(1 if failed else 0)


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _parse_args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
