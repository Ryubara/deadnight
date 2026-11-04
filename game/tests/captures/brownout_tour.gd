extends Node
## Captures the lot from the player's own camera while the generator's tank is low (issue #874):
## the real night, the shoulder camera, the tank held in its last tenth. Not part of the game.
##
##     gds godot -- --path game res://tests/captures/brownout_tour.tscn \
##         --write-movie <abs>/brownout.png --fixed-fps 30 --quit-after 330 -- --power=0.5
## Arguments after `--`:
##   --power=P  how far into the brownout the tank is held: 1 is its start (healthy), 0 dry
##              (default 0.5; `GeneratorState.power_level`).
##   --spot=N   the spot (0: down the avenue toward the road, 1: up at the screen).

const SEED := 5
const SPOTS: Array[Dictionary] = [
	{"at": Vector3(0, 0, -30), "yaw": 180.0, "pitch": 8.0},
	{"at": Vector3(0, 0, -20), "yaw": 0.0, "pitch": 20.0},
]

var _night: Night
var _power := 0.5
var _spot := 0
var _frames := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--power="):
			_power = float(arg.trim_prefix("--power="))
		elif arg.begins_with("--spot="):
			_spot = int(arg.trim_prefix("--spot="))
	_night = Night.new()
	add_child(_night)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.first_spawn_delay = 600.0
	tuning.rounds.spawn_interval_start = 600.0
	await _night.start(Night.Mode.MANUAL, SEED, tuning)
	_night.server.rules.apply(RulesAction.skip_break())
	_night.ticked.connect(_pose)


func _process(_delta: float) -> void:
	if _night != null and _night.running:
		_frames += 1


func _pose() -> void:
	var fuel_tuning: FuelTuning = _night.server.rules.tuning.fuel
	var generator := _night.server.rules.generator
	# Held there: the drain of a tick never moves it.
	generator.fuel = fuel_tuning.capacity * fuel_tuning.brownout_fraction * _power
	var spot: Dictionary = SPOTS[_spot]
	var player := _night.player()
	player.teleport(spot["at"])
	var rig := player.camera_rig
	rig.yaw = deg_to_rad(spot["yaw"])
	rig.pitch = deg_to_rad(spot["pitch"])
