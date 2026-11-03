extends Node
## The concession's neon sign and glow panes from outside, along the wall, and from inside and
## behind it, with every circuit on, for captures of a halo bleeding through a wall.
## `--hide=Halo` or `--hide=Light` hides that child of the sign, to count what it alone changes.
## Not part of the game. Run with a window:
## `godot --path game res://tests/captures/neon_halo_tour.tscn --resolution 1280x720
## -- --out=<folder>`.

const SHOTS := {
	"1_front_of_sign": [Vector3(0.0, 2.6, -13.0), Vector3(0.0, 3.2, -4.3)],
	"2_along_the_wall": [Vector3(-17.0, 3.4, -4.7), Vector3(0.0, 3.3, -4.3)],
	"3_inside_behind_sign": [Vector3(0.0, 2.2, 2.0), Vector3(0.0, 3.3, -4.0)],
	"4_inside_beside_sign": [Vector3(-3.0, 2.0, 1.0), Vector3(-0.5, 3.0, -4.0)],
	"5_inside_at_pane": [Vector3(-6.0, 1.8, 1.0), Vector3(-6.0, 1.7, -4.05)],
	"6_outside_at_pane": [Vector3(-6.0, 1.8, -10.0), Vector3(-6.0, 1.7, -4.05)],
	"7_roof_behind": [Vector3(0.0, 7.5, 3.0), Vector3(0.0, 3.4, -4.3)],
	"9_inside_oblique_west": [Vector3(-8.0, 2.0, 0.5), Vector3(0.0, 3.3, -4.0)],
	"10_inside_oblique_east": [Vector3(8.0, 2.0, 0.5), Vector3(0.0, 3.3, -4.0)],
	"11_inside_doorway_up": [Vector3(0.0, 1.0, -1.5), Vector3(-2.0, 4.0, -4.0)],
	"8_wall_corner_outside": [Vector3(-12.0, 2.0, -8.0), Vector3(-6.0, 2.5, -4.1)],
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
