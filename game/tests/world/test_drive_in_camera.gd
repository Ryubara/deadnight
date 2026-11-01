# The over-the-shoulder camera in the lot's narrow places (docs/design/map.md "Widths and the
# camera"): sweeps the player's spring arm and shoulder offset through every marker of
# `CameraProbes`.
extends GdUnitTestSuite

const SCENE := "res://world/drive_in_greybox.tscn"
## The player's positions along a passage, in metres from the marker, each way round.
const OFFSETS := [-2.5, -2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5]
## Where the arm must stay at full length: corridors with open air behind. Next to a generator or a
## ramp the arm is allowed to shorten (that is the spring arm doing its job); the camera must still
## never end up in a wall.
const FULL_ARM_PROBES := ["CarGap_", "Concession", "Link", "Gate", "BoothDoor", "RoadGate"]

var _lot: Node3D


func before_test() -> void:
	_lot = auto_free(load(SCENE).instantiate()) as Node3D
	# Doors off: the camera is judged on the passages, and a bought door is a doorway.
	_lot.get_node("Doors").free()
	add_child(_lot)
	await get_tree().process_frame
	for i in 3:
		await get_tree().physics_frame


func test_the_shoulder_camera_is_never_inside_a_wall_in_a_passage() -> void:
	var space := _lot.get_world_3d().direct_space_state
	for probe: Marker3D in _lot.get_node("CameraProbes").get_children():
		var failures := _sweep(space, probe, false)
		(
			assert_array(failures)
			. override_failure_message("%s: %s" % [probe.name, failures])
			. is_empty()
		)


func test_the_arm_keeps_its_full_length_in_corridors() -> void:
	var space := _lot.get_world_3d().direct_space_state
	for probe: Marker3D in _lot.get_node("CameraProbes").get_children():
		if not FULL_ARM_PROBES.any(
			func(prefix: String) -> bool: return String(probe.name).begins_with(prefix)
		):
			continue
		var failures := _sweep(space, probe, true)
		(
			assert_array(failures)
			. override_failure_message("%s: %s" % [probe.name, failures])
			. is_empty()
		)


func test_a_zombie_pair_fits_every_passage() -> void:
	# Two zombies abreast are two bodies of radius 0.35, 1.4 m across; every passage the camera
	# needs is wider.
	var space := _lot.get_world_3d().direct_space_state
	for probe: Marker3D in _lot.get_node("CameraProbes").get_children():
		var side := probe.global_transform.basis.x
		for offset: float in [-0.35, 0.35]:
			var feet := probe.global_position + side * offset
			var ground := space.intersect_ray(
				PhysicsRayQueryParameters3D.create(
					feet + Vector3.UP * 2.0, feet + Vector3.DOWN * 4.0
				)
			)
			if ground.is_empty():
				continue
			(
				assert_bool(CameraProbe.body_fits(space, ground["position"]))
				. override_failure_message("%s, body at %+.2f" % [probe.name, offset])
				. is_true()
			)


func test_a_gap_narrower_than_the_camera_is_caught() -> void:
	# Negative control: the first draft's 1.4 m between cars lets the arm through and puts the
	# shoulder camera in the car, so the sweep has to report it; 1.8 m is clean.
	for gap in [1.4, 1.8]:
		var world := auto_free(Node3D.new()) as Node3D
		for sign in [-1.0, 1.0]:
			var car := CSGBox3D.new()
			car.use_collision = true
			car.size = Vector3(1.7, 0.7, 2.3)
			car.position = Vector3(sign * (gap / 2.0 + 0.85), 1.3, 0)
			world.add_child(car)
		add_child(world)
		await get_tree().process_frame
		for i in 3:
			await get_tree().physics_frame
		var marker := Marker3D.new()
		world.add_child(marker)
		marker.position = Vector3(0, 0, 0)  # facing -Z, the gap runs along Z
		var space := world.get_world_3d().direct_space_state
		var clipped := 0
		for z in [-3.5, -3.0, -2.5]:  # facing -Z, the camera is 2.8 m behind: level with the cars
			if not CameraProbe.rig(space, Vector3(0, 0, z), 0.0, 1.0)["free"]:
				clipped += 1
		if gap < 1.7:
			assert_int(clipped).is_greater(0)
		else:
			assert_int(clipped).is_equal(0)
		world.queue_free()
		await get_tree().process_frame


## Failing samples ("name offset side"): the camera inside a wall or not seeing the player, and with
## `full_arm` also the arm shorter than its full length. Samples where the player's body itself
## would not fit are skipped.
func _sweep(space: PhysicsDirectSpaceState3D, probe: Marker3D, full_arm: bool) -> Array:
	var failures := []
	var forward := -probe.global_transform.basis.z
	var yaw := probe.global_transform.basis.get_euler().y
	for turn in [0.0, PI]:
		for offset: float in OFFSETS:
			var along := forward * offset * (1.0 if turn == 0.0 else -1.0)
			var top := probe.global_position + along + Vector3.UP * 2.0
			var ground := space.intersect_ray(
				PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 6.0)
			)
			if ground.is_empty() or not CameraProbe.body_fits(space, ground["position"]):
				continue
			for side in [1.0, -1.0]:
				var rig := CameraProbe.rig(space, ground["position"], yaw + turn, side)
				var short: bool = full_arm and rig["arm"] < CameraProbe.arm_length() - 0.05
				if not rig["free"] or short:
					failures.append(
						(
							"%s%+.1f %s"
							% ["fwd" if turn == 0.0 else "rev", offset, "R" if side > 0 else "L"]
						)
					)
	return failures
