# A frozen zombie on the other player's screen, over a real WebSocket on this machine (#788): the
# server and each client live in their own SubViewport world, the clients are `Night`s that joined
# with `start_remote`. Player A shoots a zombie with the freeze gun; B must see it frozen (the
# snapshot's status, the view's shell and held pose), see it thaw after three seconds, and see it
# shatter when A shoots it again: the pieces fly and no body is left.
extends GdUnitTestSuite

const A := 1
const B := 2
const AHEAD := 6.0

var _host: NightHost
var _nights: Array[Night] = []
var _commands: Dictionary = {}


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
	_commands.clear()
	if is_instance_valid(_host):
		_host.get_parent().queue_free()
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _until(condition: Callable, seconds: float = 10.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().physics_frame
	return true


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _server() -> NightHost:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	var tuning := RulesFixture.tuning()
	tuning.rounds.health_base = 600.0
	_host.rules_tuning = tuning
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


func _client() -> Night:
	var night := Night.new()
	_world().add_child(night)
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	assert_bool(await night.start_remote(url, Night.Mode.MANUAL, 30.0)).is_true()
	_nights.append(night)
	_commands[night] = NightCommand.new()
	night.ticked.connect(
		func() -> void: night.link.send((_commands[night] as NightCommand).to_dict())
	)
	return night


func _zombie_body(id: int) -> ZombieBody:
	return _host.server.sim.zombies.get(id)


func _entry_on(night: Night, id: int) -> Dictionary:
	for entry in night.state.zombies:
		if entry["id"] == id:
			return entry
	return {}


## Stands the first zombie of the night still, `AHEAD` metres in front of player A on the server.
func _zombie_in_front_of() -> int:
	_host.server.rules.apply(RulesAction.skip_break())
	var found := await _until(func() -> bool: return not _host.server.sim.zombies.is_empty(), 30.0)
	assert_bool(found).is_true()
	var id: int = _host.server.sim.zombies.keys()[0]
	await _ticks(200)
	var body := _zombie_body(id)
	body.position = _host.server.body_of(A).global_position + Vector3(0.0, 0.0, AHEAD)
	body.speed = 0.0
	return id


## A holds the trigger at the zombie until a shot of this weapon has left.
func _fire_at(a: Night, id: int) -> void:
	var shots := _host.server._shot_seq[A]
	var command := _commands[a] as NightCommand
	var eye := _host.server.body_of(A).global_position + Vector3(0.0, Autopilot.EYE, 0.0)
	command.origin = eye
	command.aim_along(_zombie_body(id).position + Vector3(0.0, Autopilot.CHEST, 0.0) - eye)
	command.fire = true
	var fired := await _until(func() -> bool: return _host.server._shot_seq[A] > shots, 5.0)
	command.fire = false
	assert_bool(fired).is_true()
	# The bolt flies the six metres and bursts.
	await _ticks(30)


func test_the_other_player_sees_the_zombie_frozen_then_thawed() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	await _until(func() -> bool: return b.avatars.ids().has(A))
	_host.server._combat(CombatAction.give_weapon(A, &"freeze_gun"))
	var id := await _zombie_in_front_of()
	await _fire_at(a, id)
	var wire := StatusCatalog.get_def(&"frozen").wire
	assert_int(_zombie_body(id).status).is_equal(wire)
	var on_b := await _until(func() -> bool: return _entry_on(b, id).get("status", 0) == wire)
	assert_bool(on_b).override_failure_message("B's snapshot never carried the freeze").is_true()
	var view := b.view.horde.view_of(id)
	assert_object(view).is_not_null()
	assert_int(view.status()).is_equal(wire)
	assert_bool(view.is_held()).is_true()
	# The freeze runs out on the server and B's picture follows.
	_zombie_body(id).speed = 2.0
	var thawed := await _until(func() -> bool: return _entry_on(b, id).get("status", 0) == 0, 10.0)
	assert_bool(thawed).override_failure_message("B's zombie never thawed").is_true()
	assert_int(view.status()).is_equal(StatusDef.NONE)
	assert_bool(view.is_held()).is_false()


func test_the_other_player_sees_the_zombie_shatter() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	await _until(func() -> bool: return b.avatars.ids().has(A))
	_host.server._combat(CombatAction.give_weapon(A, &"freeze_gun"))
	var heard: Array[StringName] = []
	b.state.event_received.connect(func(event: Dictionary) -> void: heard.append(event["type"]))
	var id := await _zombie_in_front_of()
	await _fire_at(a, id)
	var wire := StatusCatalog.get_def(&"frozen").wire
	await _until(func() -> bool: return _entry_on(b, id).get("status", 0) == wire)
	# Another gun's shot kills a frozen zombie (the freeze gun's own bolt only keeps it frozen).
	_host.server._combat(CombatAction.equip(A, &"house_pistol"))
	await _ticks(40)
	await _fire_at(a, id)
	assert_bool(_host.server.sim.zombies.has(id)).is_false()
	var seen := await _until(func() -> bool: return heard.has(&"zombie_shattered"))
	assert_bool(seen).override_failure_message("B never heard the zombie shatter").is_true()
	assert_int(b.view.effects.shards.live_count()).is_greater(0)
	var gone := await _until(func() -> bool: return b.view.horde.view_of(id) == null)
	assert_bool(gone).override_failure_message("B still draws a body").is_true()
	assert_dict(_entry_on(b, id)).is_empty()
