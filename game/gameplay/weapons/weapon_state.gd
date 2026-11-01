class_name WeaponState
extends RefCounted
## One carried weapon: rounds in the magazine, rounds in reserve, the wait until the next shot and
## the reload in progress. The server owns the real one; a client keeps its own copy only to gate
## the instant muzzle flash and sound, and the server's events set it right.
##
## Time passes only through `tick(delta)`.

## A cooldown this small counts as over (a fixed step never lands exactly).
const READY_EPSILON := 1e-4

var def: WeaponDef
var ammo: int = 0
var reserve: int = 0
var cooldown: float = 0.0
var reload_left: float = 0.0


func _init(p_def: WeaponDef) -> void:
	def = p_def
	ammo = def.magazine_size
	reserve = def.reserve_start


func uses_ammo() -> bool:
	return not def.is_melee()


func is_reloading() -> bool:
	return reload_left > 0.0


## Why a shot cannot happen now (`&"reloading"`, `&"cooldown"`, `&"empty"`), or `&""` when it can.
func fire_block() -> StringName:
	if is_reloading():
		return &"reloading"
	if cooldown > READY_EPSILON:
		return &"cooldown"
	if uses_ammo() and ammo <= 0:
		return &"empty"
	return &""


## Spends the round and starts the wait. Call only when `fire_block()` is empty.
func fire() -> void:
	cooldown = def.fire_interval
	if uses_ammo():
		ammo -= 1


## Why a reload cannot start (`&"reloading"`, `&"full"`, `&"no_reserve"`, `&"melee"`), or `&""`.
func reload_block() -> StringName:
	if not uses_ammo():
		return &"melee"
	if is_reloading():
		return &"reloading"
	if ammo >= def.magazine_size:
		return &"full"
	if reserve <= 0:
		return &"no_reserve"
	return &""


func start_reload() -> void:
	reload_left = def.reload_time


## Adds rounds to the reserve, never past the weapon's limit. Returns how many fit.
func add_reserve(rounds: int) -> int:
	var added := clampi(rounds, 0, def.reserve_max - reserve)
	reserve += added
	return added


## Drops a reload in progress (the weapon was put away).
func cancel_reload() -> void:
	reload_left = 0.0


## Advances the clocks. Returns true on the step the reload completes.
func tick(delta: float) -> bool:
	cooldown = maxf(cooldown - delta, 0.0)
	if not is_reloading():
		return false
	reload_left -= delta
	if reload_left > READY_EPSILON:
		return false
	reload_left = 0.0
	var moved := mini(def.magazine_size - ammo, reserve)
	ammo += moved
	reserve -= moved
	return true


func to_dict() -> Dictionary:
	return {
		"weapon_id": def.id,
		"ammo": ammo,
		"reserve": reserve,
		"cooldown": cooldown,
		"reload_left": reload_left,
	}
