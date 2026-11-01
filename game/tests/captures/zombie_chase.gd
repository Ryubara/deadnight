extends Node3D
## Capture and benchmark of the zombie crowd chasing in the greybox lot. Not part of the game.
## Arguments after `--`: `--warmup=SECONDS` (simulated before the first frame is drawn),
## `--seed=N`, `--zombies=N` (the cap the rules are given), `--bench` (print frame times and quit),
## `--empty` (no zombies at all, to measure the empty lot), `--frames=N` (bench length).

const GREYBOX := preload("res://world/drive_in_greybox.tscn")
const PLAYER_SPEED := 5.0
## Waypoints player 1 runs between (metres), then stands at the last.
const ROUTE: Array[Vector3] = [
	Vector3(-6, 0, -43),
	Vector3(-6, 0, -24),
	Vector3(14, 0, -24),
	Vector3(14, 0, -38),
]
const LAMP_REACH := 6.0
const BENCH_WARMUP_FRAMES := 120
const SHOOT_FROM_SECONDS := 8.0

var _rules: GameRules
var _horde: ZombieHorde
var _camera: Camera3D
var _label: Label
var _positions: Dictionary[int, Vector3] = {1: ROUTE[0], 2: Vector3(6, 0, -43)}
var _route_index := 1
var _clock := 0.0
var _warming := false
var _accumulator := 0.0
var _strikes := 0
var _kills := 0
var _lamps: Array[Node] = []
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _last_usec := 0
var _args := {}


func _ready() -> void:
	_args = _parse_args()
	var greybox := GREYBOX.instantiate()
	add_child(greybox)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var region := NavigationRegion3D.new()
	region.navigation_mesh = NavmeshBaker.bake(greybox)
	var map := get_world_3d().navigation_map
	var before := NavigationServer3D.map_get_iteration_id(map)
	add_child(region)
	# A new region reaches path queries after the map's second iteration.
	while NavigationServer3D.map_get_iteration_id(map) < before + 2:
		await get_tree().physics_frame
	_lamps = get_tree().get_nodes_in_group("powered_light")
	_make_players()
	_make_camera()
	_make_ui()
	_make_zombies(greybox)
	_warm_up(float(_args.get("warmup", 0.0)))
	_last_usec = Time.get_ticks_usec()


func _make_players() -> void:
	for id in _positions:
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.7
		body.mesh = capsule
		body.name = "Player%d" % id
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.3, 0.55, 0.95) if id == 1 else Color(0.95, 0.75, 0.3)
		body.material_override = material
		add_child(body)


func _make_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 65.0
	_camera.current = true
	add_child(_camera)
	_place_camera()


func _make_ui() -> void:
	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_label)
	add_child(layer)


func _make_zombies(greybox: Node) -> void:
	var tuning: RulesTuning = _crowd_tuning()
	_rules = GameRules.new(tuning, int(_args.get("seed", 5)))
	_rules.apply(RulesAction.add_player(1))
	_rules.apply(RulesAction.add_player(2))
	var cap := ZombieTuning.new()
	var sim := ZombieSim.new(cap, int(_args.get("seed", 5)))
	sim.rounds = tuning.rounds
	sim.pathing = NavmeshPathing.new(get_world_3d().navigation_map)
	sim.lit_probe = _is_lit
	var points: Array[Vector3] = []
	for marker in greybox.get_node("Field/ZombieSpawns").get_children():
		points.append((marker as Marker3D).global_position)
	var director := ZombieDirector.new(_rules, sim, points)
	director.player_struck.connect(func(_p: int, _z: int, _d: float) -> void: _strikes += 1)
	_horde = ZombieHorde.new()
	add_child(_horde)
	_horde.setup(director, _camera, cap.emerge_seconds)
	if not _args.has("empty"):
		_rules.apply(RulesAction.start())
		_rules.apply(RulesAction.skip_break())


## The shipped table with a bigger, faster, earlier crowd than round 1 so the capture shows 40.
func _crowd_tuning() -> RulesTuning:
	var tuning: RulesTuning = load("res://gameplay/rules/default_tuning.tres").duplicate(true)
	var rounds: RoundTuning = tuning.rounds
	rounds.count_base = 120.0
	rounds.alive_cap_start = float(_args.get("zombies", 40)) + 10.0
	rounds.alive_cap_max = rounds.alive_cap_start
	rounds.alive_cap_per_extra_player = 0.0
	rounds.spawn_interval_start = 0.25
	rounds.spawn_interval_min = 0.25
	rounds.spawn_rate_per_extra_player = 0.0
	rounds.first_spawn_delay = 0.1
	rounds.speed_base = 1.8
	# Three in ten run: the runner type from round 1, with no first-round exact count.
	var runner := tuning.roster.type_of(&"runner")
	runner.first_round = 1
	runner.share_start = 0.3
	runner.share_step = 0.0
	runner.share_max = 0.3
	return tuning


