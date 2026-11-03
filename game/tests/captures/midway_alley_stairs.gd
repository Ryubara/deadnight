extends Node
## The midway's west alley from the player's shoulder camera, in the real night (#846): the
## barrels, the dumpster and the fence between the midway and the back lot, at the places the old
## chain of hops stood on. Not part of the game. Each spot holds for `HOLD_FRAMES` frames, as
## `night_look_tour.gd` does, so with Movie Maker at 10 fps the frame numbered
## `spot * HOLD_FRAMES + 12` (from 0) is the settled shot of that spot (the last spot, the free
## camera from above, settles by `spot * HOLD_FRAMES + 10`):
##
##     godot --path game res://tests/captures/midway_alley_stairs.tscn \
##         --write-movie <abs>/alley.png --fixed-fps 10 --quit-after 60
## Prints SPOT <name> <frame> as each spot starts.

const HOLD_FRAMES := 10
const SEED := 5
## Where the player stands (lot metres), the camera's yaw and pitch (degrees; yaw 0 looks at the
## screen, 90 at the west, 180 at the road). The spots are the old chain of #846 from the floor of
## the midway's west alley to the back lot, and the alley seen from above (a free camera).
const SPOTS := [
	{
		"name": "alley_west",
		"at": Vector3(-12.0, 0, 5.5),
		"yaw": 75.0,
		"pitch": 12.0,
		"circuits": {&"concession": true},
	},
	{"name": "at_the_barrels", "at": Vector3(-14.76, 0.82, 0.24), "yaw": 20.0, "pitch": 10.0},
	{"name": "on_the_dumpster", "at": Vector3(-14.76, 1.62, -3.45), "yaw": 135.0, "pitch": 8.0},
	{"name": "past_the_fence", "at": Vector3(-19.2, 0, 1.0), "yaw": 135.0, "pitch": 8.0},
	{
		"name": "alley_from_above",
		"at": Vector3(-12.5, 0, 7.5),
		"yaw": 8.0,
		"pitch": 14.0,
		"cam": [Vector3(-11.0, 6.5, 13.5), Vector3(-13.6, 0.8, -1.0)],
	},
]

var _night: Night
var _frame := 0
var _spot := -1
var _free_camera: Camera3D


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
	if spot.has("cam"):
		if _free_camera == null:
			_free_camera = Camera3D.new()
			add_child(_free_camera)
		_free_camera.global_position = spot["cam"][0]
		_free_camera.look_at(spot["cam"][1])
		_free_camera.fov = 70.0
		_free_camera.make_current()
	elif _free_camera != null:
		_free_camera.queue_free()
		_free_camera = null
