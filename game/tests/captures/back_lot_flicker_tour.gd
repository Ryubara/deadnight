extends Node
## Captures the back lot from the player's own camera with its circuit on (issue #851): a few
## spots of the real night (the rules, the shoulder camera), the back lot's breaker thrown at the
## start. Not part of the game.
##
##     gds godot -- --path game res://tests/captures/back_lot_flicker_tour.tscn \
##         --write-movie <abs>/back.png --fixed-fps 10 --quit-after 60
## Arguments after `--`:
##   --hold=N     frames each spot holds (default 10);
##   --only=NAME  stay at one spot for the whole run (a clip: `--fixed-fps 30 --quit-after 300`);
##   --off        leave the back lot's circuit off (the dark lot);
##   --hide=NAME  hide every node of this name under the back lot's lamps (`Pool`, `Halo`,
##                `Light`) to measure what it draws.
## Prints SPOT <name> <frame> as each spot starts.

const SEED := 5
## Where the player stands (lot metres), the camera's yaw and pitch (degrees; yaw 0 looks at the
## screen, 90 west, 180 at the road).
const SPOTS: Array[Dictionary] = [
	{"name": "gate_west", "at": Vector3(-22, 0, 20), "yaw": 90.0, "pitch": 8.0},
	{"name": "rows_south", "at": Vector3(-32, 0, 2), "yaw": 180.0, "pitch": 10.0},
	{"name": "toward_sign", "at": Vector3(-26, 0, 31), "yaw": 90.0, "pitch": 8.0},
	{"name": "from_field_gate", "at": Vector3(-40, 0, -1), "yaw": 180.0, "pitch": 12.0},
	{"name": "far_corner", "at": Vector3(-56, 0, 28), "yaw": 270.0, "pitch": 8.0},
	# Behind the back lot's walls (#832's method: the room behind, with a part hidden and shown).
	{"name": "midway_behind_wall", "at": Vector3(-11, 0, 25), "yaw": 90.0, "pitch": 4.0},
	{"name": "midway_behind_wall_2", "at": Vector3(-11, 0, 15), "yaw": 90.0, "pitch": 4.0},
	{"name": "field_behind_fence", "at": Vector3(-20, 0, -9), "yaw": 180.0, "pitch": 4.0},
	{"name": "field_behind_fence_2", "at": Vector3(-44, 0, -9), "yaw": 180.0, "pitch": 4.0},
]

var _night: Night
var _frame := 0
var _spot := -1
var _hold := 10
var _only := ""
var _off := false
var _hide := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hold="):
			_hold = int(arg.trim_prefix("--hold="))
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
		elif arg.begins_with("--hide="):
			_hide = arg.trim_prefix("--hide=")
		elif arg == "--off":
			_off = true
	_night = Night.new()
	add_child(_night)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.first_spawn_delay = 600.0
	tuning.rounds.spawn_interval_start = 600.0
	await _night.start(Night.Mode.MANUAL, SEED, tuning)
	_night.server.rules.apply(RulesAction.skip_break())
	if not _off:
		var action := RulesAction.set_circuit(&"back_lot", true)
		_night.state.apply_events(_night.server.rules.apply(action))
	_night.ticked.connect(_pose)
	if _hide != "":
		for node in _night.find_children(_hide, "", true, false):
			if not str(node.get_path()).contains("/BackLot/Lamps/"):
				continue
			# Not `visible`: the lamps set it every tick.
			if node is Light3D:
				(node as Light3D).light_cull_mask = 0
			elif node is VisualInstance3D:
				(node as VisualInstance3D).layers = 0


func _process(_delta: float) -> void:
	if _night == null or not _night.running:
		return
	_frame += 1
	var spot := (_frame - 1) / _hold
	if _only != "":
		spot = _index_of(_only)
	if spot >= SPOTS.size():
		get_tree().quit()
		return
	if spot != _spot:
		_spot = spot
		print("SPOT ", SPOTS[spot]["name"], " ", _frame - 1)


func _index_of(spot_name: String) -> int:
	for i in SPOTS.size():
		if SPOTS[i]["name"] == spot_name:
			return i
	return SPOTS.size()


func _pose() -> void:
	if _spot < 0:
		return
	var spot: Dictionary = SPOTS[_spot]
	var player := _night.player()
	player.teleport(spot["at"])
	var rig := player.camera_rig
	rig.yaw = deg_to_rad(spot["yaw"])
	rig.pitch = deg_to_rad(spot["pitch"])
