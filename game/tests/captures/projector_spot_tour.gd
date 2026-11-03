extends Node
## The first map seen from the field, the road and the booth, with every circuit on, for captures of
## the projector's spot (`ProjectionBooth/Lamps/ProjectorBeam`): where it lights and where it
## must not.
## `--hide-spot` removes that light, to count (with a second run) what it alone changes.
## Not part of the game. Run with a window:
## `godot --path game res://tests/captures/projector_spot_tour.tscn --resolution 1280x720
## -- --out=<folder>`.

const SHOTS := {
	"1_field_toward_booth": [Vector3(0.0, 9.0, -14.0), Vector3(0.0, 5.5, 22.0)],
	"2_field_side_of_beam": [Vector3(-30.0, 5.0, -6.0), Vector3(0.0, 7.0, -14.0)],
	"3_field_up_at_screen": [Vector3(10.0, 2.0, 12.0), Vector3(0.0, 8.0, -47.0)],
	"4_screen_face_near": [Vector3(0.0, 2.0, -34.0), Vector3(0.0, 8.0, -47.4)],
	"5_road_at_plaza": [Vector3(0.0, 2.2, 52.0), Vector3(0.0, 3.0, 36.0)],
	"5b_field_from_the_east": [Vector3(30.0, 3.0, 4.0), Vector3(0.0, 8.0, -40.0)],
	"6_road_at_door": [Vector3(-3.0, 2.0, 43.0), Vector3(0.0, 3.0, 35.5)],
	"7_road_from_above": [Vector3(0.0, 16.0, 56.0), Vector3(0.0, 0.0, 36.0)],
	"8_booth_south_wall_outside": [Vector3(14.0, 3.0, 40.0), Vector3(0.0, 3.5, 32.0)],
	"9_inside_booth": [Vector3(0.0, 2.0, 30.5), Vector3(0.0, 4.5, 23.0)],
	"10_inside_booth_south": [Vector3(0.0, 2.0, 24.0), Vector3(0.0, 3.0, 31.5)],
}

var _night: Night
var _camera: Camera3D
var _out := "user://projector_spot"
var _hide_spot := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		if arg == "--hide-spot":
			_hide_spot = true
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
	var spot := _night.find_child("ProjectorBeam", true, false) as SpotLight3D
	print(
		"spot visible ",
		spot.is_visible_in_tree(),
		" energy ",
		spot.light_energy,
		" forward ",
		-spot.global_basis.z
	)
	if _hide_spot:
		# Freed, not hidden: hiding a light after the circuits are on changed the whole plaza's
		# brightness in Compatibility (the lens halo's wash), which has nothing to do with the cone.
		spot.free()
	for shot: String in SHOTS:
		_camera.look_at_from_position(SHOTS[shot][0], SHOTS[shot][1])
		for _i in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot])
		print("shot ", shot)
	get_tree().quit()
