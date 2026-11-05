extends "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"
## The way CI runs GdUnit4: its command line tool after every game script has been loaded as
## itself (`ScriptWarmup`), so no shard leaves scripts in use at exit whatever suites it holds
## (#1231).
##
##   godot --headless --path game -s res://tools/ci/warm_GdUnitCmdTool.gd -a <suite> -c
##
## Takes the arguments of `res://addons/gdUnit4/bin/GdUnitCmdTool.gd`. The file's name ends in
## `GdUnitCmdTool.gd` because GdUnit4 finds its own arguments after the argument that names it.


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var count := ScriptWarmup.load_all()
	print("ScriptWarmup: %d scripts in %d ms" % [count, Time.get_ticks_msec() - started])
	super()
