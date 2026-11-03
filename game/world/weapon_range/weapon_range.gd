class_name WeaponRange
extends Node3D
## The test range: zombie dummies spawned by the real rules, a wall with a corner, a stand-in
## over-the-shoulder camera and a stand-in player. A scripted demo (`RangeDemo`) fires every weapon.
##
## It is a client of the server code, wired the way the game will be: the client predicts the
## flash and impact at once, sends a `CombatAction.fire` through a `LoopbackLink` (plain bytes), and
## the answer, damage numbers, kills, points, comes back as events. Not part of the game; there is
## no controller here (#14), only the camera offsets a controller will need.

signal sound_requested(weapon_id: StringName)

const PLAYER_ID := 1
const SEED := 20260101
const STEP := 1.0 / 60.0
## Rules time run before the demo starts, so the zombies are already on the lot.
const WARMUP_SECONDS := 20.0

const CHEST_OFFSET := Vector3(0, 1.1, 0)
const BODY_HEIGHT := 1.1
const HEAD_HEIGHT := 1.62
## Where the zombies the rules spawn stand, in spawn order. Slot 1 is behind slot 0 on a shot from
## the start position; slot 4 is behind the wall's corner.
const SLOTS: Array[Vector3] = [
	Vector3(4.0, 0, -9.0),
	Vector3(6.15, 0, -14.0),
	Vector3(-0.5, 0, -1.6),
	Vector3(6.0, 0, -5.5),
	Vector3(2.0, 0, -8.0),
	Vector3(3.8, 0, -4.5),
]
## A wall at z = -3 whose right end is at x = 1.1.
const WALL_BOX := AABB(Vector3(-5, 0, -3.1), Vector3(6.1, 2.2, 0.2))
const FLOOR_SIZE := Vector3(40, 0.2, 60)
const WALL_COLOUR := Color(0.42, 0.36, 0.30)
const FLOOR_COLOUR := Color(0.16, 0.17, 0.2)
const PROJECTILE_RADIUS := 0.14
const PROJECTILE_COLOUR := Color(1.0, 0.45, 0.2)
const MARK_EVERY := 5.0
const MARK_COUNT := 5

@export var latency_ticks: int = 0

@export_group("Camera")
## The shoulder camera's place, relative to the player's feet (metres).
@export var camera_offset := Vector3(0.8, 1.9, 2.5)
## The camera's field of view (degrees).
@export_range(20.0, 120.0, 1.0, "suffix:deg") var camera_fov := 55.0
@export_group("Barrel")
## Where the shots leave the barrel, relative to the player's feet (metres).
@export var muzzle_offset := Vector3(0.3, 1.45, -0.4)

var rules: GameRules
var server: CombatServer
var link: LoopbackLink
var effects: ShotEffects
## The world as the blood sees it, for the marks; held here, a Callable does not keep it alive.
var _surface: WorldCast

var _rig := Vector3.ZERO
var _look_at := Vector3(0, 1.1, -10)
var _seq := 0
var _client_weapon: WeaponState
var _probe: WorldProbe
var _dummies: Dictionary[int, ZombieDummy] = {}
var _spawned := 0
var _flares: Dictionary[int, Dictionary] = {}
var _note := ""
var _demo_time := 0.0
var _demo_steps: Array[Dictionary] = []
## `-- --log` prints every event the client receives.
var _log := OS.get_cmdline_user_args().has("--log")

@onready var _camera: Camera3D = $Camera3D
@onready var _hud: Label = $Hud/Readout
@onready var _player: MeshInstance3D = $Player


func _ready() -> void:
	effects = ShotEffects.new()
	add_child(effects)
	_build_stage()
	_start_night()
	_demo_steps = RangeDemo.steps()
	_update_camera()
	_update_hud()


func _exit_tree() -> void:
	server.detach()
	rules.event_emitted.disconnect(_on_rules_event)
	link.delivered.disconnect(_on_events)


