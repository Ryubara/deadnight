extends Node
## How long a body takes to get through the dead, by the way a push moves them (#914): the lot's
## clear ground, one body that pushes straight on (it does not steer, the worst a person does), and
## one, two, a crowd or a ring of standing dead. Prints `DEADVARIANT {json}` per row, a row being a
## variant, a scenario, a pace and a sideways offset: the seconds to get through (-1 when it did not
## in `LIMIT`), the seconds to first move a zombie and the zombies moved by 0.3 m or more.
##
## `godot --headless --path game res://tests/captures/dead_variants.tscn --fixed-fps 60`

const LIMIT := 20.0
const VARIANTS: Array[String] = ["hard", "timed", "wade", "ramp"]

var _clear := Vector3.ZERO


func _ready() -> void:
	var lab := await DeadLab.start(self)
	_clear = _find_clear(lab)
	print("DEADVARIANT_AT ", _clear)
	var variants := VARIANTS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variants="):
			variants = []
			for name in arg.trim_prefix("--variants=").split(","):
				variants.append(name)
	for variant in variants:
		for pace in ["run", "sprint"]:
			for offset in [0.0, 0.25]:
				for scenario in ["one", "two", "crowd", "ring8", "ring10"]:
					await _row(variant, pace == "sprint", offset, scenario)
	lab.world.queue_free()
	get_tree().quit()


func _row(variant: String, sprint: bool, offset: float, scenario: String) -> void:
	var lab := await DeadLab.start(self, _tuning(variant))
	var start := _clear + Vector3(offset, 0.0, 5.0)
	if scenario.begins_with("ring"):
		start = _clear
	lab.body.teleport(start)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ids: Array[int] = []
	var goal := 3.0
	match scenario:
		"one":
			ids.append(lab.place(start + Vector3(-offset, 0.0, -2.0)))
		"two":
			ids.append(lab.place(start + Vector3(-offset - 0.4, 0.0, -2.0)))
			ids.append(lab.place(start + Vector3(-offset + 0.4, 0.0, -2.0)))
		"crowd":
			for row in 4:
				for col in 3:
					ids.append(
						lab.place(
							start + Vector3(-offset + (col - 1) * 0.85, 0.0, -2.0 - row * 0.85)
						)
					)
			goal = 6.5
		"ring8":
			ids = lab.ring(8, 1.1, start)
		"ring10":
			ids = lab.ring(10, 0.95, start)
	var first := -1.0
	# Time to the first zombie that has moved 0.3 m from where it was put.
	var placed := {}
	for id in ids:
		placed[id] = lab.zombie_at(id)
	var through := -1.0
	var left := int(LIMIT / DeadLab.STEP)
	for i in left:
		lab.step(Vector2(0.0, -1.0), sprint)
		if first < 0.0:
			for id in ids:
				if lab.zombie_at(id).distance_to(placed[id]) >= 0.3:
					first = float(i + 1) * DeadLab.STEP
					break
		if Vector2(lab.at().x - start.x, lab.at().z - start.z).length() >= goal:
			through = float(i + 1) * DeadLab.STEP
			break
	var moved := 0
	for id in ids:
		if lab.zombie_at(id).distance_to(placed[id]) >= 0.3:
			moved += 1
	print(
		"DEADVARIANT ",
		(
			JSON
			. stringify(
				{
					"variant": variant,
					"pace": "sprint" if sprint else "run",
					"offset": offset,
					"scenario": scenario,
					"through": snappedf(through, 0.01),
					"first_moved": snappedf(first, 0.01),
					"moved": moved,
					"dead": ids.size(),
				}
			)
		)
	)
	lab.world.queue_free()
	await get_tree().process_frame


func _tuning(variant: String) -> DeadContactTuning:
	var tuning := DeadContactTuning.shipped()
	match variant:
		"straight":
			tuning.lateral = 0.0
		"hard":
			tuning.policy = DeadContactTuning.Policy.TIMED
			tuning.hold_seconds = 1.0e6
		"wade":
			tuning.policy = DeadContactTuning.Policy.WADE
		"ramp":
			tuning.policy = DeadContactTuning.Policy.RAMP
			tuning.hold_seconds = 0.3
		"ramp0":
			tuning.policy = DeadContactTuning.Policy.RAMP
			tuning.hold_seconds = 0.3
			tuning.crowd_drag = 0.0
		"ramp1":
			# Held a moment longer, then faster sooner.
			tuning.policy = DeadContactTuning.Policy.RAMP
			tuning.hold_seconds = 0.5
			tuning.ramp_from = 0.6
			tuning.ramp_to = 2.4
			tuning.ramp_seconds = 1.0
			tuning.crowd_drag = 0.1
		"timed15":
			tuning.shove_speed = 1.5
		"side":
			tuning.lateral = 0.8
		"ramp_side":
			tuning.policy = DeadContactTuning.Policy.RAMP
			tuning.hold_seconds = 0.3
			tuning.lateral = 0.8
		"wade_side":
			tuning.policy = DeadContactTuning.Policy.WADE
			tuning.lateral = 0.8
	return tuning


## A spot with 14 m of clear ground each way: a box query on the walls and props.
func _find_clear(lab: DeadLab) -> Vector3:
	var shape := BoxShape3D.new()
	shape.size = Vector3(14.0, 2.0, 14.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
	var space := lab.world.get_world_3d().direct_space_state
	for z in range(-40, 40, 2):
		for x in range(-40, 40, 2):
			query.transform = Transform3D(Basis.IDENTITY, Vector3(x, 1.5, z))
			if space.intersect_shape(query, 1).is_empty():
				return Vector3(x, 0.0, z)
	return Vector3.INF
