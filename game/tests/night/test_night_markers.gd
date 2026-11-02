# The HUD's world markers over a night: names over the other players' heads, the next door with its
# distance, the pin at the edge, and damage numbers that stay on their wound while the camera turns.
# Everything is read from the real camera of the real night.
extends GdUnitTestSuite

const DOOR := &"door_concession"
## Where the player stands: 30 m short of the concession's door. Yaw PI faces the door.
const FIELD := Vector3(0.0, 0.1, -30.0)
const UNIT := Rect2(0.0, 0.0, 1.0, 1.0)

var _night: Night
var _hud: Hud


func before_test() -> void:
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(_hud)
	_night = await NightFixture.start(self, Night.Mode.MANUAL, null, 7, _hud)
	NightFixture.run(_night, 5)


func after_test() -> void:
	_night.queue_free()
	_hud.queue_free()


## The player stands at `at` looking along `yaw`, through the camera the viewport uses.
func _stand(at: Vector3, yaw: float) -> void:
	var player := _night.player()
	player.teleport(at)
	player.camera_rig.yaw = yaw
	for _i in 30:
		player.camera_rig.step(1.0 / 60.0, 1.0)
	NightFixture.run(_night, 2)
	player.camera_rig.camera().make_current()


## A second player standing at `at`, called `player_name`.
func _join(at: Vector3, player_name: String) -> void:
	_night.link.send({"type": NightServer.JOIN, "player_id": 2, "local": false})
	NightFixture.run(_night, 2)
	_hud.state.set_player_name(2, player_name)
	_night.server.body_of(2).teleport(at)
	NightFixture.run(_night, 2)


## Two rendered frames: the first starts after the idle signal, so the markers are pushed in the
## second at the latest.
func _frames() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _marker(id: StringName) -> Dictionary:
	for marker in _night.markers.markers():
		if marker["id"] == id:
			return marker
	return {}


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d()


## Where the real camera puts `point`, as a share of the screen.
func _share(point: Vector3) -> Vector2:
	return _camera().unproject_position(point) / _camera().get_viewport().get_visible_rect().size


func test_a_teammates_name_is_projected_from_the_real_camera() -> void:
	_join(Vector3(2.0, 0.1, -20.0), "Moe")
	_stand(FIELD, PI)
	var marker := _marker(&"player_2")
	assert_str(marker["label"]).is_equal("Moe")
	assert_str(marker["kind"]).is_equal("ally")
	var head := _night.server.body_of(2).global_position + Vector3(0.0, 2.15, 0.0)
	var expected := _share(head)
	assert_float(marker["x"]).is_equal_approx(expected.x, 0.01)
	assert_float(marker["y"]).is_equal_approx(expected.y, 0.01)
	assert_float(marker["distance"]).is_equal_approx(10.2, 0.5)
	assert_bool(UNIT.has_point(Vector2(marker["x"], marker["y"]))).is_true()


func test_the_name_stays_on_the_head_while_the_camera_turns() -> void:
	_join(Vector3(0.0, 0.1, -20.0), "Moe")
	_stand(FIELD, PI)
	var before := _marker(&"player_2")
	_stand(FIELD, PI + 0.12)
	var after := _marker(&"player_2")
	assert_float(absf(float(after["x"]) - float(before["x"]))).is_greater(0.02)
	var head := _night.server.body_of(2).global_position + Vector3(0.0, 2.15, 0.0)
	assert_float(after["x"]).is_equal_approx(_share(head).x, 0.01)


func test_a_name_off_the_screen_is_not_drawn_and_one_on_it_is() -> void:
	_join(Vector3(0.0, 0.1, -20.0), "Moe")
	_stand(FIELD, 0.0)
	await _frames()
	assert_dict(_hud.markers.marker_at(&"player_2")).is_empty()
	_stand(FIELD, PI)
	await _frames()
	assert_bool(_hud.markers.marker_at(&"player_2").has("at")).is_true()


func test_the_next_door_is_marked_with_its_name_and_the_distance_to_it() -> void:
	_stand(FIELD, PI)
	var door := _marker(DOOR)
	assert_str(door["label"]).is_equal("Concession stand")
	assert_str(door["kind"]).is_equal("objective")
	assert_bool(door["important"]).is_true()
	var at: Vector3 = _night.world.door_points(DOOR)[0]
	assert_float(door["distance"]).is_equal_approx(_night.state.position().distance_to(at), 0.01)
	# Doors that need another open first are not on offer yet.
	assert_dict(_marker(&"door_booth")).is_empty()
	assert_dict(_marker(&"door_yard")).is_empty()


func test_an_open_door_loses_its_marker_and_the_doors_behind_it_get_theirs() -> void:
	_stand(FIELD, PI)
	_night.state.apply_events([{"type": &"door_opened", "door_id": DOOR}])
	assert_dict(_marker(DOOR)).is_empty()
	assert_dict(_marker(&"door_booth")).is_not_empty()
	assert_dict(_marker(&"door_yard")).is_not_empty()
	assert_dict(_marker(&"door_back_lot")).is_empty()


