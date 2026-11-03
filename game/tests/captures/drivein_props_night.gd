extends Node
## The drive-in's own props (`tools/blender/build_drivein_props.py`, issue #651) close up, from the
## player's shoulder camera, in the real night: the picnic tables, the concession counter with its
## popcorn machine and menu board, the midway, the ticket booths and the marquee. Not part of the
## game. Each spot holds for `HOLD_FRAMES` frames, as `night_look_tour.gd` does, so with Movie Maker
## at 10 fps the frame numbered `spot * HOLD_FRAMES + 12` (from 0) is the settled shot of that spot:
##
##     godot --path game res://tests/captures/drivein_props_night.tscn \
##         --write-movie <abs>/props.png --fixed-fps 10 --quit-after 60
## Prints SPOT <name> <frame> as each spot starts.

const HOLD_FRAMES := 10
const SEED := 5
## Where the player stands (lot metres), the camera's yaw and pitch (degrees; yaw 0 looks at the
## screen, 180 at the road) and the circuits a spot switches on as it starts (they stay on).
const SPOTS := [
	{"name": "picnic_tables_east", "at": Vector3(48, 0, -34.5), "yaw": 180.0, "pitch": 10.0},
	{
		"name": "concession_counter",
		"at": Vector3(0, 0, -0.6),
		"yaw": 180.0,
		"pitch": 10.0,
		"circuits": {&"concession": true},
	},
	{"name": "midway", "at": Vector3(-8.4, 0, 14.0), "yaw": 15.0, "pitch": 16.0},
	{
		"name": "ticket_booths",
		"at": Vector3(0, 0, 55),
		"yaw": 0.0,
		"pitch": 8.0,
		"circuits": {&"screen_lot": true, &"back_lot": true},
	},
	{"name": "marquee", "at": Vector3(12.4, 0, 57), "yaw": 0.0, "pitch": 22.0},
]

var _night: Night
var _frame := 0
var _spot := -1


func _ready() -> void:
	_night = Night.new()
	add_child(_night)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	# No dead on the props: the first wave waits past the end of the tour.
	tuning.rounds.first_spawn_delay = 600.0
	await _night.start(Night.Mode.MANUAL, SEED, tuning)
	_night.ticked.connect(_pose)


func _process(_delta: float) -> void:
	if _night == null or not _night.running:
		return
	_frame += 1
	var spot := (_frame - 1) / HOLD_FRAMES
	if spot >= SPOTS.size():
		get_tree().quit()
		return
	if spot != _spot:
		_spot = spot
		print("SPOT ", SPOTS[spot]["name"], " ", _frame - 1)
		var circuits: Dictionary = SPOTS[spot].get("circuits", {})
		for circuit_id: StringName in circuits:
			var action := RulesAction.set_circuit(circuit_id, circuits[circuit_id])
			_night.state.apply_events(_night.server.rules.apply(action))


func _pose() -> void:
	if _spot < 0:
		return
	var spot: Dictionary = SPOTS[_spot]
	var player := _night.player()
	player.teleport(spot["at"])
	player.camera_rig.yaw = deg_to_rad(spot["yaw"])
	player.camera_rig.pitch = deg_to_rad(spot["pitch"])
