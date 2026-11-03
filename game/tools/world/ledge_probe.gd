extends SceneTree
## How high a ledge the real player body gets onto from level ground, by sprinting and walking at a
## block of each height and jumping at several moments (#833). Prints the highest that was climbed.


func _initialize() -> void:
	var tuning := CameraProbe.tuning()
	var world := Node3D.new()
	root.add_child(world)
	var floor_box := CSGBox3D.new()
	floor_box.use_collision = true
	floor_box.size = Vector3(40, 1, 40)
	floor_box.position = Vector3(0, -0.5, 0)
	world.add_child(floor_box)
	var block := CSGBox3D.new()
	block.use_collision = true
	world.add_child(block)
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = tuning.radius
	capsule.height = tuning.height
	shape.shape = capsule
	shape.position.y = tuning.height * 0.5
	body.add_child(shape)
	body.collision_layer = PhysicsLayers.BODY
	body.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
	body.floor_snap_length = 0.3
	world.add_child(body)
	for _i in 4:
		await physics_frame
	var delta := 1.0 / Engine.physics_ticks_per_second
	var best := 0.0
	for hundredths in range(90, 190, 5):
		var height := hundredths / 100.0
		block.size = Vector3(6, height, 6)
		block.position = Vector3(0, height * 0.5, -3.0)
		for _i in 3:
			await physics_frame
		var climbed := false
		for sprint in [true, false]:
			for start in [1.0, 2.0, 3.0, 4.0]:
				for jump_tick in [0, 3, 6, 9, 12, 16, 20, 26, 32]:
					var state := PlayerMotionState.new()
					state.position = Vector3(0, 0.02, start)
					state.on_floor = true
					var command := PlayerCommand.new()
					command.move = Vector2(0, -1)
					command.sprint = sprint
					command.yaw = 0.0
					for tick in 90:
						command.jump = tick >= jump_tick and tick < jump_tick + 3
						PlayerSimulation.simulate(body, state, command, tuning, delta)
					if state.position.y > height - 0.1 and state.on_floor:
						climbed = true
		print("ledge ", height, " climbed ", climbed)
		if climbed:
			best = height
	print(
		"HIGHEST CLIMBED ", best, " jump_height ", tuning.jump_height, " step ", tuning.step_height
	)
	quit()
