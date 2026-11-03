extends Node
## The concession's neon sign and glow panes from outside, along the wall, and from inside and
## behind it, with every circuit on, for captures of a halo bleeding through a wall.
## `--hide=Halo` or `--hide=Light` hides that child of the sign, to count what it alone changes.
## Not part of the game. Run with a window:
## `godot --path game res://tests/captures/neon_halo_tour.tscn --resolution 1280x720
## -- --out=<folder>`.

const SHOTS := {
	"a_lot_above": [Vector3(0.0, 100.0, 48.0), Vector3(0.0, 0.0, 4.0)],
	"b_midway": [Vector3(-12.0, 10.0, 34.0), Vector3(-8.0, 0.0, 12.0)],
	"c_midway_low": [Vector3(8.0, 1.8, 36.0), Vector3(-4.0, 0.5, 18.0)],
	"d_back_lot": [Vector3(-20.0, 12.0, 36.0), Vector3(-44.0, 0.0, 12.0)],
	"e_back_lot_low": [Vector3(-18.0, 1.8, 30.0), Vector3(-40.0, 1.0, 14.0)],
	"f_yard": [Vector3(26.0, 12.0, 34.0), Vector3(42.0, 0.0, 16.0)],
	"g_yard_low": [Vector3(20.0, 1.8, 30.0), Vector3(40.0, 1.0, 10.0)],
	"h_stand_inside_west": [Vector3(6.0, 2.0, 6.0), Vector3(-8.0, 3.5, 2.0)],
	"i_stand_roof_over": [Vector3(0.0, 14.0, 12.0), Vector3(0.0, 4.0, 2.0)],
	"j_concession_papers": [Vector3(2.5, 1.2, 8.0), Vector3(0.0, 0.0, 6.0)],
}

var _night: Night
var _camera: Camera3D
var _out := "user://neon_halo"
var _hide := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		if arg.begins_with("--hide="):
			_hide = arg.trim_prefix("--hide=")
	DirAccess.make_dir_recursive_absolute(_out)
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.MANUAL)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	add_child(_camera)
	_camera.make_current()
	var rules := _night.server.rules
	for circuit_id: StringName in rules.tuning.fuel.circuit_drain:
		_night.state.apply_events(rules.apply(RulesAction.set_circuit(circuit_id, true)))
	for _i in 6:
		_night.tick()
	if _hide != "":
		(_night.find_child("NeonSnacks", true, false).get_node(_hide) as Node3D).visible = false
	for shot: String in SHOTS:
		_camera.look_at_from_position(SHOTS[shot][0], SHOTS[shot][1])
		for _i in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot])
		print("shot ", shot)
	get_tree().quit()
