extends SceneTree
## Prints the second map's greybox against the small-map formula's targets, as a Markdown table
## (`SmallMapMeasure`): the table the pull request and `docs/design/smallmap.md` carry. Not a test;
## `test_smallmap_formula.gd` asserts the same rows. From the repository root:
##
##   godot --headless --path game -s res://tests/world/smallmap/smallmap_report.gd
##
## Exits 1 when a row is out of its tolerance.


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var host := Node.new()
	root.add_child(host)
	var started := Time.get_ticks_msec()
	var measure := SmallMapMeasure.new()
	await measure.run(host)
	print("| # | Target | Measured | Tolerance | Holds |")
	print("| ---: | --- | --- | --- | --- |")
	var failed := 0
	for entry: Dictionary in measure.rows:
		print(
			(
				"| %d | %s | %s | %s | %s |"
				% [
					entry["row"],
					entry["name"],
					_value(entry),
					_tolerance(entry),
					"yes" if entry["ok"] else "**no**",
				]
			)
		)
		if not entry["ok"]:
			failed += 1
	for entry: Dictionary in measure.rows:
		if entry["detail"] != "":
			print("row %d: %s" % [entry["row"], entry["detail"]])
	print("facts: %s" % [measure.facts])
	print(
		(
			"%d rows, %d out of tolerance, %d ms"
			% [measure.rows.size(), failed, Time.get_ticks_msec() - started]
		)
	)
	host.free()
	await process_frame
	quit(1 if failed > 0 or measure.rows.is_empty() else 0)


func _value(entry: Dictionary) -> String:
	var value: Variant = entry["value"]
	var text := "%.1f" % value if value is float else str(value)
	return ("%s %s" % [text, entry["unit"]]).strip_edges()


func _tolerance(entry: Dictionary) -> String:
	var lo: float = entry["lo"]
	var hi: float = entry["hi"]
	if lo == 0.0 and hi == 0.0:
		return "exact"
	if lo == hi:
		return "exactly %d" % int(lo)
	if is_inf(hi):
		return ("at least %s %s" % [_number(lo), entry["unit"]]).strip_edges()
	return ("%s to %s %s" % [_number(lo), _number(hi), entry["unit"]]).strip_edges()


func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
