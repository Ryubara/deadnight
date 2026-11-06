extends GdUnitTestSuite
## A person's body, a bot's and a client's predicted body when the prize crane's cabinet
## (`CraneBlock`, a solid box that moves to another spot when the crane breaks down) lands on them.
## The cabinet at its third spot is 1.8 m by 1.4 m; a body in its middle is at least 0.7 m from a
## face. #1361 left this to the engine's depenetration; this measures it on the real lot and the
## real server, and over a real socket for the client's body: each ends outside, one step after the
## landing, having crossed nothing, on the walking mesh, and can walk and be shot at as before.

const SEED := 8
const TICKS_PER_SECOND := 60
const LONG_BREAK := 3000.0
const SPOT := 2
## The cabinet's middle at the third spot.
const MIDDLE := Vector3(-24.0, 0.1, -12.5)
const BODY_RADIUS := 0.35
## Where the bodies stand when it lands: the middle (the worst case), 0.1 m inside the face on the
## shop side, and 0.1 m inside a corner.
const FRONT_FACE := Vector3(-24.0, 0.1, -13.1)
const CORNER := Vector3(-23.2, 0.1, -11.9)
## Ticks watched after the landing, and the most a body may take to be clear of the cabinet
## (measured: capsule clear on the first tick after, the client's on the second).
const WATCH_TICKS := 60
const CLEAR_WITHIN := 3
## The most a body is moved in one tick (measured: 1.04 m from the middle, 0.45 m from a face).
const MOST_MOVED := 1.2
## Metres off the walking mesh a body may end (measured: 0).
const MESH_SLACK := 0.5
## A walk of this many metres at the least, in a second of full speed (measured: 4.5 m/s).
const WALKS := 4.0

var _night: SeatedNight
var _bot: BotClient
var _host: NightHost
var _client: Night


func after_test() -> void:
	if _night != null:
		_night.dispose()
		_night = null
	if is_instance_valid(_client):
		_client.get_parent().queue_free()
	if is_instance_valid(_host):
		_host.get_parent().queue_free()
	await get_tree().process_frame


func _tuning() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	tuning.rounds.first_spawn_delay = LONG_BREAK
	tuning.crane.spin_seconds = 1.0
	tuning.crane.breakdown_seconds = 1.0
	tuning.crane.leave_chances = PackedFloat32Array([1.0])
	tuning.crane.safe_plays = 0
	return tuning


## A night with a bot (1) and a person (2) seated, nobody commanding them.
func _setup() -> void:
	_night = await NightFixture.seat(self, 2, _tuning(), SEED)
	await _night.settle(60)
	_bot = _night.seat(1, BotProfile.regular(), SEED + 1)
	_night.human(2)
	_night.run(10)
	# What the seated bot sent in those ticks runs out.
	for _i in 30:
		_night.server.step(Night.STEP)


func _solid() -> ZombieSolid:
	return _night.world.crane_block.solid


## Puts both bodies at `place`, plays the crane to its breakdown and watches both for
## `WATCH_TICKS` ticks after the cabinet lands, one server step a physics frame as in a game.
## Returns each body's position after each of those ticks, by player.
func _land_on(place: Vector3) -> Dictionary:
	var rules := _night.server.rules
	var bodies := {1: _night.server.body_of(1), 2: _night.server.body_of(2)}
	for id: int in bodies:
		(bodies[id] as Player).teleport(place)
	rules.apply(RulesAction.grant_points(2, 10000))
	rules.apply(RulesAction.buy(2, &"crane_play"))
	var guard := 0
	while rules.crane.spot != SPOT and guard < 5 * TICKS_PER_SECOND:
		_night.server.step(Night.STEP)
		await get_tree().physics_frame
		guard += 1
	assert_int(rules.crane.spot).is_equal(SPOT)
	var traces := {1: [], 2: []}
	for _tick in WATCH_TICKS:
		_night.server.step(Night.STEP)
		await get_tree().physics_frame
		for id: int in bodies:
			traces[id].append((bodies[id] as Player).global_position)
	return traces


