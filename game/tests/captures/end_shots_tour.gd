extends Node
## Looks at a map from the angles of its end-of-night camera (`MapInfo.end_shots`), for writing
## them and for a capture of them. Not part of the game. Arguments after `--`:
## `--map=ID` (default `drive_in`), `--out=FOLDER` (where the PNGs go),
## `--cam=name:x,y,z,tx,ty,tz[,fov[,near]];name2:...`: a frame from a lens at x,y,z looking at
## tx,ty,tz, named `name.png` (a near plane far out cuts away what is close, as a plan does),
## otherwise every authored shot at its start, middle and end (`shot<N>_<0|1|2>.png`).

const SETTLE_FRAMES := 6

var _args := {}
var _night: Night


func _ready() -> void:
	_args = _parse_args()
	var settings := MatchSettings.new()
	settings.map = str(_args.get("map", "drive_in"))
	_night = Night.new()
	_night.match_settings = settings
	add_child(_night)
	await _night.start(Night.Mode.AUTOPILOT, 3)
	_night.running = false
	var out := str(_args.get("out", "user://end_shots"))
	DirAccess.make_dir_recursive_absolute(out)
	var camera := Camera3D.new()
	add_child(camera)
	if _args.has("cam"):
		for one: String in str(_args["cam"]).split(";"):
			var named := one.split(":")
			var n := _numbers(named[1])
			camera.fov = n[6] if n.size() > 6 else 62.0
			camera.near = n[7] if n.size() > 7 else 0.05
			camera.global_transform = Transform3D(
				EndShot.facing(Vector3(n[3], n[4], n[5]) - Vector3(n[0], n[1], n[2])),
				Vector3(n[0], n[1], n[2])
			)
			camera.make_current()
			await _save("%s/%s.png" % [out, named[0]])
	else:
		var shots := _night.world.map_info.end_shots
		for i in shots.size():
			camera.fov = shots[i].fov
			camera.make_current()
			for k in 3:
				camera.global_transform = shots[i].pose(float(k) / 2.0)
				await _save("%s/shot%d_%d.png" % [out, i, k])
	get_tree().quit()


func _save(path: String) -> void:
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _numbers(text: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for part in text.split(","):
		out.append(part.to_float())
	return out


func _parse_args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