func _physics_process(_delta: float) -> void:
	if _probe == null:
		# Static bodies reach the physics space on the first step.
		_probe = WorldProbe.new(get_world_3d().direct_space_state)
		server.world_ray = _probe.callable()
	rules.apply(RulesAction.tick(STEP))
	server.apply(CombatAction.targets(_target_list()))
	link.broadcast(server.apply(CombatAction.tick(STEP)))
	link.pump()
	if _client_weapon != null:
		_client_weapon.tick(STEP)
	_step_flares()
	_run_demo()
	_update_camera()
	_update_hud()


# --- The client's commands (what a controller will call) ---


## Puts a weapon in hand: asks the server, which answers with `weapon_equipped`.
func give(weapon_id: StringName) -> void:
	link.send(CombatAction.give_weapon(PLAYER_ID, weapon_id))


func move_rig(offset: Vector3) -> void:
	_rig += offset


## Pulls the trigger with the crosshair on `aim_point`.
func fire_at(aim_point: Vector3) -> void:
	_look_at = aim_point
	var origin := _rig + camera_offset
	var muzzle := _rig + muzzle_offset
	var dir := (aim_point - origin).normalized()
	if _client_weapon == null or _client_weapon.fire_block() != &"":
		return
	_client_weapon.fire()
	_seq += 1
	_predict(_client_weapon.def, origin, dir, muzzle)
	link.send(CombatAction.fire(PLAYER_ID, _seq, origin, dir, muzzle, server.now))
	sound_requested.emit(_client_weapon.def.id)


func swing_at(aim_point: Vector3) -> void:
	_look_at = aim_point
	if _client_weapon == null or _client_weapon.fire_block() != &"":
		return
	_client_weapon.fire()
	_seq += 1
	var chest := _rig + CHEST_OFFSET
	var dir := (aim_point - chest).normalized()
	effects.tracer(chest, chest + dir * _client_weapon.def.melee_range, 0.12)
	link.send(CombatAction.fire(PLAYER_ID, _seq, chest, dir, chest, server.now))


func zombie_position(slot: int) -> Vector3:
	return SLOTS[slot]


# --- Prediction ---


## The look of a shot, drawn from the client's own copy of the world before the server answers.
func _predict(def: WeaponDef, origin: Vector3, dir: Vector3, muzzle: Vector3) -> void:
	if def.is_projectile():
		effects.muzzle_flash(muzzle)
		return
	var seed_value := AimResolver.shot_seed(SEED, PLAYER_ID, _seq)
	var shot := AimResolver.trace_hitscan(
		def, origin, dir, muzzle, _client_targets(), _probe.callable(), seed_value
	)
	var ends: Array = []
	for pellet: Dictionary in shot["pellets"]:
		ends.append(pellet["end"])
	effects.shot(def, muzzle, ends)


func _client_targets() -> Dictionary:
	var targets := {}
	for id in _dummies:
		var dummy := _dummies[id]
		if is_instance_valid(dummy) and server.is_target_alive(id):
			targets[id] = {"pos": dummy.position, "yaw": dummy.rotation.y}
	return targets


# --- The server's answers ---


func _on_events(events: Array) -> void:
	for event: Dictionary in events:
		if _log:
			print("t=%.2f %s" % [server.now, event])
		match event["type"]:
			&"weapon_equipped":
				_client_weapon = WeaponState.new(WeaponCatalog.get_def(event["weapon_id"]))
				_client_weapon.ammo = event["ammo"]
				_client_weapon.reserve = event["reserve"]
			&"shot_fired":
				_client_weapon.ammo = event["ammo"]
				_client_weapon.reserve = event["reserve"]
			&"fire_rejected":
				_note = "refused: %s" % event["reason"]
			&"damage_dealt":
				_show_damage(event)
			&"target_killed":
				if _dummies.has(event["target_id"]):
					_dummies[event["target_id"]].die()
			&"projectile_spawned":
				_spawn_flare(event)
			&"projectile_burst":
				_end_flare(event)
			&"points_changed":
				_note = "points %d (%+d, %s)" % [event["total"], event["delta"], event["reason"]]


