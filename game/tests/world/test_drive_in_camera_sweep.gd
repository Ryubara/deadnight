# The shoulder camera over the whole lot (issue #157): at every place the player can stand, in
# every direction, on either shoulder, normal and aimed, the lens is out of the walls and cars and
# either sees the player's head or is so close to it that the body is hidden.
extends GdUnitTestSuite

## Grid step in metres, and the lot's extent to sample (the navigation bake's box).
const STEP := 2.0
const FROM := Vector2(-66.0, -56.0)
const TO := Vector2(66.0, 68.0)
## Only places within this distance of some geometry matter: in open air nothing is near the lens.
const NEAR := 3.2
## How near a sample must be to the navigation mesh to count as a place the player stands: the mesh
## keeps a body radius from every wall, so a sample inside a wall is farther than this.
const ON_MESH := 0.15
const YAWS := 8
const PITCHES := [-35.0, 0.0, 35.0]

var _lot: Node3D
var _nav: LotNavigation


func before_test() -> void:
	# Every door sold: the player can stand anywhere the navigation reaches from the apron.
	_lot = await LotFixture.make_lot(self, LotFixture.door_table().keys())
	auto_free(_lot.get_parent())
	_nav = LotNavigation.new(_lot, CameraProbe.body_radius())
	await _nav.settle(get_tree())


func test_the_lens_is_never_in_geometry_and_the_head_is_seen_or_the_body_hidden() -> void:
	var space := _lot.get_world_3d().direct_space_state
	var tuning := CameraProbe.tuning()
	var places := _places(space)
	assert_int(places.size()).is_greater(100)  # the sweep really covers the lot
	var failures := []
	var closest := INF
	for feet: Vector3 in places:
		for yaw_index in YAWS:
			for pitch: float in PITCHES:
				for side: float in [1.0, -1.0]:
					for aim in [false, true]:
						var rig := CameraProbe.rig(
							space,
							feet,
							TAU * yaw_index / YAWS,
							side,
							deg_to_rad(pitch),
							tuning.arm_length_aim if aim else tuning.arm_length,
							tuning.shoulder_offset_aim if aim else tuning.shoulder_offset
						)
						var lens: Vector3 = rig["camera"]
						var head_distance := lens.distance_to(rig["pivot"])
						closest = minf(closest, head_distance)
						var hidden := head_distance < tuning.hide_body_distance
						if CameraProbe.in_geometry(space, lens) or (not hidden and not rig["free"]):
							failures.append(
								(
									"%s yaw %d pitch %d side %d aim %s"
									% [feet, yaw_index, pitch, side, aim]
								)
							)
	(
		assert_array(failures)
		. override_failure_message(
			"%d of the samples: %s" % [failures.size(), failures.slice(0, 8)]
		)
		. is_empty()
	)
	# Negative control: places the sweep reaches include ones that pull the lens to the head.
	assert_float(closest).is_less(tuning.hide_body_distance)


## Standing places on a grid that are near geometry (and so could squeeze the camera).
func _places(space: PhysicsDirectSpaceState3D) -> Array[Vector3]:
	var places: Array[Vector3] = []
	var near := SphereShape3D.new()
	near.radius = NEAR
	var x := FROM.x
	while x <= TO.x:
		var z := FROM.y
		while z <= TO.y:
			# The floor, not the top of a wall or a car: look from just above it.
			var top := Vector3(x, 0.4, z)
			var ground := space.intersect_ray(
				PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 1.0)
			)
			if (
				not ground.is_empty()
				and CameraProbe.body_fits(space, ground["position"])
				and _nav.can_reach(LotFixture.START, ground["position"], ON_MESH)
			):
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = near
				query.transform = Transform3D(Basis.IDENTITY, ground["position"] + Vector3.UP * 1.5)
				if not space.intersect_shape(query, 1).is_empty():
					places.append(ground["position"])
			z += STEP
		x += STEP
	return places
