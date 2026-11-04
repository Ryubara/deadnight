# The second map's twelve windows (formula rows 15 and 18): each is a barricade of five boards
# the rules know (`BarricadeTuning.ids`), solid for players while the boards stand and never a way
# out, with its dead rising 5 to 15 m outside it, where they tear the boards one by one and walk in
# to the room it opens into: on the ground floor and, for the upper windows, on the floor above.
extends GdUnitTestSuite

const SCENE := "res://world/smallmap/smallmap_greybox.tscn"
## Where the dead of a window should end: the room it opens into, by `metadata/room`.
const BOARDS := 5
## Row 18: a window's spawn stands this far outside it.
const SPAWN_FROM := 5.0
const SPAWN_TO := 15.0
const BOARD_LAYER := 2
## Metres inside a window the player stands for the dead to come to it.
const STAND_BEHIND := 2.5
## Windows the walking mesh does not join to the room behind them (the floor there is the
## stairwell's opening): a dead that rose at one comes in by the next window along, so its boards
## stand (#824).
const NO_WAY_IN: Array[StringName] = [&"upper_b1"]

var _night: Night
var _seated: SeatedNight


func after_test() -> void:
	if _night != null:
		_night.queue_free()
		_night = null
	if _seated != null:
		_seated.dispose()
		_seated = null


func _start() -> Night:
	_night = await SmallMapNight.start(self)
	SmallMapNight.run(_night, 20)
	return _night


func _room_rects(lot: Node3D) -> Dictionary:
	var found := {}
	for group in ["Start", "Side", "UpperA", "UpperB"]:
		var node := lot.get_node(group)
		var room := String(node.get_meta("room"))
		if not found.has(room):
			found[room] = []
		found[room].append([node.get_meta("rect") as Rect2, float(node.get_meta("floor"))])
	return found


func test_twelve_windows_are_barricades_of_five_boards_the_rules_list() -> void:
	await _start()
	var world := _night.world
	var listed := _night.server.rules.tuning.barricades
	assert_int(world.barricade_ids().size()).is_equal(12)
	assert_int(listed.boards).is_equal(BOARDS)
	for id in listed.ids:
		var barricade := world.barricade(id)
		assert_object(barricade).override_failure_message(String(id)).is_not_null()
		assert_int(barricade.capacity()).is_equal(BOARDS)
		assert_int(barricade.boards()).is_equal(BOARDS)
		assert_float(barricade.board_half).override_failure_message(String(id)).is_equal(0.75)
		assert_int(_night.server.rules.barricades.boards_of(id)).is_equal(BOARDS)


func test_the_windows_are_five_in_the_hall_three_in_the_side_room_and_four_upstairs() -> void:
	await _start()
	var counts := {}
	for node in _night.world.greybox.find_children("*", "Barricade", true, false):
		var room := String(node.get_parent().get_meta("room"))
		counts[room] = int(counts.get(room, 0)) + 1
	assert_dict(counts).is_equal({"start": 5, "side": 3, "upstairs": 4})


func test_boards_are_solid_for_players_while_up_and_gone_when_torn() -> void:
	await _start()
	for id in _night.world.barricade_ids():
		var barricade := _night.world.barricade(id)
		for board in barricade.get_children():
			if board is StaticBody3D:
				assert_int((board as StaticBody3D).collision_layer).is_equal(BOARD_LAYER)
		barricade.set_boards(0, false)
		for board in barricade.get_children():
			if board is StaticBody3D:
				assert_int((board as StaticBody3D).collision_layer).is_equal(0)
				assert_bool((board as StaticBody3D).visible).is_false()
		barricade.set_boards(BOARDS, false)
		assert_int(barricade.boards()).is_equal(BOARDS)


