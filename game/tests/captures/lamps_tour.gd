extends Node
## The lot's lamps through a night's generator, for captures: the screen lot alone (the start),
## every circuit on, the tank nearly dry (the lights fail), and dry. Each stage is shot from four
## fixed cameras (the screen field, the midway, the whole lot from above, the generator yard) and
## saved as PNGs.
## Not part of the game. Run with a window (not headless):
## `godot --path game res://tests/captures/lamps_tour.tscn --resolution 1280x720
## -- --out=<folder>`.

## Camera position and where it looks, per shot.
const SHOTS := {
	"field": [Vector3(0.0, 15.0, -8.0), Vector3(0.0, 1.0, -34.0)],
	"midway": [Vector3(-12.0, 10.0, 34.0), Vector3(-8.0, 0.0, 12.0)],
	"lot": [Vector3(0.0, 100.0, 48.0), Vector3(0.0, 0.0, 4.0)],
	"yard": [Vector3(26.0, 12.0, 34.0), Vector3(42.0, 0.0, 16.0)],
}
## Ticks after a change before the frame is shot, and the frames the renderer is given.
const SETTLE_TICKS := 4
const SETTLE_FRAMES := 3

var _night: Night
var _camera: Camera3D
var _out := "user://lamps"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.MANUAL)
	_camera = Camera3D.new()
	_camera.fov = 65.0
	add_child(_camera)
	_camera.make_current()
	var rules := _night.server.rules
	await _stage("1_start")
	for circuit_id: StringName in rules.tuning.fuel.circuit_drain:
		_act(RulesAction.set_circuit(circuit_id, true))
	await _stage("2_all_circuits")
	_act(RulesAction.set_circuit(&"concession", false))
	_act(RulesAction.set_circuit(&"booth", false))
	await _stage("3_concession_and_booth_off")
	for circuit_id: StringName in rules.tuning.fuel.circuit_drain:
		_act(RulesAction.set_circuit(circuit_id, true))
	var fuel: FuelTuning = rules.tuning.fuel
	rules.generator.fuel = fuel.capacity * fuel.brownout_fraction * 0.5
	await _stage("4_failing", 5)
	rules.generator.fuel = 0.001
	await _stage("5_dry", SETTLE_TICKS + 40)
	get_tree().quit()


## Lets `ticks` pass, then shoots each camera.
func _stage(stage: String, ticks: int = SETTLE_TICKS) -> void:
	for _i in ticks:
		_night.tick()
	for shot: String in SHOTS:
		_camera.look_at_from_position(SHOTS[shot][0], SHOTS[shot][1])
		for _i in SETTLE_FRAMES:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s/%s_%s.png" % [_out, stage, shot])
	print("shot ", stage)


## A rules action from outside the server's tick, its events delivered as the link would.
func _act(action: Dictionary) -> void:
	_night.state.apply_events(_night.server.rules.apply(action))
