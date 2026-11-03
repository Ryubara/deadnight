extends Node3D
## The second map's move soak (#631): player bodies walk the greybox from goal to goal for a while
## along the zombies' mesh, every link open (`SmallMapWalkers`), and the numbers are printed: legs
## walked, reached, given up, stuck episodes and the longest, ticks spent outside the building,
## metres walked. Not part of the game.
##
##   godot --headless --path game res://tests/captures/smallmap_move_soak.tscn -- \
##     --minutes=10 --bodies=4 --seed=1
## Prints `SOAK {json}` at the end and exits 1 when a leg was given up or a body got outside.

const TICKS_PER_FRAME := 30


func _ready() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var parts := argument.substr(2).split("=", true, 1)
			args[parts[0]] = parts[1]
	var walkers := SmallMapWalkers.new()
	add_child(walkers)
	await walkers.setup(int(args.get("bodies", 4)), int(args.get("seed", 1)))
	var limit := int(float(args.get("minutes", 10)) * 60.0 * 60.0)
	var started := Time.get_ticks_msec()
	while walkers.ticks < limit:
		for _i in TICKS_PER_FRAME:
			walkers.step()
		await get_tree().physics_frame
	var report := walkers.report()
	report["all"]["wall_ms"] = Time.get_ticks_msec() - started
	print("SOAK %s" % JSON.stringify(report))
	var all: Dictionary = report["all"]
	walkers.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if all["failed"] > 0 or all["outside"] > 0 else 0)
