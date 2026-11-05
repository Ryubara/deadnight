extends Node
## The soak of bot filling (#230, #1179): a game server's room over a real WebSocket on this
## machine, people who are autopilot clients (each drives its own predicted body from its own
## shoulder camera, as a person's client does) and the room's bots, for game minutes. It checks
## what a match with bots must keep: the bots are the setting however many people come and go (they
## hold no seat of the eight people, so none gives way), the night is never rebuilt and the round
## never goes back, and the clients stay with the server (no predicted body far from the server's,
## no seat a client shows that the server does not hold). An engine error anywhere fails the run
## (the log is read).
##
## `godot --headless --path game res://tests/captures/bots_slots_soak.tscn --fixed-fps 60
##   -- --scenario=pair --minutes=10`
## Arguments after `--`: `--scenario=pair|churn` (default pair), `--minutes=M` (game minutes),
## `--seed=N`, `--skill=0|1|2`, `--tough=X` (every player's health, a multiple of the shipped: the
## point is the network, not whether the autopilot survives ten minutes), `--trace` (a line a
## game minute).
##
## pair:  two people and a Bots setting of 2 for the whole run.
## churn: a Bots setting of 3; people join at 0, 10, 30 and 50% of the run (every bot stays, on top
##        of the people) and leave at 70, 80 and 90% (every bot still stays).
## Run it with `--fixed-fps 60` so the minutes pass as fast as the machine can step them. Prints
## `SLOTS {json}` and exits 1 when any check failed.

const HZ := 60
## How far a predicted body may be from the server's while the autopilot sprints (as in the netcode
## scenario of #56).
const MOST_AHEAD := 2.5
## Ticks after a seat change in which the clients' seat lists may still lag the server's.
const SETTLE_TICKS := 120
## Ticks the lot takes to warm up; the host's worst step is read after them.
const WARM_TICKS := 1200
## Ticks between two comparisons of the solid things the clients' worlds and the server's hold.
const SOLIDS_EVERY := 300

var _args := {}
var _host: NightHost
## Player id -> the client (a `Night`) that plays the seat.
var _clients: Dictionary = {}
var _started_at := 0
var _failures: Array[String] = []
var _worst_gap := 0.0
## Player id -> what the last check of the solid things found different.
var _solids_apart := {}
var _worst_step_ms := 0.0
var _seat_checks := 0
var _last_change := 0
var _round_seen := 0
var _changes: Array[Dictionary] = []
var _bodies_kept := 0


func _ready() -> void:
	_args = _parse_args()
	var scenario := String(_args.get("scenario", "pair"))
	var minutes := float(_args.get("minutes", 10))
	var settings := MatchSettings.new()
	settings.bot_skill = int(_args.get("skill", 1))
	var churn := scenario == "churn"
	settings.bots = 3 if churn else 2
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.health.max_health *= float(_args.get("tough", 4.0))
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = int(_args.get("seed", 7))
	_host.match_settings = settings
	_host.rules_tuning = tuning
	_host.clock = _game_seconds
	_world().add_child(_host)
	while not _host.serving:
		await get_tree().physics_frame
	var total := int(minutes * 60.0 * HZ)
	_started_at = Engine.get_physics_frames()
	var plan: Array[Dictionary] = _churn_plan(total) if churn else _pair_plan()
	var next := 0
	var first_night := -1
	while _tick() < total:
		while next < plan.size() and _tick() >= int(plan[next]["at"]):
			await _change(plan[next])
			next += 1
		if first_night < 0 and _host.nights > 0:
			first_night = _host.nights
		await get_tree().physics_frame
		_watch(first_night)
		if _args.has("trace") and _tick() % (60 * HZ) == 0:
			print("SLOTS TRACE minute ", _tick() / (60 * HZ), " ", _line())
	_report(total, first_night)
	for id: int in _clients.keys():
		_drop(id)
	await get_tree().process_frame
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _game_seconds() -> float:
	return Engine.get_physics_frames() / float(HZ)


func _tick() -> int:
	return Engine.get_physics_frames() - _started_at


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _pair_plan() -> Array[Dictionary]:
	return [{"at": 0, "join": true}, {"at": 0, "join": true}]