func _is_lit(point: Vector3) -> bool:
	for lamp: Light3D in _lamps:
		if (
			lamp.visible
			and (
				Vector2(point.x - lamp.global_position.x, point.z - lamp.global_position.z).length()
				< LAMP_REACH
			)
		):
			return true
	return false


func _warm_up(seconds: float) -> void:
	_warming = true
	for _i in ceili(seconds / ZombieSim.STEP):
		_sim_step()
	_horde.publish(0.0)
	_warming = false
	_clock = 0.0
	_strikes = 0
	_kills = 0


func _physics_process(delta: float) -> void:
	if _horde == null:
		return
	_accumulator += delta
	while _accumulator >= ZombieSim.STEP:
		_accumulator -= ZombieSim.STEP
		_sim_step()


func _sim_step() -> void:
	_clock += ZombieSim.STEP
	_move_player()
	_rules.apply(RulesAction.tick(ZombieSim.STEP))
	_shoot()
	var targets: Dictionary = {}
	for id in _positions:
		targets[id] = _positions[id]
	_horde.step(ZombieSim.STEP, targets)


func _move_player() -> void:
	if _warming or _route_index >= ROUTE.size():
		return
	var to_next := ROUTE[_route_index] - _positions[1]
	var step := PLAYER_SPEED * ZombieSim.STEP
	if to_next.length() <= step:
		_positions[1] = ROUTE[_route_index]
		_route_index += 1
	else:
		_positions[1] += to_next.normalized() * step


## From a few seconds in, player 2 shoots the nearest zombie in reach twice a second: a body shot
## (a stagger), then a headshot (the kill).
func _shoot() -> void:
	if _warming or _clock < SHOOT_FROM_SECONDS or fmod(_clock, 0.5) > ZombieSim.STEP:
		return
	var sim := _horde.director.sim
	var best_id := -1
	var best := 9.0
	for zombie: ZombieBody in sim.zombies.values():
		var d := zombie.position.distance_to(_positions[2])
		if zombie.is_alive() and d < best:
			best = d
			best_id = zombie.id
	if best_id == -1:
		return
	var body_shot := int(_clock * 2.0) % 2 == 0
	var result := _horde.director.take_hit(
		best_id, &"body" if body_shot else &"head", 40.0 if body_shot else 80.0, 2
	)
	if result["killed"]:
		_kills += 1


func _process(_delta: float) -> void:
	if _horde == null:
		return
	_place_camera()
	var sim := _horde.director.sim
	_label.text = (
		"zombies %d (waiting %d)   kills %d   blows on players %d   snapshot %d B   views %d"
		% [
			sim.standing_count(),
			_horde.director.waiting_count(),
			_kills,
			_strikes,
			_horde.last_snapshot_bytes,
			_horde.view_count()
		]
	)
	_record_frame()


func _place_camera() -> void:
	var focus := (_positions[1] + _positions[2]) * 0.5
	_camera.look_at_from_position(focus + Vector3(0, 17.0, 9.0), focus + Vector3(0, 0.0, -3.0))
	for i in range(_positions.size()):
		var body := get_node_or_null("Player%d" % (i + 1)) as Node3D
		if body != null:
			body.global_position = _positions[i + 1] + Vector3(0, 0.85, 0)


func _record_frame() -> void:
	if not _args.has("bench"):
		return
	var now := Time.get_ticks_usec()
	_frame_ms.append((now - _last_usec) / 1000.0)
	_last_usec = now
	var wanted := BENCH_WARMUP_FRAMES + int(_args.get("frames", 400))
	if _frame_ms.size() >= wanted:
		_report_and_quit()


func _report_and_quit() -> void:
	var sample := _frame_ms.slice(BENCH_WARMUP_FRAMES)
	var sorted := Array(sample)
	sorted.sort()
	var total := 0.0
	for ms in sample:
		total += ms
	var sim := _horde.director.sim
	print(
		(
			"BENCH zombies=%d views=%d mean_ms=%.2f p95_ms=%.2f advanced=%d draws=%d snapshot_bytes=%d"
			% [
				sim.standing_count(),
				_horde.view_count(),
				total / sample.size(),
				sorted[int(sorted.size() * 0.95)],
				_horde.throttle.advanced_last_frame,
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
				),
				_horde.last_snapshot_bytes
			]
		)
	)
	get_tree().quit()


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
