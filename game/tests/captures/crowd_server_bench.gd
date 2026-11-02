extends Node
## What a zombie crowd costs the game server, with no client and no socket (issue #453). The real
## `NightServer` on the real lot, four players joined and standing still, the rules bent so the
## crowd fills to N at once and the players cannot die; every tick is timed, and every second tick
## the snapshot each of the four players would be sent is made the way `NightHost` makes it (the
## frame's delta against the last one, packed in a `NetWire.tick`) so the bytes are the wire's.
## Not part of the game. Runs headless, the same in the Railway container and on this machine.
## Arguments after `--`: `--zombies=N` (alive at once), `--measure=TICKS` (default 1200, 20 s of
## game time), `--players=N` (default 4), `--seed=N`, `--web=1` (the players are browsers).
## `--rooms=K` runs K nights in this one process, each in a `SubViewport` of its own as
## `GameServer` builds them, all stepped in the same physics frame: the numbers are then the
## process's tick (`tick_ms_*`: the steps and the snapshots of every room), which is what has to fit
## the 16.7 ms. `--stagger=1` starts the odd rooms one step later (`NightHost.phase`), so the
## rooms' heavy steps do not fall on the same tick.

## Ticks the crowd is given to fill and settle before the measured ones.
const FILL_TICKS_MAX := 6000
const SETTLE_TICKS := 300
const NEVER := 1.0e9

var _args := {}
var _crowd := 40
var _players := 4
var _room_count := 1
var _stagger := false
var _measure_ticks := 1200
var _rooms: Array[BenchRoom] = []
var _running := false
var _ticks := 0
var _fill_until := 1 << 30
var _filled_in := 0
var _measured := 0
## Per physics frame: the steps of every room, and those plus the snapshots they make.
var _step_ms: Array[float] = []
var _tick_ms: Array[float] = []
var _send_ms: Array[float] = []
var _bytes_each: Array[int] = []
var _alive_sum := 0.0
var _no_zombies: Dictionary[int, PackedByteArray] = {}
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


## One night in the process: its own world in its own `SubViewport` (as `GameServer` builds a room),
## its step counter and what it last sent each player.
class BenchRoom:
	extends RefCounted
	var world: NightWorld
	var server: NightServer
	var timed: TimedPathing
	var steps := 0
	var phase := 0
	var paths_before := 0
	var calls_before := 0
	var last_frames := {}
	var zombie_base := {}
	var zombie_sequence := 0


func _ready() -> void:
	_args = _parse_args()
	_crowd = int(_args.get("zombies", 40))
	_players = int(_args.get("players", 4))
	_room_count = maxi(int(_args.get("rooms", 1)), 1)
	_stagger = _flag("stagger")
	_measure_ticks = int(_args.get("measure", 1200))
	for index in _room_count:
		_rooms.append(await _build_room(index))
	_running = true
	PerfProbe.enabled = true
	PerfProbe.take()


func _build_room(index: int) -> BenchRoom:
	var room := BenchRoom.new()
	var viewport := SubViewport.new()
	viewport.name = "Room_%d" % index
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	room.world = NightWorld.new()
	viewport.add_child(room.world)
	await room.world.build()
	room.server = NightServer.new(
		room.world, int(_args.get("seed", 7)) + index, null, _bent_rules(_crowd)
	)
	room.server.sim.tuning.hard_cap = _crowd
	room.timed = TimedPathing.new(room.world.map())
	room.server.sim.pathing = room.timed
	for id in range(1, _players + 1):
		room.server.apply({"type": NightServer.JOIN, "player_id": id})
		room.server.crowd.set_platform(id, _flag("web"))
	room.server.apply({"type": NightServer.START_NIGHT})
	return room


## One server tick a physics frame, as `NightHost` runs it: the navigation map and the bodies need
## the engine's own physics step between ticks. Every room steps in the same frame, in turn.
func _physics_process(_delta: float) -> void:
	if not _running:
		return
	if _ticks < _fill_until:
		_fill_step()
	elif _ticks < _fill_until + SETTLE_TICKS:
		for room in _rooms:
			_align(room)
			room.server.step(Night.STEP)
			room.steps += 1
		_ticks += 1
	elif _measured < _measure_ticks:
		_measure_step()
	else:
		_running = false
		_report()


## What `NightHost` does on its first step when a `GameServer` gave it a `heavy_parity`.
func _align(room: BenchRoom) -> void:
	if room.steps != 0 or not _stagger:
		return
	if (Engine.get_physics_frames() & 1) == _rooms.find(room) % 2:
		room.phase = 1
		room.server.sim.tick(Night.STEP, {})


