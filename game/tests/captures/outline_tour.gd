extends Node
## Captures the outline through walls on the last three zombies of a round, in the real night: the
## player stands at a spot, and the three zombies of a one-round-of-three night stand behind a wall
## in front of the view (or, in the `open` spot, in the open). Not part of the game. Each spot holds
## `HOLD_FRAMES` frames; the frame numbered `spot * HOLD_FRAMES + HOLD_FRAMES - 1` (from 0) is the
## settled shot.
##
##     gds godot -- --path game res://tests/captures/outline_tour.tscn \
##         --write-movie <abs>/o.png --fixed-fps 10 --quit-after 34 -- \
##         [--off] [--hud] [--glow=N] [--thickness=N]
##
## `--off` switches the outline off (the "before" picture of the same spots); `--glow` and
## `--thickness` set the style. Prints SPOT <name> <frame> as each spot starts.
## In a browser (`tools/web_smoke/outline_capture.py` exports a copy of the project that starts
## here) the page's query gives the same arguments, `?spot=near&off=1&hold=60`: only that spot is
## held, and then `window.__outline` says so and the page is photographed.

const HOLD_FRAMES := 10
const SEED := 5
## Where the player stands (lot metres), the view's yaw and pitch (degrees), and where the dead
## stand: `behind` metres past the first wall the view meets, or `ahead` metres in front of the
## camera.
const SPOTS := [
	{"name": "near", "at": Vector3(0, 0, -6), "yaw": 180.0, "pitch": 6.0, "behind": 3.0},
	{"name": "far", "at": Vector3(0, 0, -34), "yaw": 180.0, "pitch": 4.0, "behind": 5.0},
	{"name": "open", "at": Vector3(0, 0, -34), "yaw": 180.0, "pitch": 6.0, "ahead": 14.0},
]
const DEAD_SPACING := 1.6
## The page's query is read as the arguments of the command line.
const QUERY := "location.search.replace(/^\\?/, '')"

var _night: Night
var _frame := 0
var _spot := -1
var _args := {}
var _hold := HOLD_FRAMES
var _first := 0
var _last := 0
var _told := false


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=")
		_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	if OS.has_feature("web"):
		for pair in str(JavaScriptBridge.eval(QUERY)).split("&", false):
			var parts := pair.split("=", true, 1)
			_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	_hold = int(_args.get("hold", HOLD_FRAMES))
	_last = SPOTS.size() - 1
	if _args.has("spot"):
		for index in SPOTS.size():
			if SPOTS[index]["name"] == _args["spot"]:
				_first = index
				_last = index
	var layer := CanvasLayer.new()
	add_child(layer)
	_night = Night.new()
	if _args.has("hud"):
		var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
		layer.add_child(hud)
		_night.hud = hud
	add_child(_night)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.first_spawn_delay = 0.2
	tuning.rounds.spawn_interval_start = 0.2
	tuning.rounds.count_base = 3.0
	await _night.start(Night.Mode.MANUAL, SEED, tuning)
	_night.server.rules.apply(RulesAction.skip_break())
	var marks := _night.view.marks
	marks.enabled = not _args.has("off")
	if _args.has("glow"):
		marks.style.glow = float(_args["glow"])
	if _args.has("thickness"):
		marks.style.thickness = float(_args["thickness"])
	_night.ticked.connect(_pose)


func _process(_delta: float) -> void:
	if _night == null or not _night.running:
		return
	_frame += 1
	var spot := _first + (_frame - 1) / _hold
	if spot > _last:
		_finish()
		return
	if spot != _spot:
		_spot = spot
		print("SPOT ", SPOTS[spot]["name"], " ", _frame - 1)


## A desktop run ends; a page tells the probe that is photographing it that the spot has settled.
func _finish() -> void:
	if not OS.has_feature("web"):
		get_tree().quit()
		return
	if not _told:
		_told = true
		var line := "window.__outline = {spot: '%s', off: %s}"
		JavaScriptBridge.eval(line % [SPOTS[_last]["name"], str(_args.has("off")).to_lower()])


func _pose() -> void:
	if _spot < 0 or _spot > _last:
		return
	var spot: Dictionary = SPOTS[_spot]
	var player := _night.player()
	player.teleport(spot["at"])
	var rig := player.camera_rig
	rig.yaw = deg_to_rad(spot["yaw"])
	rig.pitch = deg_to_rad(spot["pitch"])
	var camera := rig.camera()
	var forward := -camera.global_basis.z
	var ahead := Vector3(forward.x, 0.0, forward.z).normalized()
	var base := camera.global_position + ahead * float(spot.get("ahead", 0.0))
	if spot.has("behind"):
		var space := get_viewport().world_3d.direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			camera.global_position, camera.global_position + forward * 80.0
		)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return
		base = hit["position"] + ahead * float(spot["behind"])
	var right := ahead.cross(Vector3.UP).normalized() * -1.0
	var dead: Array[ZombieBody] = []
	for body: ZombieBody in _night.server.sim.zombies.values():
		if body.is_alive():
			dead.append(body)
	var first := -0.5 * DEAD_SPACING * float(dead.size() - 1)
	for index in dead.size():
		var at := base + right * (first + DEAD_SPACING * index)
		dead[index].position = Vector3(at.x, 0.0, at.z)
		dead[index].yaw = deg_to_rad(spot["yaw"]) + PI
		dead[index].velocity = Vector3.ZERO
		if dead[index].mode == ZombieBody.Mode.ATTACK:
			dead[index].enter(ZombieBody.Mode.CHASE)
