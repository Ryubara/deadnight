class_name GrenadeRange
extends Node3D
## The grenade test range: zombie dummies spawned by the real rules, a low barrier, a pillar, a
## back wall and a stand-in player who throws. A scripted demo cooks and throws one grenade.
##
## It is a client of the server code, wired the way the game will be: the player's buttons become
## `PlayerCommand`s, `GrenadeThrower` turns them into actions that go to the `GrenadeServer`
## as plain bytes, the client predicts the throw at once with the same `GrenadeState` code, and
## the server's events (bounce, blast, hits, crippled zombies) correct and decorate it.

signal sound_requested(id: StringName, at: Vector3)

const DUMMY_SCENE := preload("res://world/weapon_range/zombie_dummy.tscn")
const PLAYER_ID := 1
const SEED := 20260102
const STEP := 1.0 / 60.0
const WARMUP_SECONDS := 20.0

const PLAYER_FEET := Vector3(0.0, 0.0, 2.0)
const HAND_OFFSET := Vector3(0.35, 1.45, -0.35)
const CAMERA_POSITION := Vector3(5.5, 7.0, 1.0)
const CAMERA_TARGET := Vector3(2.4, 0.2, -8.6)
const CAMERA_FOV := 55.0
## Where the demo's cooked overarm throw is aimed.
const DEMO_AIM := Vector3(0.15, 0.0, -1.0)
const DEMO_COOK_SECONDS := 1.4
## Zombie slots, in spawn order (see `docs/research/grenades.md` for which is which).
const SLOTS: Array[Vector3] = [
	Vector3(2.0, 0, -10.2),
	Vector3(3.6, 0, -12.2),
	Vector3(1.0, 0, -12.2),
	Vector3(3.2, 0, -5.2),
	Vector3(-1.6, 0, -11.3),
	Vector3(6.8, 0, -11.3),
]
## The pillar, the low barrier and the back wall, as boxes (corner, size).
const PILLAR := AABB(Vector3(0.0, 0, -12.5), Vector3(0.5, 3.0, 2.4))
const BARRIER := AABB(Vector3(5.0, 0, -12.9), Vector3(0.4, 0.7, 3.2))
const BACK_WALL := AABB(Vector3(-20, 0, -13.4), Vector3(40, 3.5, 0.4))
const FLOOR_SIZE := Vector3(40, 0.2, 60)
const WALL_COLOUR := Color(0.42, 0.36, 0.30)
const FLOOR_COLOUR := Color(0.16, 0.17, 0.2)
const VIEW_SCALE := 2.5
const CRAWLER_SQUASH := 0.42
const KNOCK_SECONDS := 0.35
const KNOCK_SCALE := 0.18

var rules: GameRules
var server: GrenadeServer
var effects: ShotEffects

var _def: GrenadeDef
var _thrower: GrenadeThrower
var _cast: WorldCast
var _probe: WorldProbe
var _views: Dictionary[int, GrenadeView] = {}
var _predicted: Array[GrenadeView] = []
var _dummies: Dictionary[int, ZombieDummy] = {}
var _spawned := 0
var _held := false
var _aim := DEMO_AIM
var _demo_time := 0.0
var _demo_steps: Array[Dictionary] = []
var _note := ""
var _crippled := 0
var _killed := 0
var _arc: MeshInstance3D
var _tick_clock := 0.0
var _log := OS.get_cmdline_user_args().has("--log")

@onready var _camera: Camera3D = $Camera3D
@onready var _hud: Label = $Hud/Readout
@onready var _player: MeshInstance3D = $Player


func _ready() -> void:
	_def = load("res://gameplay/grenades/defs/frag.tres")
	effects = ShotEffects.new()
	add_child(effects)
	_build_stage()
	_start_night()
	_thrower = GrenadeThrower.new(PLAYER_ID, _def)
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.listener = _camera
		sound_requested.connect(func(id: StringName, at: Vector3) -> void: audio.play(id, at))
	_demo_steps = _steps()
	_camera.fov = CAMERA_FOV
	_camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET)
	_player.position = PLAYER_FEET + Vector3(0, 0.9, 0)
	_update_hud()


func _exit_tree() -> void:
	if server != null:
		server.detach()
		rules.event_emitted.disconnect(_on_rules_event)
		_release(rules.generator)


## `GameRules` connects lambdas that capture itself to its generator, a reference cycle that
## Godot reports as leaked resources at exit. Cutting those connections ends the cycle.
func _release(emitter: Object) -> void:
	for signal_info in emitter.get_signal_list():
		for connection in emitter.get_signal_connection_list(signal_info["name"]):
			emitter.disconnect(signal_info["name"], connection["callable"])


