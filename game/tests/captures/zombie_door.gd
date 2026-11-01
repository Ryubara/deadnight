extends Node3D
## Capture of the dead and a bought door. A player waits inside the concession stand; a few
## zombies walk up to its door in the field; at BUY_AT seconds the door is bought through the rules.
## Not part of the game. Arguments after `--`:
##   `--mode=rebake`  (default) the lot's `LotDoors` opens the door and `DoorNavigation` rebakes:
##                    the zombies walk in;
##   `--mode=stale`   the door's slab goes but the navigation mesh is left as baked (what the game
##                    did before DoorNavigation): the zombies stay at the old wall.
##   `--saved=0`      with `rebake`, bake every mesh at run time instead of using the saved ones
##                    (`LotNavmeshes`): the zombies walk the same paths.

const GREYBOX := preload("res://world/drive_in_greybox.tscn")
const ZOMBIE_MODEL := "res://assets/zombie_kit/zombie.glb"
const BUY_AT := 6.0
const PLAYER_AT := Vector3(0, 0, 3)
## Where the dead rise: spread over the field in front of the concession door, one per point.
const SPAWNS: Array[Vector3] = [
	Vector3(-9, 0, -14),
	Vector3(-4, 0, -16),
	Vector3(4, 0, -16),
	Vector3(9, 0, -14),
	Vector3(-6, 0, -10),
	Vector3(6, 0, -10),
]

var _rules: GameRules
var _horde: ZombieHorde
var _doors: LotDoors
var _label: Label
var _clock := 0.0
var _accumulator := 0.0
var _bought := false
var _inside := 0
var _args := {}


func _ready() -> void:
	_args = _parse_args()
	var lot := GREYBOX.instantiate()
	add_child(lot)
	_doors = lot.get_node("Doors")
	# The stand's roof would hide the inside from this camera.
	lot.get_node("Concession/Roof").visible = false
	var tuning := _tuning()
	_rules = GameRules.new(tuning, 5)
	_rules.apply(RulesAction.add_player(1))
	_rules.apply(RulesAction.start())
	_rules.apply(RulesAction.grant_points(1, 1000))
	_doors.bind(_rules)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var map := get_world_3d().navigation_map
	if _args.get("mode", "rebake") == "stale":
		var region := NavigationRegion3D.new()
		region.navigation_mesh = NavmeshBaker.bake(lot)
		lot.add_child(region)
	else:
		var navigation := DoorNavigation.new()
		if _args.get("saved", "1") == "0":
			navigation.saved = null
		lot.add_child(navigation)
		navigation.setup(lot, _doors)
	while NavigationServer3D.map_get_path(map, SPAWNS[0], Vector3(0, 0, -30), true).is_empty():
		await get_tree().physics_frame
	_make_player()
	var camera := _make_camera()
	_make_ui()
	var sim := ZombieSim.new(ZombieTuning.new(), 5)
	sim.rounds = tuning.rounds
	sim.pathing = NavmeshPathing.new(map)
	var points: Array[Vector3] = SPAWNS.duplicate()
	var director := ZombieDirector.new(_rules, sim, points)
	_horde = ZombieHorde.new()
	_horde.model_scene = load(ZOMBIE_MODEL)
	add_child(_horde)
	_horde.setup(director, camera, sim.tuning.emerge_seconds)
	_rules.apply(RulesAction.skip_break())


func _tuning() -> RulesTuning:
	var tuning: RulesTuning = load("res://gameplay/rules/default_tuning.tres").duplicate(true)
	var rounds: RoundTuning = tuning.rounds
	rounds.count_base = 6.0
	rounds.count_linear = 0.0
	rounds.count_quadratic = 0.0
	rounds.alive_cap_start = 6.0
	rounds.alive_cap_max = 6.0
	rounds.spawn_interval_start = 1.0
	rounds.spawn_interval_min = 1.0
	rounds.first_spawn_delay = 0.5
	rounds.speed_base = 2.2
	rounds.speed_jitter = 0.0
	tuning.roster.type_of(&"runner").first_round = 99
	tuning.specials.every = 0
	return tuning


func _make_player() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	body.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.55, 0.95)
	body.material_override = material
	body.position = PLAYER_AT + Vector3(0, 0.85, 0)
	add_child(body)


func _make_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 15, -17), Vector3(0, 0, -3))
	camera.current = true
	return camera


func _make_ui() -> void:
	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_label)
	add_child(layer)


func _physics_process(delta: float) -> void:
	if _horde == null:
		return
	_accumulator += delta
	while _accumulator >= ZombieSim.STEP:
		_accumulator -= ZombieSim.STEP
		_clock += ZombieSim.STEP
		if not _bought and _clock >= BUY_AT:
			_bought = true
			_rules.apply(RulesAction.buy(1, &"door_concession"))
		_rules.apply(RulesAction.tick(ZombieSim.STEP))
		_horde.step(ZombieSim.STEP, {1: PLAYER_AT})
	_inside = 0
	for zombie: ZombieBody in _horde.director.sim.zombies.values():
		if zombie.position.z > -3.4:
			_inside += 1
	var mode: String = _args.get("mode", "rebake")
	_label.text = (
		"%s    door %s    zombies %d    inside the stand %d"
		% [
			"BEFORE: mesh left as baked" if mode == "stale" else "AFTER: mesh rebaked",
			"OPEN" if _bought else "closed",
			_horde.director.sim.standing_count(),
			_inside
		]
	)


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
