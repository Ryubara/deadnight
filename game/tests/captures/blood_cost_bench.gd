extends "res://tests/captures/crowd_cost_bench.gd"
## What hit blood costs a frame (issue #618): the crowd bench (a crowd running the lot, no HUD) with
## the real `ShotEffects` and the real world for the marks, and a hit on each of the N zombies
## nearest the camera every `1 / hits` seconds, as a firefight would land them. `?blood=0` draws
## none of it (the same hits are made, the effects are left out), so the difference is the blood.
## Not part of the game: `tools/web_smoke/blood_cost.py` exports a copy of the project that starts
## on this scene. Extra arguments: `--blood=0|1`, `--targets=N` (zombies hit, default 20),
## `--hits=H` (hits a second on each, default 4: 80 a second in all) and `--mix=gun|shotgun|rifle`.

const CHEST := 1.1
const HEAD := 1.62
const WEAPONS: Array[StringName] = [&"smg", &"shotgun", &"rifle", &"pistol"]

var _effects: ShotEffects
var _surface: WorldCast
var _blood_on := true
var _targets := 20
var _hits_per_second := 4.0
var _owed := 0.0
var _fired := 0


func _ready() -> void:
	await super._ready()
	_blood_on = int(_args.get("blood", 1)) != 0
	_targets = int(_args.get("targets", 20))
	_hits_per_second = float(_args.get("hits", 4.0))
	_effects = ShotEffects.new()
	add_child(_effects)
	_effects.prewarm()
	_surface = WorldCast.new(get_world_3d().direct_space_state)


func _process(delta: float) -> void:
	super._process(delta)
	if _horde == null or _effects == null:
		return
	_owed += delta * _hits_per_second * _targets
	var eye := _camera.global_position
	var near: Array[ZombieBody] = []
	for body: ZombieBody in _horde.director.sim.zombies.values():
		if body.is_alive():
			near.append(body)
	near.sort_custom(
		func(a: ZombieBody, b: ZombieBody) -> bool:
			return a.position.distance_squared_to(eye) < b.position.distance_squared_to(eye)
	)
	near.resize(mini(near.size(), _targets))
	while _owed >= 1.0 and not near.is_empty():
		_owed -= 1.0
		var body := near[_fired % near.size()]
		var head := _fired % 5 == 0
		var point := body.position + Vector3(0.0, HEAD if head else CHEST, 0.0)
		var event := {
			"type": &"damage_dealt",
			"point": point,
			"dir": (point - eye).normalized(),
			"weapon_id": WEAPONS[_fired % WEAPONS.size()],
			"headshot": head,
			"melee": false,
			"damage": 30.0,
			"pellets": 4 if _fired % WEAPONS.size() == 1 else 1,
		}
		_fired += 1
		if _blood_on:
			_effects.blood_hit(event, _surface.callable())
	_extra = {
		"blood": _blood_on,
		"targets": _targets,
		"hits_per_second": _hits_per_second,
		"hits_made": _fired,
		"splashes_alive": _effects.blood.splashes_alive(),
		"marks_alive": _effects.blood.marks_alive(),
		"mark_cap": _effects.blood.mark_cap,
	}
