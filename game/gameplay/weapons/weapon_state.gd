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
## The part of the last tick the wait did not need (the cooldown ran out part way through it).
## The next shot takes it off its wait, so a weapon whose interval is not a whole number of ticks
## still reaches its rate on average. Under one tick, and gone a tick after the weapon was ready:
## a pause banks nothing.
var carry: float = 0.0
var reload_left: float = 0.0
## By-round reload (`WeaponDef.reload_by_round`): seconds each round takes, the wait until the next
## one is in, and how many went in during the last tick (the server says so, a round at a time).
var round_time: float = 0.0
var round_left: float = 0.0
var loaded_last_tick: int = 0
## The reload the last shot ended (a by-round reload a round had been loaded into).
var interrupted: bool = false
## The hand of the last shot of a dual weapon (`WeaponDef.dual`): 0 the right, 1 the left. The
## shots alternate, right first, and a reload does not change whose turn it is. Always 0 for a
## weapon held in one hand.
var hand: int = 0
var _next_hand: int = 0


func _init(p_def: WeaponDef) -> void:
	def = p_def
	ammo = def.magazine_size
	reserve = def.reserve_start


func uses_ammo() -> bool:
	return not def.is_melee()


func is_reloading() -> bool:
	return reload_left > 0.0


## Why a shot cannot happen now (`&"reloading"`, `&"cooldown"`, `&"empty"`), or `&""` when it can.
## A by-round reload gives way to a shot once a round is in the magazine.
func fire_block() -> StringName:
	if is_reloading() and not (def.reload_by_round and ammo > 0):
		return &"reloading"
	if cooldown > READY_EPSILON:
		return &"cooldown"
	if uses_ammo() and ammo <= 0:
		return &"empty"
	return &""


## Spends the round and starts the wait, shortened by the carried part of the tick
## (`interval_scale` is the fire-rate perk's share of it, 1 without). Call only when
## `fire_block()` is empty. The wait never ends inside the tick of the shot, so a weapon fires at
## most once a tick however short its interval.
func fire(interval_scale: float = 1.0) -> void:
	interrupted = is_reloading()
	if interrupted:
		cancel_reload()
	cooldown = maxf(def.fire_interval * interval_scale - carry, 2.0 * READY_EPSILON)
	carry = 0.0
	if uses_ammo():
		ammo -= 1
	if def.dual:
		hand = _next_hand
		_next_hand = 1 - _next_hand


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


## Starts the reload; `time_scale` is the reload perk's share of its time (1 without).
func start_reload(time_scale: float = 1.0) -> void:
	if def.reload_by_round:
		round_time = def.round_seconds() * time_scale
		round_left = round_time
		reload_left = round_time * float(rounds_to_load())
		return
	reload_left = def.reload_time * time_scale


## How many rounds a reload now would load.
func rounds_to_load() -> int:
	return maxi(mini(def.magazine_size - ammo, reserve), 0)


## Adds rounds to the reserve, never past the weapon's limit. Returns how many fit.
func add_reserve(rounds: int) -> int:
	var added := clampi(rounds, 0, def.reserve_max - reserve)
	reserve += added
	return added


## Re-cuts the weapon (`WeaponDef.upgraded`): the magazine and the reserve come back full at their
## new size. The caller has checked `tier() == 0`.
func upgrade(spec: UpgradeTuning) -> void:
	def = def.upgraded(spec)
	cancel_reload()
	ammo = def.magazine_size
	reserve = def.reserve_max


## 0 as shipped, 1 once re-cut.
func tier() -> int:
	return def.tier


## Drops a reload in progress (the weapon was put away).
func cancel_reload() -> void:
	reload_left = 0.0
	round_left = 0.0


## Advances the clocks. Returns true on the step the reload completes.
func tick(delta: float) -> bool:
	_run_cooldown(delta)
	loaded_last_tick = 0
	if not is_reloading():
		return false
	if def.reload_by_round:
		return _tick_rounds(delta)
	reload_left -= delta
	if reload_left > READY_EPSILON:
		return false
	reload_left = 0.0
	var moved := mini(def.magazine_size - ammo, reserve)
	ammo += moved
	reserve -= moved
	return true


## A by-round reload: a round goes in each `round_time`; true on the tick the last one does.
func _tick_rounds(delta: float) -> bool:
	round_left -= delta
	while round_left <= READY_EPSILON and ammo < def.magazine_size and reserve > 0:
		ammo += 1
		reserve -= 1
		loaded_last_tick += 1
		round_left += round_time
	if ammo < def.magazine_size and reserve > 0:
		reload_left = round_left + float(rounds_to_load() - 1) * round_time
		return false
	reload_left = 0.0
	round_left = 0.0
	return true


## The wait runs down; on the tick it runs out, what was not needed is kept for the next shot.
## A weapon that was already ready keeps nothing: only a trigger held through the tick gets credit.
func _run_cooldown(delta: float) -> void:
	if cooldown <= READY_EPSILON:
		cooldown = 0.0
		carry = 0.0
		return
	cooldown -= delta
	if cooldown > READY_EPSILON:
		return
	carry = clampf(-cooldown, -READY_EPSILON, delta)
	cooldown = 0.0


func to_dict() -> Dictionary:
	return {
		"weapon_id": def.id,
		"ammo": ammo,
		"reserve": reserve,
		"cooldown": cooldown,
		"reload_left": reload_left,
	}