func _physics_process(_delta: float) -> void:
	if _cast == null:
		# Static bodies reach the physics space on the first step.
		var space := get_world_3d().direct_space_state
		_cast = WorldCast.new(space)
		_probe = WorldProbe.new(space)
		server.world_cast = _cast.callable()
		server.world_ray = _probe.callable()
	rules.apply(RulesAction.tick(STEP))
	_run_demo()
	_send_player_command()
	server.apply(GrenadeAction.targets(_target_list()))
	server.apply(GrenadeAction.players([{"id": PLAYER_ID, "pos": PLAYER_FEET}]))
	_on_events(server.apply(GrenadeAction.tick(STEP)))
	_step_predicted()
	_play_cook_ticks()
	_update_hud()


# --- The player's side (what a controller will call) ---


## The command this tick: the buttons held now. The thrower turns it into actions for the server.
func _send_player_command() -> void:
	var command := PlayerCommand.new()
	command.throw_over = _held
	var cooked := _thrower.cooked_for(STEP)
	var was_cooking := _thrower.is_cooking()
	for action in _thrower.step(command, hand(), _aim, Vector3.ZERO):
		if action["type"] == GrenadeAction.THROW and was_cooking:
			_predict_throw(action, cooked)
		_on_events(server.apply(bytes_to_var(var_to_bytes(action))))


func hand() -> Vector3:
	return PLAYER_FEET + HAND_OFFSET


## The client draws the throw at once, from its own copy of the grenade; the server's
## `grenade_thrown` (same tick on a loopback, later on a real link) corrects it.
func _predict_throw(action: Dictionary, cooked: float) -> void:
	var view := _new_view()
	view.state = GrenadeState.new(
		0,
		PLAYER_ID,
		_def,
		action["hand"],
		_def.launch_velocity(action["aim"], action["underarm"], action["velocity"]),
		maxf(_def.fuse - cooked, _def.min_fuse_left)
	)
	_predicted.append(view)
	sound_requested.emit(&"grenade_throw", action["hand"])


func _new_view() -> GrenadeView:
	var view := GrenadeView.new()
	view.visual_scale = VIEW_SCALE
	view.trail = true
	add_child(view)
	return view


func _step_predicted() -> void:
	for view in _predicted:
		view.state.step(STEP, _cast.callable())
		view.follow(STEP)
	for id in _views:
		var view := _views[id]
		view.state.step(STEP, _cast.callable())
		view.follow(STEP)


func _play_cook_ticks() -> void:
	if not _thrower.is_cooking():
		_tick_clock = 0.0
		return
	_tick_clock += STEP
	var progress := clampf(_thrower.cooked_for(STEP) / _def.fuse, 0.0, 1.0)
	var period := lerpf(0.5, 0.07, progress * progress)
	if _tick_clock >= period:
		_tick_clock = 0.0
		sound_requested.emit(&"grenade_tick", hand())


# --- The server's answers ---


func _on_events(events: Array) -> void:
	for event: Dictionary in events:
		if _log:
			print("t=%.2f %s" % [server.now, event])
		match event["type"]:
			&"grenade_thrown":
				_adopt(event)
			&"grenade_bounced":
				sound_requested.emit(&"grenade_bounce", event["point"])
			&"grenade_exploded":
				_explode(event)
			&"blast_hit":
				_hit_dummy(event)
			&"player_blasted":
				_note = "thrower hurt for %d" % roundi(event["damage"])
			&"cook_rejected", &"throw_rejected":
				_note = "refused: %s" % event["reason"]
			&"zombie_crippled":
				_cripple(event)
			&"zombie_removed":
				_remove(event)
			&"zombie_damaged":
				var dummy := _dummies.get(event["zombie_id"]) as ZombieDummy
				if dummy != null and is_instance_valid(dummy):
					dummy.show_health(event["health"])


## The server's grenade replaces the prediction that made the same throw.
func _adopt(event: Dictionary) -> void:
	var view: GrenadeView = _predicted.pop_front() if not _predicted.is_empty() else _new_view()
	if view.state == null:
		view.state = GrenadeState.new(
			event["grenade_id"],
			event["thrower_id"],
			_def,
			event["position"],
			event["velocity"],
			event["fuse_left"]
		)
	view.state.id = event["grenade_id"]
	_views[event["grenade_id"]] = view


func _explode(event: Dictionary) -> void:
	var view: GrenadeView = _views.get(event["grenade_id"])
	if view != null:
		view.queue_free()
		_views.erase(event["grenade_id"])
	var blast := BlastEffect.new()
	add_child(blast)
	blast.play(event["point"], _def)
	sound_requested.emit(&"grenade_blast", event["point"])
	_note = "boom%s" % (" (in hand)" if event["in_hand"] else "")