func test_one_door_is_the_important_one_and_it_pins_to_the_bottom_when_it_is_behind() -> void:
	_night.state.apply_events([{"type": &"door_opened", "door_id": DOOR}])
	_stand(FIELD, 0.0)
	await _frames()
	var important: Array[StringName] = []
	for marker in _night.markers.markers():
		if marker["important"]:
			important.append(marker["id"])
	assert_int(important.size()).is_equal(1)
	# Facing away from the lot the door is behind: pinned inside the screen, toward the bottom.
	var pinned := _hud.markers.marker_at(important[0])
	assert_bool(pinned["pinned"]).is_true()
	assert_float(pinned["at"].y).is_greater(_hud.markers.size.y * 0.5)
	assert_bool(Rect2(Vector2.ZERO, _hud.markers.size).has_point(pinned["at"])).is_true()


func test_a_pinned_marker_keeps_out_of_the_corners_where_the_cards_stand() -> void:
	var list: Array[Dictionary] = []
	for x: float in [-0.4, 0.0, 0.5, 1.0, 1.4]:
		for y: float in [-0.4, 0.0, 0.5, 1.0, 1.4]:
			if not UNIT.has_point(Vector2(x, y)):
				(
					list
					. append(
						{
							"id": StringName("m_%s_%s" % [x, y]),
							"kind": &"objective",
							"x": x,
							"y": y,
							"distance": 20.0,
							"label": "",
							"important": true,
						}
					)
				)
	_hud.state.set_markers(list)
	var size := _hud.markers.size
	var top := minf(HudMarkers.TOP_CLEAR, size.y * 0.5)
	var bottom := maxf(size.y - HudMarkers.BOTTOM_CLEAR, size.y * 0.5)
	var side := minf(HudMarkers.SIDE_CLEAR, size.x * 0.5)
	for marker in list:
		var at: Vector2 = _hud.markers.marker_at(marker["id"])["at"]
		var on_a_side := (
			is_equal_approx(at.x, HudMarkers.EDGE_INSET)
			or is_equal_approx(at.x, size.x - HudMarkers.EDGE_INSET)
		)
		if on_a_side:
			assert_float(at.y).is_between(top - 0.5, bottom + 0.5)
		else:
			assert_float(at.x).is_between(side - 0.5, size.x - side + 0.5)


func test_a_damage_number_is_over_the_zombie_and_follows_the_camera() -> void:
	var zombie := _zombie_in_view()
	_night.state.apply_events([_hit(zombie["id"], "head")])
	var number: Dictionary = _hud.crosshair.numbers.back()
	var world: Vector3 = number["world"]
	var lifted: Vector3 = zombie["position"] + Vector3(0.0, NightHudBinding.HEAD_HEIGHT, 0.0)
	assert_vector(world).is_equal_approx(lifted, Vector3(0.01, 0.01, 0.01))
	var nudge := Vector2(number["nudge"], 0.0)
	var here := _hud.crosshair.number_at(number)
	var size := _hud.crosshair.size
	assert_vector(here).is_equal_approx(_share(world) * size + nudge, Vector2(0.01, 0.01))
	# The camera turns: the number is elsewhere on the screen, over the same point of the world.
	_stand(FIELD, _yaw_toward(world) + 0.05)
	var moved := _hud.crosshair.number_at(number)
	assert_float(moved.distance_to(here)).is_greater(5.0)
	assert_vector(moved).is_equal_approx(_share(world) * size + nudge, Vector2(0.01, 0.01))


func test_a_number_for_a_hit_behind_the_camera_is_not_drawn() -> void:
	var zombie := _zombie_in_view()
	_night.state.apply_events([_hit(zombie["id"], "body")])
	var number: Dictionary = _hud.crosshair.numbers.back()
	assert_bool(_hud.crosshair.number_at(number).is_finite()).is_true()
	# Turned right round, the same point is behind the lens.
	_stand(FIELD, _yaw_toward(number["world"]) + PI)
	assert_bool(_camera().is_position_behind(number["world"])).is_true()
	assert_bool(_hud.crosshair.number_at(number).is_finite()).is_false()


## The first zombie of the night, once it is on the lot, with the camera turned to look at it from
## the field.
func _zombie_in_view() -> Dictionary:
	var id := NightFixture.first_zombie(_night)
	assert_int(id).is_greater(0)
	NightFixture.run(_night, 3)
	var zombie: Dictionary = {}
	for entry in _night.state.zombies:
		if entry["id"] == id:
			zombie = entry
	_stand(FIELD, _yaw_toward(zombie["position"]))
	return zombie


## The yaw that faces `point` from the field.
func _yaw_toward(point: Vector3) -> float:
	return atan2(-(point.x - FIELD.x), -(point.z - FIELD.z))


func _hit(zombie_id: int, zone: String) -> Dictionary:
	return {
		"type": &"zombie_damaged",
		"zombie_id": zombie_id,
		"zombie_type": &"walker",
		"player_id": 1,
		"zone": zone,
		"damage": 60.0,
		"health": 20.0,
	}
