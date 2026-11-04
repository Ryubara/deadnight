# What a second client sees of a re-cut weapon's elements, over a real WebSocket on this machine
# (#794): the server judges the burst, the arc and the fire; every client draws them from the events
# and the name and numbers from the frame. The server and each client live in their own SubViewport
# world; the clients are `Night`s that joined with `start_remote`.
extends GdUnitTestSuite

const A := 1
const B := 2

var _host: NightHost
var _nights: Array[Night] = []
var _commands: Dictionary = {}


func after_test() -> void:
	for night in _nights:
		if is_instance_valid(night):
			night.get_parent().queue_free()
	_nights.clear()
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


func _server() -> NightHost:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	_world().add_child(_host)
	await _until(func() -> bool: return _host.serving, 30.0)
	return _host


func _client() -> Night:
	var night := Night.new()
	_world().add_child(night)
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	assert_bool(await night.start_remote(url, Night.Mode.MANUAL, 30.0)).is_true()
	_nights.append(night)
	# A hand-driven client sends its (empty) command every tick, as the server expects.
	_commands[night] = NightCommand.new()
	night.ticked.connect(
		func() -> void: night.link.send((_commands[night] as NightCommand).to_dict())
	)
	return night


## A zombie the server's night has, for the shot to land on.
func _a_zombie() -> ZombieBody:
	for zombie: ZombieBody in _host.server.sim.zombies.values():
		if zombie.is_alive():
			return zombie
	return null


func _fx_of(night: Night, kind: ElementFx.Kind) -> Array[ElementFx]:
	var found: Array[ElementFx] = []
	for fx: ElementFx in night.find_children("*", "ElementFx", true, false):
		if fx.kind == kind:
			found.append(fx)
	return found


func _flames_on(night: Night, zombie_id: int) -> Array[ElementFx]:
	var found: Array[ElementFx] = []
	for fx in _fx_of(night, ElementFx.Kind.BURN):
		if fx.burns(zombie_id):
			found.append(fx)
	return found


func _status_of(night: Night, zombie_id: int) -> int:
	var view := night.view.horde.view_of(zombie_id)
	return view.status() if view != null else -1


func test_the_other_client_sees_the_name_and_draws_the_burst_of_a_re_cut_revolver() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return b.avatars.ids().has(A))).is_true()
	var server := _host.server
	server._combat(CombatAction.give_weapon(A, &"pistol"))
	server._combat(CombatAction.upgrade_weapon(A, &"pistol"))
	# B is told by the frame: A's revolver is re-cut (the tier), and the name is the profile's.
	var told := await _until(
		func() -> bool:
			var arms: Dictionary = b.state.frame["players"][A].get("arms", {})
			return arms.has(&"pistol") and int(arms[&"pistol"][2]) == 1
	)
	assert_bool(told).is_true()
	# A zombie of the server's night stands 3 m ahead of A (held still, off the fence), A fires at it
	# with the real command, and B hears the burst and draws it from the event alone.
	assert_bool(await _until(func() -> bool: return _a_zombie() != null, 60.0)).is_true()
	var zombie := _a_zombie()
	zombie.gate_id = &""
	zombie.speed = 0.0
	var at: Vector3 = (server._bodies[A] as Node3D).global_position
	zombie.position = at + Vector3(0.0, 0.0, -3.0)
	var command := _commands[a] as NightCommand
	command.aim_along(Vector3(0.0, 0.0, -1.0))
	command.fire = true
	# Both clients draw it, each from the same event: poll until both show a blast.
	var drawn := await _until(
		func() -> bool:
			return (
				not _fx_of(b, ElementFx.Kind.BLAST).is_empty()
				and not _fx_of(a, ElementFx.Kind.BLAST).is_empty()
			)
	)
	command.fire = false
	assert_bool(drawn).override_failure_message("a client drew no blast").is_true()
	var blast := _fx_of(b, ElementFx.Kind.BLAST)[0]
	assert_bool(blast.tint.is_equal_approx(ElementCatalog.get_def(&"explosive").tint)).is_true()


func test_the_other_client_sees_the_flames_on_the_zombie_a_re_cut_pump_set_alight() -> void:
	await _server()
	var a := await _client()
	var b := await _client()
	assert_bool(await _until(func() -> bool: return b.avatars.ids().has(A))).is_true()
	var server := _host.server
	server._combat(CombatAction.give_weapon(A, &"pump_870"))
	server._combat(CombatAction.upgrade_weapon(A, &"pump_870"))
	server._combat(CombatAction.equip(A, &"pump_870"))
	assert_bool(await _until(func() -> bool: return _a_zombie() != null, 60.0)).is_true()
	var zombie := _a_zombie()
	# A zombie that outlasts the shell, held still 3 m ahead of A and off the fence.
	zombie.gate_id = &""
	zombie.speed = 0.0
	server.rules._zombies[zombie.id].health = 100000.0
	var at: Vector3 = (server._bodies[A] as Node3D).global_position
	zombie.position = at + Vector3(0.0, 0.0, -3.0)
	var command := _commands[a] as NightCommand
	command.aim_along(Vector3(0.0, 0.0, -1.0))
	command.fire = true
	# Both clients draw the flames from the one `element_burn` event, on that zombie.
	var both := func() -> bool:
		return not _flames_on(a, zombie.id).is_empty() and not _flames_on(b, zombie.id).is_empty()
	var drawn := await _until(both)
	command.fire = false
	assert_bool(drawn).override_failure_message("a client drew no flames").is_true()
	var flames := _flames_on(b, zombie.id)
	# One fire a zombie, in the element's colour, though the pump fired again meanwhile.
	assert_int(flames.size()).is_equal(1)
	assert_bool(flames[0].tint.is_equal_approx(ElementCatalog.get_def(&"fire").tint)).is_true()
	# The zombie's own view wears the burning shell the snapshot's status byte tells.
	var burning := StatusCatalog.get_def(&"burning").wire
	var shell := await _until(func() -> bool: return _status_of(b, zombie.id) == burning)
	assert_bool(shell).is_true()