func _show_damage(event: Dictionary) -> void:
	var text := str(roundi(event["damage"]))
	effects.number(event["point"] + Vector3(0, 0.3, 0), text, event["headshot"])
	if _surface == null:
		_surface = WorldCast.new(get_world_3d().direct_space_state)
	effects.blood_hit(event, _surface.callable())
	var dummy := _dummies.get(event["target_id"]) as ZombieDummy
	if dummy != null and is_instance_valid(dummy):
		dummy.flash()
		dummy.show_health(event["health"])


func _spawn_flare(event: Dictionary) -> void:
	var def := WeaponCatalog.get_def(event["weapon_id"])
	var state := ProjectileState.new(
		event["projectile_id"], event["shooter_id"], def, event["position"], event["velocity"]
	)
	var mesh := SphereMesh.new()
	mesh.radius = PROJECTILE_RADIUS
	mesh.height = PROJECTILE_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = PROJECTILE_COLOUR
	mesh.material = material
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.position = state.position
	add_child(body)
	_flares[state.id] = {"state": state, "node": body}


## The client flies the flare with the same code as the server, to draw it; the server's burst
## says where and when it ends.
func _step_flares() -> void:
	for id in _flares:
		var flare: Dictionary = _flares[id]
		var state: ProjectileState = flare["state"]
		state.step(STEP, {}, Callable())
		(flare["node"] as Node3D).position = state.position


func _end_flare(event: Dictionary) -> void:
	var flare: Dictionary = _flares.get(event["projectile_id"], {})
	if not flare.is_empty():
		(flare["node"] as Node3D).queue_free()
		_flares.erase(event["projectile_id"])
	effects.spark(event["point"])
	effects.muzzle_flash(event["point"])


# --- The night ---


func _start_night() -> void:
	rules = GameRules.new(null, SEED)
	server = CombatServer.new(WeaponCatalog.all(), rules, Callable(), SEED)
	link = LoopbackLink.new(server, latency_ticks)
	link.delivered.connect(_on_events)
	rules.event_emitted.connect(_on_rules_event)
	rules.apply(RulesAction.add_player(PLAYER_ID))
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.skip_break())
	for _i in roundi(WARMUP_SECONDS / STEP):
		rules.apply(RulesAction.tick(STEP))


func _on_rules_event(event: Dictionary) -> void:
	if event["type"] != &"zombie_spawn_requested" or _spawned >= SLOTS.size():
		return
	var dummy := preload("res://world/weapon_range/zombie_dummy.tscn").instantiate() as ZombieDummy
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


func _run_demo() -> void:
	_demo_time += STEP
	while not _demo_steps.is_empty() and _demo_steps[0]["at"] <= _demo_time:
		(_demo_steps.pop_front()["do"] as Callable).call(self)


# --- Stage, camera, readout ---


func _build_stage() -> void:
	_add_box(Vector3(0, -FLOOR_SIZE.y / 2.0, -FLOOR_SIZE.z / 2.0 + 10.0), FLOOR_SIZE, FLOOR_COLOUR)
	_add_box(WALL_BOX.get_center(), WALL_BOX.size, WALL_COLOUR)
	for i in range(1, MARK_COUNT + 1):
		var label := Label3D.new()
		label.text = "%d m" % int(i * MARK_EVERY)
		label.rotation_degrees.x = -90.0
		label.position = Vector3(-1.5, 0.02, -i * MARK_EVERY)
		label.font_size = 64
		label.pixel_size = 0.01
		label.modulate = Color(0.5, 0.55, 0.65)
		add_child(label)


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


func _update_camera() -> void:
	_camera.fov = camera_fov
	_camera.look_at_from_position(_rig + camera_offset, _look_at)
	_player.position = _rig + Vector3(0, 0.9, 0)


func _update_hud() -> void:
	var held := ""
	if _client_weapon != null:
		var def := _client_weapon.def
		held = def.display_name
		if def.is_melee():
			held += "   (melee)"
		else:
			held += "   %d / %d" % [_client_weapon.ammo, _client_weapon.reserve]
			if _client_weapon.is_reloading():
				held += "   reloading"
	_hud.text = (
		"%s\nround %d   points %d\n%s"
		% [held, rules.round_number, rules.points_of(PLAYER_ID), _note]
	)
