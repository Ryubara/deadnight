# A night at its fullest, 8 people and the 7 bots a host may set (15 bodies, `NightHost.MAX_SEATS`),
# starts with nobody inside anybody and nobody out of bounds, on every map a night can be played on
# (issue #1193). A map lists its start markers in its scene (`MapLayout.player_markers`); the 9th
# body to sit down used to share the 1st one's marker, and a seat that opened again after a leave
# shared the marker of a body already there (the slot was the count of bodies, not a free marker).
extends GdUnitTestSuite

const SEED := 1193
## Bodies are capsules of 0.35 m radius that do not push each other (layer 4 against a mask of the
## world's 1 and 2); two starts closer than this stack two soldiers into one.
const MIN_APART := 1.0
## A start this far from the walkable mesh is at the edge of a wall or off the floor (metres, flat).
const ON_MESH := 0.2
const BODY_RADIUS := 0.35
## A start has this much room round the body (metres): one at the very edge of a car is a soldier
## drawn through the car.
const ELBOW := 0.3
const BODY_HEIGHT := 1.8
const WORLD_MASK := 3
## Ticks the bodies fall and settle for before the second look.
const SETTLE_TICKS := 60


## A night on `info`'s map with the 8 people seated, then the bots `NightBots` seats: the 15 bodies
## of a full room, in the order a room fills (people first).
func _full_night(info: MapInfo, people := NightHost.MAX_PLAYERS) -> Dictionary:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	var night := await NightFixture.seat(self, people, tuning, SEED, false, info.load_scene())
	var bots := NightBots.new(night.server, night.world, SEED, func(_events: Array) -> void: pass)
	bots.fill(MatchSettings.MAX_BOTS)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return {"night": night, "bots": bots}


func _ids(night: SeatedNight, bots: NightBots) -> Array[int]:
	var ids: Array[int] = []
	for id in night.server.rules.players:
		ids.append(id)
	assert_int(ids.size()).is_equal(NightHost.MAX_PLAYERS + bots.count())
	return ids


## What is wrong with where the bodies stand, one line each: two inside each other, one inside a
## wall or off the floor, one out of bounds.
func _faults(night: SeatedNight, ids: Array[int]) -> Array[String]:
	var faults: Array[String] = []
	var space := night.world.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS + ELBOW
	capsule.height = BODY_HEIGHT
	for i in ids.size():
		var at := night.server.body_of(ids[i]).global_position
		if night.world.bounds.is_out(at):
			faults.append("%d stands out of bounds at %s" % [ids[i], at])
		var mesh := NavigationServer3D.map_get_closest_point(night.world.map(), at)
		if Vector2(mesh.x - at.x, mesh.z - at.z).length() > ON_MESH:
			faults.append("%d is %s off the walkable mesh at %s" % [ids[i], mesh - at, at])
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (BODY_HEIGHT * 0.5 + 0.05))
		query.collision_mask = WORLD_MASK
		if not space.intersect_shape(query, 1).is_empty():
			faults.append("%d stands inside the map's geometry at %s" % [ids[i], at])
		for j in range(i + 1, ids.size()):
			var other := night.server.body_of(ids[j]).global_position
			var apart := Vector2(at.x - other.x, at.z - other.z).length()
			if apart < MIN_APART and absf(at.y - other.y) < BODY_HEIGHT:
				faults.append("%d and %d stand %.2f m apart at %s" % [ids[i], ids[j], apart, at])
	return faults


func test_fifteen_bodies_start_apart_and_in_bounds_on_every_map() -> void:
	var maps := MapRegistry.playable()
	assert_int(maps.size()).is_greater_equal(2)
	for info in maps:
		var built := await _full_night(info)
		var night: SeatedNight = built["night"]
		var ids := _ids(night, built["bots"])
		var faults := _faults(night, ids)
		# Again once the bodies have fallen and settled on the floor.
		night.run(SETTLE_TICKS)
		faults.append_array(_faults(night, ids))
		(
			assert_array(faults)
			. override_failure_message("%s: %s" % [info.id, "\n".join(faults)])
			. is_empty()
		)
		night.dispose()


func test_a_seat_that_opens_again_takes_a_free_start_not_one_in_use() -> void:
	for info in MapRegistry.playable():
		var night := await NightFixture.seat(
			self, 6, RulesFixture.tuning(), SEED, false, info.load_scene()
		)
		# The 2nd and 4th go, and two people come: they take the markers just freed, in order.
		night.server.apply({"type": NightServer.LEAVE, "player_id": 2})
		night.server.apply({"type": NightServer.LEAVE, "player_id": 4})
		night.server.apply({"type": NightServer.JOIN, "player_id": 7, "local": false})
		night.server.apply({"type": NightServer.JOIN, "player_id": 8, "local": false})
		await get_tree().physics_frame
		var starts: Array[Vector3] = []
		for id in [1, 3, 5, 6, 7, 8]:
			starts.append(night.server.body_of(id).global_position)
		assert_vector(starts[4]).is_equal_approx(night.world.player_spawn(1), Vector3.ONE * 0.05)
		assert_vector(starts[5]).is_equal_approx(night.world.player_spawn(3), Vector3.ONE * 0.05)
		var faults := _faults(night, [1, 3, 5, 6, 7, 8] as Array[int])
		(
			assert_array(faults)
			. override_failure_message("%s: %s" % [info.id, "\n".join(faults)])
			. is_empty()
		)
		night.dispose()