func test_a_torn_window_is_still_no_way_out_for_a_player() -> void:
	await _start()
	var lot := _night.world.greybox
	for node in lot.get_node("Windows").get_children():
		var blocker := node.get_node("Blocker") as StaticBody3D
		assert_int(blocker.collision_layer).override_failure_message(node.name).is_equal(
			BOARD_LAYER
		)
		# The players-only blocker fills the opening above the sill, whatever the boards do.
		var shape := (blocker.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
		assert_float(shape.size.x).is_greater_equal(1.2)
		assert_float(shape.size.y).is_greater_equal(1.2)


func test_every_spawn_stands_5_to_15_metres_outside_its_own_window() -> void:
	await _start()
	var world := _night.world
	var gates := world.spawn_gates()
	assert_int(gates.size()).is_equal(12)
	var rooms := _room_rects(world.greybox)
	for point: Vector3 in gates:
		var id: StringName = gates[point]
		var barricade := world.barricade(id)
		var out := -barricade.depth_of(point)
		assert_float(out).override_failure_message("%s: %.1f m outside" % [id, out]).is_between(
			SPAWN_FROM, SPAWN_TO
		)
		# Outside the building: not inside any room's rectangle on that floor.
		var floor_y: float = barricade.global_position.y
		assert_float(absf(point.y - floor_y)).is_less(0.1)
		for entry: Array in rooms[String(barricade.get_parent().get_meta("room"))]:
			var rect: Rect2 = entry[0]
			if absf(float(entry[1]) - floor_y) < 0.1:
				assert_bool(rect.has_point(Vector2(point.x, point.z))).is_false()


func test_with_every_link_sold_the_map_leads_from_each_window_to_the_hall() -> void:
	# The dead path over the navigation map the tick it is asked, on every machine: the map takes
	# meshes in on the physics step (not a worker thread, which dropped the last of several swaps
	# made in one go and left the upper floor and the side room cut off: #733, #736).
	_seated = await SmallMapNight.seat(self, 1, null, 5)
	for item in _seated.server.rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			_seated.open_door(item.id)
	await _seated.settle(10)
	var map := _seated.world.map()
	assert_bool(NavigationServer3D.map_get_use_async_iterations(map)).is_false()
	var hall := _seated.world.player_spawn(0)
	var gates := _seated.world.spawn_gates()
	assert_int(gates.size()).is_equal(12)
	for point: Vector3 in gates:
		var way := NavigationServer3D.map_get_path(map, point, hall, true)
		var end := way[way.size() - 1] if not way.is_empty() else point
		(
			assert_float(Vector2(end.x - hall.x, end.z - hall.z).length())
			. override_failure_message(
				"%s: the way ends %.1f m from the hall" % [gates[point], end.distance_to(hall)]
			)
			. is_less(1.0)
		)


func test_the_dead_come_in_through_every_window_to_the_room_it_opens_into() -> void:
	# A night of 24 dead at once on the whole map, a player who cannot fall standing in each window's
	# room in turn, a metre or two behind it: the dead come to that window, tear its five boards and
	# walk through into the right room, up stairs and all. (A player in the hall draws the dead of
	# every window on that wall to the one window the way to the hall is shortest by: a dead that
	# comes to another window than the one it rose at tears that one, #810.)
	var tuning := RulesFixture.tuning()
	tuning.health.max_health = 1000000.0
	tuning.rounds.count_base = 400.0
	tuning.rounds.spawn_interval_start = 0.3
	tuning.rounds.spawn_interval_min = 0.3
	tuning.rounds.first_spawn_delay = 0.2
	_seated = await SmallMapNight.seat(self, 1, tuning, 5)
	for item in _seated.server.rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			_seated.open_door(item.id)
	await _seated.settle(30)
	_seated.start_round()
	var rooms := _room_rects(_seated.world.greybox)
	var came_from := {}  # zombie id -> the window it rose at
	var through := {}  # window id -> the room positions of the dead that came in by it
	var torn := {}
	_seated.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"board_torn":
			torn[event["barricade_id"]] = true
	var sim := _seated.server.sim
	var windows: Array = _seated.world.spawn_gates().values().filter(
		func(id: StringName) -> bool: return not NO_WAY_IN.has(id)
	)
	var wanted := windows.size()
	var turn := 0
	_stand_behind(windows[turn])
	for tick in 5400:
		_seated.tick()
		if turn < windows.size() and torn.has(windows[turn]) and through.has(windows[turn]):
			turn += 1
			if turn < windows.size():
				_stand_behind(windows[turn])
		if tick % 30 == 0:
			await get_tree().physics_frame
		for zombie: ZombieBody in sim.zombies.values():
			if zombie.gate_id != &"":
				came_from[zombie.id] = zombie.gate_id
			elif came_from.has(zombie.id):
				var id: StringName = came_from[zombie.id]
				# Over the sill and down the far side (#915): the floor is read where it is flat again.
				var sill := _seated.world.barricade(id)
				var flat_from := (
					sill.thickness * 0.5 + ZombieGate.BODY_CLEARANCE + ZombieGate.CLIMB_RAMP
				)
				if sill.depth_of(zombie.position) < flat_from:
					continue
				if not through.has(id):
					through[id] = zombie.position
				# In, and put down at the door, so the next ones can rise (the cap is 24).
				came_from.erase(zombie.id)
				RulesFixture.kill(_seated.server.rules, 1, zombie.id)
		if through.size() >= wanted and torn.size() >= wanted:
			break
	for id: StringName in windows:
		assert_bool(torn.has(id)).override_failure_message("%s was not torn" % id).is_true()
		assert_bool(through.has(id)).override_failure_message("%s: none came in" % id).is_true()
	for id: StringName in through:
		var barricade := _seated.world.barricade(id)
		var at: Vector3 = through[id]
		# On the inside of the boards, and on the floor the window is on.
		assert_float(barricade.depth_of(at)).override_failure_message(String(id)).is_greater(0.0)
		(
			assert_float(absf(at.y - barricade.global_position.y))
			. override_failure_message(
				(
					"%s: the dead stand at height %.2f, the window is at %.2f"
					% [id, at.y, barricade.global_position.y]
				)
			)
			. is_less(0.8)
		)


## Puts the player on the inside of window `id`, in the room it opens into.
func _stand_behind(id: StringName) -> void:
	var barricade := _seated.world.barricade(id)
	var at := barricade.centre() + barricade.inward() * STAND_BEHIND
	_seated.server.body_of(1).teleport(Vector3(at.x, barricade.global_position.y + 0.1, at.z))
