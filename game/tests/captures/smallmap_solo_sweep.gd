extends Node
## The solo bot night of the second map (`SoloBotNight`) over a range of seeds, one line a seed and
## the rate at the end: the measurement behind the limit in `test_smallmap_bot_night.gd`. A night
## takes about 5 s, so run several processes over halves of the range (at most four at once).
##
## `godot --headless --path game res://tests/captures/smallmap_solo_sweep.tscn -- --from=1 --to=25`
## Prints `SOLO seed=... ok=...` for every seed and `SOLO_RATE failed=F of N`.


func _ready() -> void:
	var from := 1
	var to := 25
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=")
		if parts.size() == 2 and parts[0] == "from":
			from = int(parts[1])
		elif parts.size() == 2 and parts[0] == "to":
			to = int(parts[1])
	var failed := 0
	for seed_value in range(from, to + 1):
		var night := SoloBotNight.new(seed_value)
		await night.play(self)
		print("SOLO ", night.summary())
		if not night.failures().is_empty():
			failed += 1
			print("SOLO   ", night.failures())
		await get_tree().process_frame
	print("SOLO_RATE failed=%d of %d" % [failed, to - from + 1])
	get_tree().quit()
