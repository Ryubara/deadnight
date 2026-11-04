extends SceneTree
## What the zombies' separation pass costs a 30 Hz step (#933): the time (`PerfProbe`'s
## `sim.separate`, and the whole step), and the most memory the pass holds at once while it runs
## (an allocation count in bytes: the pass should make nothing once its scratch has grown).
## Two crowds of `--dead=` (120) zombies, one spread over 30 m and one piled into a 3 m square,
## run for `--steps=` (100) steps, `--repeat=` (5) times each; prints a `RESULT` line per crowd and
## repeat and a `SUMMARY` line per crowd (the median of the repeats). It uses only the sim's public
## surface and `_separate`, so the same file runs on another commit to compare (copy it there).
##
##     gds godot -- --headless --path game -s res://tools/bench/separation_cost.gd -- --dead=120
##
## The memory figure needs a build with memory tracking (the editor and debug templates).

const SPREADS: Array[float] = [30.0, 3.0]
const SETTLE_STEPS := 60
const SEED := 933
## Slack on the ballast that lifts the live memory to the old peak, so a step that holds nothing
## shows 0 and not the ballast's own rounding.
const BALLAST_SLACK := 4096


func _initialize() -> void:
	var dead := _arg("dead", 120)
	var steps := _arg("steps", 100)
	var repeat := _arg("repeat", 5)
	PerfProbe.enabled = true
	for spread in SPREADS:
		var separate_us: Array[float] = []
		var step_us: Array[float] = []
		var held: Array[int] = []
		var held_step: Array[int] = []
		for r in repeat:
			var sim := _crowd(dead, spread)
			var targets := {1: Vector3.ZERO}
			for _i in SETTLE_STEPS:
				sim.tick(ZombieSim.STEP, targets)
			PerfProbe.take()
			for _i in steps:
				sim.tick(ZombieSim.STEP, targets)
			var taken := PerfProbe.take()
			var usec: Dictionary = taken["usec"]
			var sep := float(usec.get(&"sim.separate", 0)) / steps
			var whole := 0.0
			for label: StringName in usec:
				whole += float(usec[label])
			whole /= steps
			var pass_bytes := _peak_over(sim, targets, true)
			var step_bytes := _peak_over(sim, targets, false)
			separate_us.append(sep)
			step_us.append(whole)
			held.append(pass_bytes)
			held_step.append(step_bytes)
			print(
				(
					(
						"RESULT dead=%d spread=%.0f repeat=%d separate_us=%.1f step_us=%.1f"
						+ " pass_peak_bytes=%d step_peak_bytes=%d"
					)
					% [dead, spread, r, sep, whole, pass_bytes, step_bytes]
				)
			)
		print(
			(
				(
					"SUMMARY dead=%d spread=%.0f separate_us_median=%.1f step_us_median=%.1f"
					+ " pass_peak_bytes_max=%d step_peak_bytes_max=%d"
				)
				% [
					dead,
					spread,
					_median(separate_us),
					_median(step_us),
					held.max(),
					held_step.max()
				]
			)
		)
	quit()


## A crowd of `dead` standing zombies at seeded places in a square `spread` metres wide.
func _crowd(dead: int, spread: float) -> ZombieSim:
	var sim := ZombieSim.new(null, SEED)
	sim.tuning.hard_cap = maxi(sim.tuning.hard_cap, dead + 10)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in dead:
		var at := Vector3(
			rng.randf_range(-spread, spread) / 2.0, 0.0, rng.randf_range(-spread, spread) / 2.0
		)
		sim.spawn(i + 1, 1.5, at).enter(ZombieBody.Mode.CHASE)
	return sim


## The most the allocator holds above where it stood, while the pass (or the whole step) runs: a
## ballast lifts the live memory to the old peak, so the peak only moves for what the call holds.
func _peak_over(sim: ZombieSim, targets: Dictionary, pass_only: bool) -> int:
	var ballast := PackedByteArray()
	ballast.resize(
		maxi(
			OS.get_static_memory_peak_usage() - OS.get_static_memory_usage() + BALLAST_SLACK,
			BALLAST_SLACK
		)
	)
	var before := OS.get_static_memory_peak_usage()
	if pass_only:
		sim._separate(ZombieSim.STEP)
	else:
		sim.tick(ZombieSim.STEP, targets)
	var after := OS.get_static_memory_peak_usage()
	ballast.clear()
	return maxi(after - before, 0)


func _median(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _arg(name: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return int(arg.get_slice("=", 1))
	return fallback