func _fill_step() -> void:
	var full := true
	for room in _rooms:
		_align(room)
		room.server.step(Night.STEP)
		room.steps += 1
		full = full and room.server.sim.standing_count() >= _crowd
	_ticks += 1
	if full or _ticks >= FILL_TICKS_MAX:
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
		for room in _rooms:
			room.paths_before = room.timed.usec
			room.calls_before = room.timed.calls
	var step_total := 0.0
	var send_total := 0.0
	for room in _rooms:
		# As `NightHost` runs it: a frame is built only on the steps a snapshot is sent after.
		var sending := (room.steps + room.phase + 1) % NightHost.SEND_EVERY == 0
		var began := Time.get_ticks_usec()
		var events := room.server.step(Night.STEP, sending)
		step_total += (Time.get_ticks_usec() - began) / 1000.0
		room.steps += 1
		_alive_sum += room.server.sim.standing_count()
		if sending:
			send_total += _send_snapshots(room, events)
	var probes: Dictionary = PerfProbe.take()["usec"]
	for label: StringName in probes:
		(_probe_usec.get_or_add(label, []) as Array).append(int(probes[label]))
	_step_ms.append(step_total)
	_tick_ms.append(step_total + send_total)
	if send_total > 0.0:
		_send_ms.append(send_total)
	_measured += 1


## The snapshot each of the room's players is sent, made as `NightHost._send_ticks` makes it (the
## frame's delta against the last one, the zombies as a delta); returns the milliseconds it took.
func _send_snapshots(room: BenchRoom, events: Array[Dictionary]) -> float:
	var frame: Dictionary = events.pop_back()
	var sent := Time.get_ticks_usec()
	var zombies := ZombieDelta.entries_of(frame["zombies"])
	for id in range(1, _players + 1):
		var out: Array = events.filter(
			func(e: Dictionary) -> bool: return e["type"] != NightServer.LOOK_PACKET
		)
		var own := frame.duplicate()
		var base: Dictionary[int, PackedByteArray] = room.zombie_base.get(id, _no_zombies)
		own["zombies"] = ZombieDelta.diff(base, zombies, room.zombie_sequence)
		room.zombie_base[id] = zombies
		out.append(FrameDelta.diff(room.last_frames.get(id, {}), own))
		room.last_frames[id] = own
		_bytes_each.append(NetWire.tick(room.server.tick_count, out).size())
	room.zombie_sequence = (room.zombie_sequence + 1) & 0xFF
	return (Time.get_ticks_usec() - sent) / 1000.0


func _report() -> void:
	var ticks := _measured
	var seconds := ticks * Night.STEP
	var bytes_total := 0
	for b in _bytes_each:
		bytes_total += b
	var paths_usec := 0
	var path_calls := 0
	for room in _rooms:
		paths_usec += room.timed.usec - room.paths_before
		path_calls += room.timed.calls - room.calls_before
	var result := {
		"zombies_asked": _crowd,
		"rooms": _room_count,
		"stagger": _stagger,
		"players": _players,
		"filled_in_ticks": _filled_in,
		"alive": snappedf(_alive_sum / ticks, 0.1),
		"ticks": ticks,
		"send_ms_mean_per_sending_tick": snappedf(_mean(_send_ms), 0.001),
		"navigation_ms_per_tick": snappedf(paths_usec / 1000.0 / ticks, 0.001),
		"navigation_calls_per_tick": snappedf(float(path_calls) / ticks, 0.01),
		"tick_budget_ms": snappedf(Night.STEP * 1000.0, 0.01),
		"bytes_per_snapshot_per_player": snappedf(float(bytes_total) / _bytes_each.size(), 1.0),
		"bytes_per_second_all_players": roundi(bytes_total / seconds),
		"memory_rss_mb": _rss_mb(),
		"probe_ms_per_tick": _probe_report(ticks),
	}
	# The steps of every room (what an older bench of one room called the step), then those and
	# the snapshots made after them: the process's tick, which has to fit the budget.
	result.merge(_spread("step_ms", _step_ms))
	result.merge(_spread("tick_ms", _tick_ms))
	print("CROWD_SERVER ", JSON.stringify(result))
	get_tree().quit()


## Mean, median, 95th and 99th percentile, worst and the count over the tick budget of per-tick
## milliseconds, under `<prefix>_mean`, `_p50`, ...
func _spread(prefix: String, values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var over := 0
	for ms in values:
		if ms > Night.STEP * 1000.0:
			over += 1
	return {
		prefix + "_mean": snappedf(_mean(values), 0.001),
		prefix + "_p50": snappedf(sorted[sorted.size() / 2], 0.001),
		prefix + "_p95": snappedf(sorted[int(sorted.size() * 0.95)], 0.001),
		prefix + "_p99": snappedf(sorted[int(sorted.size() * 0.99)], 0.001),
		prefix + "_max": snappedf(sorted[sorted.size() - 1], 0.001),
		prefix.replace("_ms", "") + "_over_budget": over,
	}


## The process's resident memory in megabytes (Linux; 0 elsewhere).
func _rss_mb() -> float:
	# /proc files have no length, so they are read line by line, not as a string.
	var status := FileAccess.open("/proc/self/status", FileAccess.READ)
	while status != null and not status.eof_reached():
		var line := status.get_line()
		if line.begins_with("VmRSS:"):
			var kilobytes := line.get_slice(":", 1).strip_edges().get_slice(" ", 0)
			return snappedf(float(kilobytes) / 1024.0, 0.1)
	return 0.0


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


## Whether `--name=1` was given.
func _flag(name: String) -> bool:
	return int(str(_args.get(name, 0))) != 0


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var parts := arg.trim_prefix("--").split("=", true, 1)
			out[parts[0]] = parts[1]
	return out
