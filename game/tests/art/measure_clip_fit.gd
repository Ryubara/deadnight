extends Node
## Prints how limbs and garments sink into the body in every clip of the player's (#895), for one or
## more looks: one `FIT` line per clip and check with a fault, and a `FIT_SUMMARY`. Not a test: the
## table behind `test_soldier_clip_fit.gd` and docs/research/soldier-parts.md, "Fit".
##
##     godot --headless --path game res://tests/art/measure_clip_fit.tscn --
##         [--looks=10,0] [--clips=Idle,Run] [--menu] [--write=<file.json>]
##
## `--write` also writes the deepest sinking per look, clip and check as JSON: the recorded depths
## `test_soldier_clip_fit.gd` holds the clips to.
##
## `--menu` measures the menu's soldier instead: the idle with each weapon the menu shows in the
## hands (`MenuHero`, the night's hold), read when the skeleton has the hand pose on.

var _host: Node3D


func _ready() -> void:
	var looks := PackedStringArray(["10", "0"])
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--looks="):
			looks = arg.substr(8).split(",")
		elif arg.begins_with("--clips="):
			only = arg.substr(8).split(",")
	if "--menu" in OS.get_cmdline_user_args():
		await _menu(looks)
		get_tree().quit()
		return
	_host = Node3D.new()
	add_child(_host)
	var worst := {}
	var table := {}
	for spec in looks:
		var look := CharacterLook.from_preset(int(spec))
		var model := CharacterAssembler.assemble(look, 0)
		_host.add_child(model)
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		var fit := BodyFit.new(_host, skeleton)
		var sampler := ClipFit.new(fit, model)
		var report := await sampler.sample_clips(only)
		for clip: String in report:
			for check: String in report[clip]:
				var e: Dictionary = report[clip][check]
				print(
					(
						"FIT %s %s %s: %d vertices, deepest %.3f m at %.2f s (%s)"
						% [spec, clip, check, e.count, e.depth, e.at, e.mesh]
					)
				)
				table.get_or_add(spec, {}).get_or_add(clip, {})[check] = snappedf(e.depth, 0.001)
				var key := "%s %s" % [spec, check]
				worst[key] = maxf(worst.get(key, 0.0), e.depth)
		fit.free_bodies()
		_host.remove_child(model)
		model.free()
	print("FIT_SUMMARY ", worst)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--write="):
			var file := FileAccess.open(arg.substr(8), FileAccess.WRITE)
			file.store_string(JSON.stringify(table, " ", true) + "\n")
	get_tree().quit()


func _menu(looks: PackedStringArray) -> void:
	_host = Node3D.new()
	add_child(_host)
	for spec in looks:
		for id in MenuHero.available():
			var found := await ClipFit.menu_fit(_host, CharacterLook.from_preset(int(spec)), id)
			for check: String in found:
				var deepest: Dictionary = found[check][0]
				print(
					(
						"MENU %s %s %s: %d vertices, deepest %.3f m (%s %s)"
						% [
							spec,
							id,
							check,
							found[check].size(),
							deepest.depth,
							deepest.mesh,
							deepest.group
						]
					)
				)