## The tick (counted from 0 after the landing) a body is first clear of the cabinet.
func _clear_at(trace: Array, solid: ZombieSolid) -> int:
	for index in trace.size():
		if not solid.contains(trace[index], BODY_RADIUS):
			return index
	return -1


func _most_in_a_tick(start: Vector3, trace: Array) -> float:
	var most := 0.0
	var before := start
	for at: Vector3 in trace:
		most = maxf(most, before.distance_to(at))
		before = at
	return most


## What a ray from 3 m away on `side` meets first on its way to the body's chest.
func _shot_meets(body: Player, side: Vector3) -> Object:
	var chest := body.global_position + Vector3(0.0, 1.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(
		chest + side * 3.0, chest, PhysicsLayers.WORLD | PhysicsLayers.BODY
	)
	var hit := _night.world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") if not hit.is_empty() else null


## What but the cabinet stands on the straight way from `a` to `b` (rays at the knee, chest, head).
func _blocking(a: Vector3, b: Vector3) -> Array[String]:
	var found: Array[String] = []
	for height in [0.3, 1.0, 1.7]:
		var query := PhysicsRayQueryParameters3D.create(
			a + Vector3(0.0, height, 0.0), b + Vector3(0.0, height, 0.0), PhysicsLayers.WORLD
		)
		query.exclude = [_night.world.crane_block.get_rid()]
		var hit := _night.world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			found.append(str((hit["collider"] as Node).name))
	return found


## A walk to `goal` as a person with a stick does it, for a second or two; whether it got there.
func _walk_to(id: int, goal: Vector3) -> bool:
	var walker := HumanWalker.new(_night.server, _night.world.map(), id)
	walker.goto(goal)
	for _i in 3 * TICKS_PER_SECOND:
		if walker.arrived():
			return true
		walker.tick()
		_night.server.step(Night.STEP)
		await get_tree().physics_frame
	return walker.arrived()


func _check_server_body(id: int, place: Vector3, trace: Array) -> void:
	var who := "bot" if id == 1 else "person"
	var body := _night.server.body_of(id)
	var end: Vector3 = trace.back()
	var clear := _clear_at(trace, _solid())
	(
		assert_int(clear)
		. override_failure_message("%s at %s: clear on tick %d (-1: never)" % [who, place, clear])
		. is_between(0, CLEAR_WITHIN)
	)
	(
		assert_float(_most_in_a_tick(place, trace))
		. override_failure_message("%s at %s: moved too far in one tick" % [who, place])
		. is_less(MOST_MOVED)
	)
	assert_float(end.y).is_less(0.05)
	assert_bool(_night.world.bounds.is_out(end)).is_false()
	var near := NavigationServer3D.map_get_closest_point(_night.world.map(), end)
	assert_float(Vector2(near.x - end.x, near.z - end.z).length()).is_less(MESH_SLACK)
	assert_array(_blocking(place, end)).is_empty()
	# Shot at from the open side the body is met, not the cabinet; from behind it, the cabinet is.
	var out := Vector3(end.x - MIDDLE.x, 0.0, end.z - MIDDLE.z).normalized()
	assert_bool(_shot_meets(body, out) is Player).is_true()
	assert_bool(_shot_meets(body, -out) is CraneBlock).is_true()
	var goal := end + out * 3.0
	assert_bool(await _walk_to(id, goal)).is_true()


func _land_and_check(place: Vector3) -> void:
	await _setup()
	var traces := await _land_on(place)
	for id in [1, 2]:
		await _check_server_body(id, place, traces[id])


func test_a_body_in_the_middle_of_the_cabinet_is_put_out_in_a_step() -> void:
	await _land_and_check(MIDDLE)


func test_a_body_inside_a_face_of_the_cabinet_is_put_out_in_a_step() -> void:
	await _land_and_check(FRONT_FACE)


func test_a_body_inside_a_corner_of_the_cabinet_is_put_out_in_a_step() -> void:
	await _land_and_check(CORNER)


func test_a_bot_the_cabinet_landed_on_walks_off_by_itself() -> void:
	await _setup()
	await _land_on(MIDDLE)
	var body := _night.server.body_of(1)
	for _i in 6 * TICKS_PER_SECOND:
		_night.tick()
		await get_tree().physics_frame
	assert_bool(_solid().contains(body.global_position, BODY_RADIUS)).is_false()
	var from_middle := Vector2(body.global_position.x - MIDDLE.x, body.global_position.z - MIDDLE.z)
	assert_float(from_middle.length()).is_greater(5.0)


# --- the client's predicted body ---------------------------------------------------------------


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


## A server with the real socket and a client that plays player 1 and predicts its own body.
func _online() -> void:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_host.rules_tuning = _tuning()
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	_client = Night.new()
	_world().add_child(_client)
	var joined := await _client.start_remote(
		"ws://127.0.0.1:%d" % _host.listener.port(), Night.Mode.HUMAN, 30.0
	)
	assert_bool(joined).is_true()
	_host._collect(_host.server.rules.apply(RulesAction.skip_break()))
	await _until(func() -> bool: return _client.player() != null)
	for _i in 60:
		await get_tree().physics_frame


func _land_on_the_client(place: Vector3) -> void:
	await _online()
	var server_body := _host.server.body_of(1)
	var mine := _client.player()
	server_body.teleport(place)
	mine.teleport(place)
	_client.reconciler.reset()
	var rules := _host.server.rules
	rules.apply(RulesAction.grant_points(1, 10000))
	_host._collect(rules.apply(RulesAction.buy(1, &"crane_play")))
	assert_bool(await _until(func() -> bool: return rules.crane.spot == SPOT, 10.0)).is_true()
	var server_clear := -1
	var client_clear := -1
	var worst_gap := 0.0
	var worst_tick := 0.0
	var before := place
	for tick in WATCH_TICKS:
		await get_tree().physics_frame
		var at := mine.global_position
		var server_solid := _host.world.crane_block.solid
		if server_clear < 0 and not server_solid.contains(server_body.global_position, BODY_RADIUS):
			server_clear = tick
		if (
			client_clear < 0
			and _client.world.crane_block.spot() == SPOT
			and not _client.world.crane_block.solid.contains(at, BODY_RADIUS)
		):
			client_clear = tick
		worst_gap = maxf(worst_gap, at.distance_to(server_body.global_position))
		worst_tick = maxf(worst_tick, before.distance_to(at))
		before = at
	assert_int(server_clear).is_between(0, CLEAR_WITHIN)
	assert_int(client_clear).is_between(0, CLEAR_WITHIN + 2)
	# The client's cabinet and the server's are one and the same place, and so are the bodies.
	assert_float(mine.global_position.distance_to(server_body.global_position)).is_less(0.05)
	assert_float(worst_gap).is_less(MOST_MOVED)
	assert_float(worst_tick).is_less(MOST_MOVED)
	assert_int(_client.reconciler.corrections).is_less_equal(2)
	assert_float(_client.reconciler.worst_error).is_less(MOST_MOVED)
	assert_float(mine.global_position.y).is_less(0.05)
	assert_bool(_client.world.bounds.is_out(mine.global_position)).is_false()
	# And it walks: pressed in each of the four directions in turn, one of them takes it
	# at full speed away from the cabinet (the others may meet the cabinet's own face).
	var out := (
		Vector3(
			server_body.global_position.x - MIDDLE.x, 0.0, server_body.global_position.z - MIDDLE.z
		)
		. normalized()
	)
	var best := 0.0
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
		var start := mine.global_position
		Input.action_press(action)
		for _i in TICKS_PER_SECOND:
			await get_tree().physics_frame
		Input.action_release(action)
		best = maxf(best, (mine.global_position - start).dot(out))
		for _i in 20:
			await get_tree().physics_frame
	assert_float(best).is_greater(WALKS)
	assert_bool(_client.world.crane_block.solid.contains(mine.global_position)).is_false()


func test_the_clients_own_body_in_the_middle_of_the_cabinet_ends_where_the_servers_does() -> void:
	await _land_on_the_client(MIDDLE)


func test_the_clients_own_body_in_a_corner_of_the_cabinet_ends_where_the_servers_does() -> void:
	await _land_on_the_client(CORNER)