func _churn_plan(total: int) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	for share in [0.0, 0.1, 0.3, 0.5]:
		plan.append({"at": int(total * share), "join": true})
	for share in [0.7, 0.8, 0.9]:
		plan.append({"at": int(total * share), "join": false})
	return plan


## A person joins (an autopilot client takes the lowest free seat) or the person in the highest seat
## leaves; then the room is given a moment and the bots are counted against the rule, and each is
## the body it was.
func _change(step: Dictionary) -> void:
	var bodies_before := {}
	for bot_id in _host.bots.seats():
		bodies_before[bot_id] = _host.server.body_of(bot_id)
	if step["join"]:
		await _join()
	else:
		var ids: Array = _clients.keys()
		ids.sort()
		_drop(ids.back())
	_last_change = _tick()
	for _i in SETTLE_TICKS:
		await get_tree().physics_frame
	# A client that joins builds its lot on this thread: that stall is not the server's.
	_host.worst_ms = 0.0
	var expected := NightBots.target(_host.match_settings.bots, _host.bot_limit)
	(
		_changes
		. append(
			{
				"tick": _tick(),
				"join": step["join"],
				"people": _clients.size(),
				"bots": _host.bots.count(),
				"expected": expected,
			}
		)
	)
	if _host.bots.count() != expected:
		_fail("at tick %d: %d bots, expected %d" % [_tick(), _host.bots.count(), expected])
	for bot_id: int in bodies_before:
		_bodies_kept += 1
		# A bot has no seat for a person to take: each is the body it was, still a bot.
		if (
			not _host.server.rules.players.has(bot_id)
			or not (_host.server.rules.players[bot_id] as PlayerState).bot
			or _host.server.body_of(bot_id) != bodies_before[bot_id]
		):
			_fail("the bot %d is not the body it was after a person came or went" % bot_id)


func _join() -> void:
	var night := Night.new()
	night.shoulder_camera = true
	_world().add_child(night)
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	var link := WebSocketLink.new()
	link.clock = _game_seconds
	var joined := await night.start_remote(url, Night.Mode.AUTOPILOT, 60.0, link)
	if not joined:
		_fail("a client could not join")
		night.get_parent().queue_free()
		return
	_clients[night.state.player_id] = night


func _drop(player_id: int) -> void:
	var night: Night = _clients.get(player_id)
	_clients.erase(player_id)
	if night != null and is_instance_valid(night):
		night.link.close()
		night.get_parent().queue_free()


## Every frame: the predicted bodies near the server's, the round never back, the step time.
func _watch(first_night: int) -> void:
	# The first seconds build and warm the lot: the worst step is read after them.
	if _tick() > WARM_TICKS:
		_worst_step_ms = maxf(_worst_step_ms, _host.worst_ms)
	if first_night >= 0 and _host.nights != first_night:
		_fail("the night was rebuilt (%d -> %d)" % [first_night, _host.nights])
		return
	var rules := _host.server.rules
	if rules.round_number < _round_seen:
		_fail("the round went back from %d to %d" % [_round_seen, rules.round_number])
	_round_seen = maxi(_round_seen, rules.round_number)
	for id: int in _clients:
		var night: Night = _clients[id]
		var body := _host.server.body_of(id)
		if body == null or night.player() == null:
			continue
		var gap := night.player().state.position.distance_to(body.global_position)
		_worst_gap = maxf(_worst_gap, gap)
		if gap > MOST_AHEAD:
			_fail(
				(
					"client %d is %.2f m from the server at tick %d (%s)"
					% [id, gap, _tick(), _why_apart(id, night, body)]
				)
			)
	if _tick() % 30 == 0 and _tick() - _last_change > SETTLE_TICKS:
		_check_seats()
	if _tick() % SOLIDS_EVERY == 0:
		_check_solids()


## What the two bodies were doing when they were far apart, for the failure line: the nearest
## other body to the server's, and what each of the two last slid along.
func _why_apart(id: int, night: Night, body: Player) -> String:
	var mine := night.player()
	return (
		"server body %s, nearest other body %.2f m, client slid on %s, server slid on %s"
		% [body.global_position, _nearest_other(id, body), _slid_on(mine), _slid_on(body)]
	)


