extends SceneTree
## Runs one cell of the balance simulator from the command line and writes it as JSON.
##
##   godot --headless --path game -s res://tools/balance/balance_cli.gd -- \
##     --skill=average --players=1 --nights=200 --seed=1 --out=cell.json [--step=0.25] [--rounds=30]
##     [--set=rounds.health_growth=1.05 ...] [--shopping=door_concession,weapon_rifle | none]
##     [--skill-set=head_rate=0.7 ...]  (a number of the skill level replaced, for a try)
##     [--assist=0.5]  (a touch player with the aim assist at that strength)
##     [--map=small_indoor]  (the second map's rules over the table, and its bots' shopping list)
##
## `tools/balance/run_report.py` runs all nine cells in parallel and draws the charts.

## The maps whose rules overlay `--map` lays over the shared table.
const MAP_TUNINGS := {"small_indoor": "res://world/smallmap/smallmap_tuning.tres"}


func _init() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var started := Time.get_ticks_msec()
	var tuning := (
		(load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).duplicate(true) as RulesTuning
	)
	var shopping_default := ""
	var map_path := String(MAP_TUNINGS.get(String(args.get("map", "")), ""))
	if not map_path.is_empty():
		var overlay := load(map_path) as MapTuning
		tuning = overlay.apply(tuning)
		shopping_default = ",".join(PackedStringArray(overlay.bot_shopping))
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
		int(args.get("rounds", str(BalanceBatch.DEFAULT_MAX_ROUNDS))),
		_shopping(args.get("shopping", shopping_default)),
		float(args.get("assist", "0")),
		_skill_numbers(OS.get_cmdline_user_args())
	)
	cell["seconds"] = float(Time.get_ticks_msec() - started) / 1000.0
	var out: String = args.get("out", "")
	if out.is_empty():
		print(JSON.stringify(cell))
	else:
		# A relative path is the caller's: `--path` moves the working directory into the project.
		var file := FileAccess.open(_absolute(out), FileAccess.WRITE)
		if file == null:
			push_error(
				"cannot write %s: %s" % [_absolute(out), error_string(FileAccess.get_open_error())]
			)
			quit(1)
			return
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


## `path` as an absolute path. Godot starts a `--path` run inside the project, so a relative path
## would land there; the shell's own directory (`PWD`, which POSIX shells and Git Bash export) is
## the one the caller meant. Without it the path is taken as given.
func _absolute(path: String) -> String:
	if path.is_absolute_path() or path.contains("://"):
		return path
	var base := OS.get_environment("PWD")
	return path if base.is_empty() else base.path_join(path)


## The items a run buys instead of the skill's list: names separated by commas, or `none`.
func _shopping(text: String) -> Array:
	var items: Array = []
	if text == "":
		return items
	for name in text.split(","):
		if name != "none":
			items.append(StringName(name))
	return items if not items.is_empty() else [&"none_at_all"]


## `--skill-set=head_rate=0.7` (repeatable): a number of the skill level replaced for this run.
func _skill_numbers(raw: PackedStringArray) -> Dictionary:
	var numbers := {}
	for arg in raw:
		if arg.begins_with("--skill-set=") and arg.length() > 12:
			var parts := arg.substr(12).split("=", true, 1)
			if parts.size() == 2:
				numbers[parts[0]] = float(parts[1])
	return numbers


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
