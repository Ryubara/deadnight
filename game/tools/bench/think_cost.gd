extends SceneTree
## What the dead's thinking costs a 30 Hz step at the late rounds (#947): `sim.think` (which holds
## the repaths, `sim.path`) and the whole step, as the median of the steps, for `--dead=` (99)
## zombies spread over 45 m round four players who walk, on a bent path over a floor. Counts come
## first: the thinking (not dying, not held) and the swinging are printed with the times.
## `--steps=` (600) steps, `--repeat=` (5) times; prints a `RESULT` line per repeat and a `SUMMARY`
## of the medians. To compare two commits, copy this file to the other checkout and run both
## together: a loaded machine moves one process by more than the cost changed (the kit's
## `docs/godot/performance-budgets.md`).
##
##     gds godot -- --headless --path game -s res://tools/bench/think_cost.gd -- --dead=99

const SEED := 947
const SPREAD := 45.0
const SETTLE_STEPS := 90


## A path with a bend, over the floor by the baker's lift.
class BentPathing:
	extends ZombiePathing

	func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		var lift := Vector3(0.0, ZombieSim.NAV_LIFT, 0.0)
		var middle := from.lerp(to, 0.5)
		middle.x += 2.0
		return PackedVector3Array([from + lift, middle + lift, to + lift])

	func ground_offset() -> float:
		return ZombieSim.NAV_LIFT


func _initialize() -> void:
	var dead := _arg("dead", 99)
	var steps := _arg("steps", 600)
	var repeat := _arg("repeat", 5)
	PerfProbe.enabled = true
	var think: Array[float] = []
	var whole: Array[float] = []
	for r in repeat:
		var sim := _crowd(dead)
		var step_think: Array[float] = []
		var step_whole: Array[float] = []
		var thinking := 0
		var swinging := 0
		for step in SETTLE_STEPS + steps:
			var t := float(step) * ZombieSim.STEP
			var targets := {
				1: Vector3(cos(t * 0.3) * 12.0, 0.0, sin(t * 0.3) * 12.0),
				2: Vector3(-20.0 + t * 0.1, 0.0, 10.0),
				3: Vector3(25.0, 0.0, -15.0),
				4: Vector3.ZERO,
			}
			var began := Time.get_ticks_usec()
			sim.tick(ZombieSim.STEP, targets)
			var spent := Time.get_ticks_usec() - began
			var taken := PerfProbe.take()
			if step < SETTLE_STEPS:
				continue
			step_think.append(float(taken["usec"].get(&"sim.think", 0)))
			step_whole.append(float(spent))
			for zombie: ZombieBody in sim.zombies.values():
				if zombie.is_alive() and not zombie.halted:
					thinking += 1
				if zombie.mode == ZombieBody.Mode.ATTACK:
					swinging += 1
		step_think.sort()
		step_whole.sort()
		think.append(step_think[steps / 2])
		whole.append(step_whole[steps / 2])
		print(
			(
				"RESULT dead=%d repeat=%d think_us=%.0f step_us=%.0f thinking_a_step=%.1f swinging_a_step=%.1f"
				% [dead, r, think[-1], whole[-1], float(thinking) / steps, float(swinging) / steps]
			)
		)
	think.sort()
	whole.sort()
	print(
		"SUMMARY dead=%d think_us=%.0f step_us=%.0f" % [dead, think[repeat / 2], whole[repeat / 2]]
	)
	quit()


func _crowd(dead: int) -> ZombieSim:
	var sim := ZombieSim.new(ZombieTuning.shipped(), SEED)
	sim.pathing = BentPathing.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in dead:
		var at := Vector3(rng.randf_range(-SPREAD, SPREAD), 0.0, rng.randf_range(-SPREAD, SPREAD))
		sim.spawn(i + 1, 1.0 + rng.randf() * 1.5, at, rng.randf() * TAU).enter(
			ZombieBody.Mode.CHASE
		)
	return sim


func _arg(name: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return int(arg.trim_prefix("--%s=" % name))
	return fallback
