extends Node
## What a zombie crowd costs the game server, with no client and no socket (issue #453). The real
## `NightServer` on the real lot, four players joined and standing still, the rules bent so the
## crowd fills to N at once and the players cannot die; every tick is timed, and every second tick
## the snapshot each of the four players would be sent is made the way `NightHost` makes it (the
## frame's delta against the last one, packed in a `NetWire.tick`) so the bytes are the wire's.
## Not part of the game. Runs headless, the same in the Railway container and on this machine.
## Arguments after `--`: `--zombies=N` (alive at once), `--measure=TICKS` (default 1200, 20 s of
## game time), `--players=N` (default 4), `--seed=N`.

## Ticks the crowd is given to fill and settle before the measured ones.
const FILL_TICKS_MAX := 6000
const SETTLE_TICKS := 300
const NEVER := 1.0e9

var _world: NightWorld
var _server: NightServer
var _timed: TimedPathing
var _args := {}
var _crowd := 40
var _players := 4
var _measure_ticks := 1200
var _running := false
var _ticks := 0
var _fill_until := 1 << 30
var _filled_in := 0
var _measured := 0
var _step_ms: Array[float] = []
var _send_ms: Array[float] = []
var _bytes_each: Array[int] = []
var _last_frames := {}
var _zombie_base := {}
var _no_zombies: Dictionary[int, PackedByteArray] = {}
var _zombie_sequence := 0
var _alive_sum := 0.0
var _paths_before := 0
var _calls_before := 0
## What `PerfProbe` timed inside the server's step, summed over the measured ticks (microseconds).
var _probe_usec: Dictionary[StringName, Array] = {}


## Paths through the navigation map, with the time they took.
class TimedPathing:
	extends NavmeshPathing

	var usec := 0
	var calls := 0

	func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		var started := Time.get_ticks_usec()
		var way := super.find_path(from, to)
		usec += Time.get_ticks_usec() - started
		calls += 1
		return way


func _ready() -> void:
	_args = _parse_args()
	_crowd = int(_args.get("zombies", 40))
	_players = int(_args.get("players", 4))
	_measure_ticks = int(_args.get("measure", 1200))
	var tuning := _bent_rules(_crowd)
	_world = NightWorld.new()
	add_child(_world)
	await _world.build()
	_server = NightServer.new(_world, int(_args.get("seed", 7)), null, tuning)
	_server.sim.tuning.hard_cap = _crowd
	_timed = TimedPathing.new(_world.map())
	_server.sim.pathing = _timed
	for id in range(1, _players + 1):
		_server.apply({"type": NightServer.JOIN, "player_id": id})
		_server.set_platform(id, bool(_args.get("web", false)))
	_server.apply({"type": NightServer.START_NIGHT})
	_running = true
	PerfProbe.enabled = true
	PerfProbe.take()


## One server tick a physics frame, as `NightHost` runs it: the navigation map and the bodies need
## the engine's own physics step between ticks.
func _physics_process(_delta: float) -> void:
	if not _running:
		return
	if _ticks < _fill_until:
		_fill_step()
	elif _ticks < _fill_until + SETTLE_TICKS:
		_server.step(Night.STEP)
		_ticks += 1
	elif _measured < _measure_ticks:
		_measure_step()
	else:
		_running = false
		_report()


func _fill_step() -> void:
	_server.step(Night.STEP)
	_ticks += 1
	if _server.sim.standing_count() >= _crowd or _ticks >= FILL_TICKS_MAX:
		_fill_until = _ticks
		_filled_in = _ticks


## The rules, bent for a bench: the crowd is as large as asked and arrives at once, the players do
## not die, and no break or intro waits.
func _bent_rules(crowd: int) -> RulesTuning:
	var tuning := (
		(load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).duplicate(true) as RulesTuning
	)
	var rounds := tuning.rounds
	rounds.count_base = float(crowd) * 100.0
	rounds.alive_cap_start = float(crowd)
	rounds.alive_cap_max = float(crowd)
	rounds.alive_cap_per_extra_player = 0.0
	rounds.alive_cap_ceiling = crowd
	rounds.spawn_interval_start = 0.05
	rounds.spawn_interval_min = 0.05
	rounds.first_spawn_delay = 0.0
	rounds.intro_seconds = 0.1
	tuning.health.max_health = NEVER
	return tuning