func _hit_dummy(event: Dictionary) -> void:
	var dummy := _dummies.get(event["target_id"]) as ZombieDummy
	if dummy == null or not is_instance_valid(dummy):
		return
	dummy.flash()
	effects.number(dummy.position + Vector3(0, 2.0, 0), str(roundi(event["damage"])), false)
	var impulse: Vector3 = event["impulse"]
	var tween := create_tween()
	var landing := dummy.position + Vector3(impulse.x, 0.0, impulse.z) * KNOCK_SCALE
	tween.tween_property(dummy, "position", landing, KNOCK_SECONDS).set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)


## A crawler: the dummy drops low and wide, and says so.
func _cripple(event: Dictionary) -> void:
	_crippled += 1
	var dummy := _dummies.get(event["zombie_id"]) as ZombieDummy
	if dummy == null or not is_instance_valid(dummy):
		return
	var tween := create_tween()
	tween.tween_property(dummy, "scale", Vector3(1.15, CRAWLER_SQUASH, 1.15), 0.3)
	effects.number(dummy.position + Vector3(0, 1.3, 0), "CRAWLER", true)


func _remove(event: Dictionary) -> void:
	var dummy := _dummies.get(event["zombie_id"]) as ZombieDummy
	if dummy == null or not is_instance_valid(dummy):
		return
	_killed += 1
	var blast := BlastEffect.new()
	add_child(blast)
	blast.gibs(dummy.position + Vector3(0, 1.0, 0), Vector3(0, 2.0, 0), event["zombie_id"])
	dummy.die()


# --- The night ---


func _start_night() -> void:
	rules = GameRules.new(null, SEED)
	server = GrenadeServer.new(_def, rules)
	rules.event_emitted.connect(_on_rules_event)
	rules.apply(RulesAction.add_player(PLAYER_ID))
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.skip_break())
	for _i in roundi(WARMUP_SECONDS / STEP):
		rules.apply(RulesAction.tick(STEP))


func _on_rules_event(event: Dictionary) -> void:
	if event["type"] != &"zombie_spawn_requested" or _spawned >= SLOTS.size():
		return
	var dummy := DUMMY_SCENE.instantiate() as ZombieDummy
	dummy.target_id = event["zombie_id"]
	dummy.position = SLOTS[_spawned]
	dummy.rotation.y = 0.0
	_spawned += 1
	add_child(dummy)
	dummy.show_health(event["health"])
	_dummies[dummy.target_id] = dummy


func _target_list() -> Array:
	var list: Array = []
	for id in _dummies:
		var dummy := _dummies[id]
		if is_instance_valid(dummy):
			list.append({"id": id, "pos": dummy.position, "yaw": dummy.rotation.y})
	return list


# --- The scripted demo ---


func _steps() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"at": 0.6, "do": func() -> void: _show_arc(true)})
	list.append({"at": 1.8, "do": func() -> void: _show_arc(false)})
	list.append({"at": 2.0, "do": func() -> void: _held = true})
	list.append({"at": 2.0 + DEMO_COOK_SECONDS, "do": func() -> void: _held = false})
	return list


func _run_demo() -> void:
	_demo_time += STEP
	while not _demo_steps.is_empty() and _demo_steps[0]["at"] <= _demo_time:
		(_demo_steps.pop_front()["do"] as Callable).call()


## The preview line, drawn with the same stepping the server uses.
func _show_arc(shown: bool) -> void:
	if _arc != null:
		_arc.queue_free()
		_arc = null
	if not shown:
		return
	var path := GrenadeArc.predict(_def, hand(), _aim, Vector3.ZERO, false, _cast.callable(), STEP)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in path["points"]:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.9, 0.4)
	mesh.surface_set_material(0, material)
	_arc = MeshInstance3D.new()
	_arc.mesh = mesh
	add_child(_arc)
	_note = "landing %s  bounces %d" % [path["landing"].snapped(Vector3.ONE * 0.1), path["bounces"]]


# --- Stage and readout ---


func _build_stage() -> void:
	_add_box(Vector3(0, -FLOOR_SIZE.y / 2.0, -FLOOR_SIZE.z / 2.0 + 10.0), FLOOR_SIZE, FLOOR_COLOUR)
	for box in [PILLAR, BARRIER, BACK_WALL]:
		_add_box(box.position + box.size / 2.0, box.size, WALL_COLOUR)


func _add_box(centre: Vector3, size: Vector3, colour: Color) -> void:
	var body := StaticBody3D.new()
	body.position = centre
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	body.add_child(instance)
	add_child(body)


func _update_hud() -> void:
	var fuse := ""
	if _thrower.is_cooking():
		var left := _def.fuse - _thrower.cooked_for(STEP)
		fuse = "   COOKING  fuse %.1f s" % left
	_hud.text = (
		"Grenades %d%s\nkilled %d   crawlers %d   points %d\n%s"
		% [
			rules.grenades_of(PLAYER_ID),
			fuse,
			_killed,
			_crippled,
			rules.points_of(PLAYER_ID),
			_note
		]
	)
