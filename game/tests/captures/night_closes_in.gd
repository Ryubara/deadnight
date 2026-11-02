extends Node
## Captures the night closing in (Deadnight #314) from the player's own shoulder camera: the real
## night at one round (the rules' round number is set, the next round begins by the break being
## skipped, and the light is given the whole of its ease), the dead lined up 7 m and then 25 m in
## front of the player, on the field with the HUD drawn. Run it once for each round to compare:
##
##     godot --path game res://tests/captures/night_closes_in.tscn --write-movie <abs>/r08.png \
##         --fixed-fps 10 --resolution 1280x720 --quit-after 30 -- --round=8
## Frame 9 is the dead at 7 m, frame 19 the dead at 25 m (counting from 0).

const HOLD_FRAMES := 10
const SEED := 5
const AT := Vector3(0, 0, -30)
const DISTANCES := [7.0, 25.0]
const DEAD_SPACING := 2.2

var _night: Night
var _frame := 0
var _round := 1


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--round="):
			_round = int(argument.trim_prefix("--round="))
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.first_spawn_delay = 0.2
	tuning.rounds.spawn_interval_start = 0.2
	tuning.rounds.spawn_interval_min = 0.2
	await _night.start(Night.Mode.MANUAL, SEED, tuning)
	_night.server.rules.round_number = _round - 1
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	_night.ticked.connect(_pose)


func _process(_delta: float) -> void:
	if _night == null or not _night.running:
		return
	_frame += 1
	if _frame == 1:
		for _i in 5:
			_night.tick()
		var light := _night.get_node_or_null("NightLight") as NightLight  # not there on `main`
		if light != null:
			light.advance(LightTuning.current().ease_seconds)
		print("ROUND ", _round, " light ", light.level if light != null else "fixed")
	if _frame > HOLD_FRAMES * DISTANCES.size():
		get_tree().quit()


func _pose() -> void:
	var player := _night.player()
	player.teleport(AT)
	var rig := player.camera_rig
	rig.yaw = PI
	rig.pitch = deg_to_rad(3.0)
	var distance: float = DISTANCES[clampi((_frame - 1) / HOLD_FRAMES, 0, DISTANCES.size() - 1)]
	var dead: Array[ZombieBody] = []
	for body: ZombieBody in _night.server.sim.zombies.values():
		if body.is_alive():
			dead.append(body)
	var forward := -Basis(Vector3.UP, rig.yaw).z
	var right := Basis(Vector3.UP, rig.yaw).x
	var first := -0.5 * DEAD_SPACING * float(dead.size() - 1)
	for index in dead.size():
		var spot := (
			_night.state.position() + forward * distance + right * (first + DEAD_SPACING * index)
		)
		dead[index].position = Vector3(spot.x, dead[index].position.y, spot.z)
		dead[index].yaw = rig.yaw + PI
		dead[index].velocity = Vector3.ZERO
		if dead[index].mode == ZombieBody.Mode.ATTACK:
			dead[index].enter(ZombieBody.Mode.CHASE)