func _slid_on(body: Player) -> String:
	var hit := body.get_last_slide_collision()
	if hit == null:
		return "nothing"
	var collider := hit.get_collider() as Node3D
	return "%s at %s" % [collider.name, collider.global_position]


func _nearest_other(id: int, body: Node3D) -> float:
	var best := INF
	for other: int in _host.server.rules.players.keys():
		var other_body := _host.server.body_of(other)
		if other != id and other_body != null:
			best = minf(best, other_body.global_position.distance_to(body.global_position))
	return best


## Every solid thing a client's world holds is in the server's too, and the other way round: a wall
## one of them lacks stops one body and not the other (#748, #760). A board torn a moment ago may
## not have reached a client yet, so a difference counts when two checks in a row find the same.
func _check_solids() -> void:
	var mask := 0
	for id: int in _host.server.rules.players.keys():
		var any := _host.server.body_of(id)
		if any != null:
			mask = any.collision_mask
			break
	var server := WorldSolids.of(_host.get_parent(), mask)
	for id: int in _clients:
		var night: Night = _clients[id]
		if night.world == null or not is_instance_valid(night.get_parent()):
			continue
		var apart := str(WorldSolids.differences(WorldSolids.of(night.get_parent(), mask), server))
		if apart != "[]" and apart == _solids_apart.get(id, ""):
			_fail("client %d and the server hold different solid things: %s" % [id, apart])
		_solids_apart[id] = apart if apart != "[]" else ""


## The seats a client's frame holds are the seats the server holds.
func _check_seats() -> void:
	_seat_checks += 1
	var held: Array = _host.server.rules.players.keys()
	held.sort()
	for id: int in _clients:
		var frame: Dictionary = (_clients[id] as Night).state.frame
		if frame.is_empty():
			continue
		var shown: Array = (frame.get("players", {}) as Dictionary).keys()
		shown.sort()
		if shown != held:
			_fail("client %d shows seats %s, the server holds %s" % [id, shown, held])


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)
	printerr("SLOTS FAIL ", message)


func _line() -> String:
	return (
		"round %d, %d zombies, %d people, %d bots"
		% [
			_host.server.rules.round_number,
			_host.server.sim.zombies.size(),
			_clients.size(),
			_host.bots.count(),
		]
	)


func _report(total: int, first_night: int) -> void:
	var sent := 0
	var stuck := 0
	for bot in _host.bots.host.bots:
		sent += bot.telemetry.commands
		stuck += int(bot.telemetry.counters.get(&"stuck_episodes", 0))
	var worst_error := 0.0
	var corrections := 0
	for id: int in _clients:
		var reconciler: Reconciler = (_clients[id] as Night).reconciler
		worst_error = maxf(worst_error, reconciler.worst_error)
		corrections += reconciler.corrections
	var profile := ""
	if _host.bots.count() > 0:
		profile = _host.bots.host.bots[0].profile.title
	var report := {
		"scenario": String(_args.get("scenario", "pair")),
		"minutes": snappedf(total / float(HZ) / 60.0, 0.1),
		"ticks": total,
		"night_rebuilt": _host.nights != first_night,
		"round_reached": _round_seen,
		"people_at_end": _clients.size(),
		"bots_at_end": _host.bots.count(),
		"bot_profile": profile,
		"changes": _changes,
		"bot_bodies_kept": _bodies_kept,
		"seat_checks": _seat_checks,
		"worst_gap_m": snappedf(_worst_gap, 0.01),
		"worst_reconcile_error_m": snappedf(worst_error, 0.01),
		"corrections": corrections,
		"bot_commands": sent,
		"bot_stuck_episodes": stuck,
		"host_worst_step_ms": snappedf(_worst_step_ms, 0.1),
		"host_mean_step_ms": snappedf(_host.work_ms / maxf(float(_host.steps), 1.0), 0.01),
		"failures": _failures,
	}
	print("SLOTS ", JSON.stringify(report))


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
