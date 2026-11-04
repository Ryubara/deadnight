extends GdUnitTestSuite
## The dead stop a predicting client's body where they stop the server's (#914): a client on a link
## with a real delay sprints at a standing zombie and at one that walks to meet it, and the body it
## moves at once ends where the server has the player, without being thrown back (no rubber band).
## The server judges the body against the dead as the client drew them
## (`NightServer._dead_seen_by`).

const ONE_WAY_DELAY := 0.06
## How far the predicted body may be from the server's after it has stopped, and the largest
## correction the reconciler may ask for in a run that has a zombie in it.
const SETTLED := 0.12
## The reconciler's largest correction in a run that meets the dead: the lead a sprint has over the
## server on a 120 ms round trip is about 0.5 m and the start of a sprint costs corrections of 0.2
## to 0.5 m with no zombie at all, so this is a bound on a snap-back, not a comparison (the numbers
## of the arms, 8 runs: `docs/research/dead-contact.md`).
const MOST_CORRECTED := 1.0

var _host: NightHost
var _night: Night


func after_test() -> void:
	for action in [&"move_forward", &"sprint"]:
		Input.action_release(action)
	if is_instance_valid(_night):
		_night.get_parent().queue_free()
	if is_instance_valid(_host):
		_host.get_parent().queue_free()


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _until(condition: Callable, seconds: float = 20.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


func _join(seen: bool) -> bool:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	if not await _until(func() -> bool: return _host.serving, 30.0):
		return false
	_host.server.dead_as_seen = seen
	var link := WebSocketLink.new()
	link.conditioner_in = LinkConditioner.new(ONE_WAY_DELAY, 0.01, 1)
	link.conditioner_out = LinkConditioner.new(ONE_WAY_DELAY, 0.01, 2)
	_night = Night.new()
	_world().add_child(_night)
	var joined := await _night.start_remote(
		"ws://127.0.0.1:%d" % _host.listener.port(), Night.Mode.HUMAN, 30.0, link
	)
	# The first frames, and the body on the ground.
	for _i in 60:
		await get_tree().physics_frame
	return joined


## A zombie that stands (or walks at `speed`) and hurts nobody, `ahead` metres in front of the
## player's body on the server. Returns its id.
func _zombie(ahead: float, speed: float) -> int:
	var sim := _host.server.sim
	var profile := ZombieProfile.plain(sim.tuning)
	profile.damage = 0.0
	profile.windup = 1.0e6
	var at := _host.server.body_of(1).global_position + Vector3(0.0, 0.0, -ahead)
	var zombie := sim.spawn(900, speed, at, 0.0, profile)
	zombie.enter(ZombieBody.Mode.CHASE)
	return 900


## Holds forward (and sprint) for `seconds`; returns the nearest approach of the client's body and
## of the server's to the zombie's true place.
func _sprint_at(zombie_id: int, seconds: float) -> Dictionary:
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	var nearest_client := INF
	var nearest_server := INF
	for i in int(seconds * 60.0):
		await get_tree().physics_frame
		var zombie: ZombieBody = _host.server.sim.zombies.get(zombie_id)
		if zombie == null:
			zombie = ZombieBody.new()
			zombie.position = Vector3(1.0e4, 0.0, 1.0e4)
		if i % 6 == 0 and OS.get_environment("DEAD_TRACE") != "":
			print(
				(
					"t=%.2f server z=%.2f client z=%.2f zombie z=%.2f x=%.2f mode=%d gap=%.3f"
					% [
						i / 60.0,
						_host.server.body_of(1).global_position.z,
						_night.player().global_position.z,
						zombie.position.z,
						zombie.position.x,
						zombie.mode,
						_gap()
					]
				)
			)
		var server := _host.server.body_of(1).global_position
		var client := _night.player().global_position
		nearest_server = minf(
			nearest_server,
			Vector2(server.x - zombie.position.x, server.z - zombie.position.z).length()
		)
		nearest_client = minf(
			nearest_client,
			Vector2(client.x - zombie.position.x, client.z - zombie.position.z).length()
		)
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	return {"client": nearest_client, "server": nearest_server}


func _edge() -> float:
	return PlayerTuning.new().radius + DeadContactTuning.shipped().radius


func _gap() -> float:
	var server := _host.server.body_of(1).global_position
	return _night.player().global_position.distance_to(server)


## One run: a zombie `ahead` metres in front that walks at `speed` (none when `ahead` is 0), the
## body sprinting at it; returns the numbers of the run.
func _run(seen: bool, ahead: float, speed: float, seconds: float) -> Dictionary:
	assert_bool(await _join(seen)).is_true()
	var id := -1
	if ahead > 0.0:
		id = _zombie(ahead, speed)
	var near := await _sprint_at(id, seconds)
	# The body has stopped: the server's answers catch the client up (a slow machine takes longer).
	await _until(func() -> bool: return _gap() < SETTLED, 5.0)
	var result := {
		"client": near["client"],
		"server": near["server"],
		"gap": _gap(),
		"worst": _night.reconciler.worst_error,
		"corrections": _night.reconciler.corrections,
	}
	print(
		(
			(
				"dead online ahead=%.0f speed=%.1f seen=%s: client %.2f server %.2f m from the zombie,"
				+ " gap %.3f, worst correction %.3f, corrections %d"
			)
			% [
				ahead,
				speed,
				seen,
				result["client"],
				result["server"],
				result["gap"],
				result["worst"],
				result["corrections"]
			]
		)
	)
	_night.get_parent().queue_free()
	_host.get_parent().queue_free()
	await get_tree().physics_frame
	return result


func test_a_predicting_client_is_stopped_at_a_standing_zombie_with_the_server() -> void:
	var result := await _run(true, 5.0, 0.0, 2.5)
	# A client that is a frame or two behind is stopped by the zombie a few centimetres late.
	assert_float(result["client"]).is_greater(_edge() - 0.2)
	assert_float(result["server"]).is_greater(_edge() - 0.1)
	assert_float(result["server"]).is_less(_edge() + 0.5)
	assert_float(result["gap"]).is_less(SETTLED)
	assert_float(result["worst"]).is_less(MOST_CORRECTED)


func test_a_walking_zombie_is_met_without_a_snap_back() -> void:
	var none := await _run(true, 0.0, 0.0, 2.5)
	var seen := await _run(true, 7.0, 1.5, 2.5)
	var now := await _run(false, 7.0, 1.5, 2.5)
	print(
		(
			"dead online: worst correction none %.3f, as seen %.3f, as it stands %.3f"
			% [none["worst"], seen["worst"], now["worst"]]
		)
	)
	# The server's body is stopped by the dead as its client drew them, a round trip old: a zombie
	# that walks to meet it has come this much nearer by then.
	assert_float(seen["server"]).is_greater(_edge() - 0.35)
	assert_float(seen["gap"]).is_less(SETTLED)
	assert_float(seen["worst"]).is_less(MOST_CORRECTED)
