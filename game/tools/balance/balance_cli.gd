extends SceneTree
## Runs one cell of the balance simulator from the command line and writes it as JSON.
##
##   godot --headless --path game -s res://tools/balance/balance_cli.gd -- \
##     --skill=average --players=1 --nights=200 --seed=1 --out=cell.json [--step=0.25] [--rounds=30]
##     [--set=rounds.health_growth=1.05 ...]
##
## `tools/balance/run_report.py` runs all nine cells in parallel and draws the charts.


func _init() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var started := Time.get_ticks_msec()
	var tuning := (
		(load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).duplicate(true) as RulesTuning
	)
	var failed := TuningOverrides.apply(tuning, _specs(OS.get_cmdline_user_args()))
	if not failed.is_empty():
		push_error("no such tuning: %s" % ", ".join(failed))
	var cell := BalanceBatch.run_cell(
		tuning,
		StringName(args.get("skill", "average")),
		int(args.get("players", "1")),
		int(args.get("nights", "100")),
		int(args.get("seed", "1")),
		float(args.get("step", str(BalanceBatch.DEFAULT_STEP))),
		int(args.get("rounds", str(BalanceBatch.DEFAULT_MAX_ROUNDS)))
	)
	cell["seconds"] = float(Time.get_ticks_msec() - started) / 1000.0
	var out: String = args.get("out", "")
	if out.is_empty():
		print(JSON.stringify(cell))
	else:
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(cell))
		file.close()
	print(
		(
			"%s x%d: %d nights, median round %d, %.1f s"
			% [
				cell["skill"],
				cell["players"],
				cell["nights"],
				BalanceBatch.median_round(cell),
				cell["seconds"],
			]
		)
	)
	quit()


func _specs(raw: PackedStringArray) -> PackedStringArray:
	var specs := PackedStringArray()
	for arg in raw:
		if arg.begins_with("--set="):
			specs.append(arg.substr(6))
	return specs


func _parse(raw: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw:
		if arg.begins_with("--") and arg.contains("="):
			var parts := arg.substr(2).split("=", true, 1)
			parsed[parts[0]] = parts[1]
	return parsed