func _measure_step() -> void:
	if _measured == 0:
		_paths_before = _timed.usec
		_calls_before = _timed.calls
	# As `NightHost` runs it: a frame is built only on the steps a snapshot is sent after.
	var sending := (_measured + 1) % NightHost.SEND_EVERY == 0
	var began := Time.get_ticks_usec()
	var events := _server.step(Night.STEP, sending)
	_step_ms.append((Time.get_ticks_usec() - began) / 1000.0)
	var probes: Dictionary = PerfProbe.take()["usec"]
	for label: StringName in probes:
		(_probe_usec.get_or_add(label, []) as Array).append(int(probes[label]))
	var frame: Dictionary = events.pop_back() if sending else {}
	_alive_sum += _server.sim.standing_count()
	_measured += 1
	if not sending:
		return
	var sent := Time.get_ticks_usec()
	var zombies := ZombieDelta.entries_of(frame["zombies"])
	for id in range(1, _players + 1):
		var out: Array = events.filter(
			func(e: Dictionary) -> bool: return e["type"] != NightServer.LOOK_PACKET
		)
		# As `NightHost._send_ticks`: the zombies go as what changed from the ones the client has.
		var own := frame.duplicate()
		var base: Dictionary[int, PackedByteArray] = _zombie_base.get(id, _no_zombies)
		own["zombies"] = ZombieDelta.diff(base, zombies, _zombie_sequence)
		_zombie_base[id] = zombies
		out.append(FrameDelta.diff(_last_frames.get(id, {}), own))
		_last_frames[id] = own
		_bytes_each.append(NetWire.tick(_server.tick_count, out).size())
	_zombie_sequence = (_zombie_sequence + 1) & 0xFF
	_send_ms.append((Time.get_ticks_usec() - sent) / 1000.0)


func _report() -> void:
	var sorted := _step_ms.duplicate()
	sorted.sort()
	var ticks := _measured
	var seconds := ticks * Night.STEP
	var bytes_total := 0
	for b in _bytes_each:
		bytes_total += b
	var over := 0
	for ms in _step_ms:
		if ms > Night.STEP * 1000.0:
			over += 1
	var result := {
		"zombies_asked": _crowd,
		"players": _players,
		"filled_in_ticks": _filled_in,
		"alive": snappedf(_alive_sum / ticks, 0.1),
		"ticks": ticks,
		"step_ms_mean": snappedf(_mean(_step_ms), 0.001),
		"step_ms_p50": snappedf(sorted[sorted.size() / 2], 0.001),
		"step_ms_p95": snappedf(sorted[int(sorted.size() * 0.95)], 0.001),
		"step_ms_p99": snappedf(sorted[int(sorted.size() * 0.99)], 0.001),
		"step_ms_max": snappedf(sorted[sorted.size() - 1], 0.001),
		"ticks_over_budget": over,
		"send_ms_mean_per_snapshot": snappedf(_mean(_send_ms), 0.001),
		"navigation_ms_per_tick": snappedf((_timed.usec - _paths_before) / 1000.0 / ticks, 0.001),
		"navigation_calls_per_tick": snappedf(float(_timed.calls - _calls_before) / ticks, 0.01),
		"tick_budget_ms": snappedf(Night.STEP * 1000.0, 0.01),
		"bytes_per_snapshot_per_player": snappedf(float(bytes_total) / _bytes_each.size(), 1.0),
		"bytes_per_second_all_players": roundi(bytes_total / seconds),
		"probe_ms_per_tick": _probe_report(ticks),
	}
	print("CROWD_SERVER ", JSON.stringify(result))
	get_tree().quit()


## The probes of the server's step, in milliseconds a tick: mean, median, 95th percentile and worst.
## A machine shared with other work shows in the mean and the worst; trust the median.
func _probe_report(ticks: int) -> Dictionary:
	var out := {}
	for label: StringName in _probe_usec:
		var values: Array = _probe_usec[label]
		# Ticks where the probe never ran count as zero.
		values.resize(ticks)
		for i in ticks:
			if values[i] == null:
				values[i] = 0
		var total := 0
		for usec: int in values:
			total += usec
		values.sort()
		out[String(label)] = {
			"mean": snappedf(total / 1000.0 / ticks, 0.001),
			"p50": snappedf(values[ticks / 2] / 1000.0, 0.001),
			"p95": snappedf(values[int(ticks * 0.95)] / 1000.0, 0.001),
			"max": snappedf(values[ticks - 1] / 1000.0, 0.01),
		}
	return out


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxf(values.size(), 1.0)


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var parts := arg.trim_prefix("--").split("=", true, 1)
			out[parts[0]] = parts[1]
	return out
