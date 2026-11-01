extends Node
## Captures the look of the night from the player's own camera at a few spots of the lot, the real
## night (the rules, the zombies, the player's shoulder camera). Not part of the game. Each spot
## holds for `HOLD_FRAMES` frames, so with Movie Maker at 10 fps the frame numbered
## `spot * HOLD_FRAMES + HOLD_FRAMES - 1` (from 0) is the settled shot of that spot:
##
##     godot --path game res://tests/captures/night_look_tour.tscn --write-movie <abs>/look.png \
##         --fixed-fps 10 --quit-after 100
## Arguments after `--`: `--hud` (draw the real HUD over the night).
## Prints SPOT <name> <frame> as each spot starts.

const HOLD_FRAMES := 10
const SEED := 5
## Where the player stands (lot metres), the camera's yaw and pitch (degrees; yaw 0 looks at the
## screen, 180 at the road; positive pitch looks up) and, when above 0, the distance at which the
## live dead are lined up in front of the camera. A spot may also switch circuits (`circuits`: id to
## on or off) as it starts; they stay as set for the spots after it.
const SPOTS := [
	{"name": "up_at_screen", "at": Vector3(0, 0, -30), "yaw": 0.0, "pitch": 32.0, "dead": 0.0},
	{"name": "across_the_lot", "at": Vector3(0, 0, -40), "yaw": 180.0, "pitch": 4.0, "dead": 0.0},
	{"name": "dead_at_25m", "at": Vector3(0, 0, -30), "yaw": 180.0, "pitch": 3.0, "dead": 25.0},
	{"name": "up_the_avenue", "at": Vector3(0, 0, -16), "yaw": 180.0, "pitch": 24.0, "dead": 0.0},
	{"name": "flank", "at": Vector3(36, 0, -20), "yaw": 300.0, "pitch": 8.0, "dead": 0.0},
	{"name": "yard", "at": Vector3(22, 0, 13), "yaw": 270.0, "pitch": 20.0, "dead": 0.0},
	{"name": "back_lot", "at": Vector3(-20, 0, 34), "yaw": 170.0, "pitch": 18.0, "dead": 0.0},
	{
		"name": "concession_powered",
		"at": Vector3(0, 0, -14),
		"yaw": 180.0,
		"pitch": 8.0,
		"dead": 0.0,
		"circuits": {&"concession": true},
	},
	{
		"name": "screen_circuit_off",
		"at": Vector3(0, 0, -30),
		"yaw": 0.0,
		"pitch": 32.0,
		"dead": 0.0,
		"circuits": {&"screen_lot": false},
	},
]
const DEAD_SPACING := 2.2

var _night: Night
var _frame := 0
var _spot := -1


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_night = Night.new()
	if OS.get_cmdline_user_args().has("--hud"):
		var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
		layer.add_child(hud)
		_night.hud = hud
	add_child(_night)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.first_spawn_delay = 0.2
	tuning.rounds.spawn_interval_start = 0.2
	await _night.start(Night.Mode.MANUAL, SEED, tuning)
	_night.server.rules.apply(RulesAction.skip_break())
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
	var rig := player.camera_rig
	rig.yaw = deg_to_rad(spot["yaw"])
	rig.pitch = deg_to_rad(spot["pitch"])
	var distance: float = spot["dead"]
	if distance > 0.0:
		_line_up(distance, rig.yaw)


## Holds the live dead in a row across the view at `distance` metres.
func _line_up(distance: float, yaw: float) -> void:
	var dead: Array[ZombieBody] = []
	for body: ZombieBody in _night.server.sim.zombies.values():
		if body.is_alive():
			dead.append(body)
	var forward := -Basis(Vector3.UP, yaw).z
	var right := Basis(Vector3.UP, yaw).x
	var origin := _night.state.position()
	var first := -0.5 * DEAD_SPACING * float(dead.size() - 1)
	for index in dead.size():
		var spot := origin + forward * distance + right * (first + DEAD_SPACING * index)
		dead[index].position = Vector3(spot.x, dead[index].position.y, spot.z)
		dead[index].yaw = yaw + PI
		dead[index].velocity = Vector3.ZERO
		if dead[index].mode == ZombieBody.Mode.ATTACK:
			dead[index].enter(ZombieBody.Mode.CHASE)
