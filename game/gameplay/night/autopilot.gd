class_name Autopilot
extends RefCounted
## A bot that plays the night through the same `NightCommand` a person sends. It sees only what a
## client sees (`ClientState`, and the level's navigation map): its own position, the zombies in
## the latest frame, its points and the prompt the server shows for what is in reach. It keeps
## its distance from the nearest zombie, turns to it and shoots, reloads when the magazine runs
## dry, walks to the next door when it can afford it and buys it, buys rounds when the gun in hand
## is nearly out, buys the weapons on the walls and the crane with points to spare, swaps to a gun
## that has rounds, and puts boards back when it is standing at one with nothing to shoot.

## Metres: a zombie nearer than this is backed away from.
const KEEP_AWAY := 7.0
## Metres past which it does not bother shooting.
const SHOOT_RANGE := 20.0
const CHEST := 1.1
const EYE := 1.55
const MUZZLE := Vector3(0.3, 1.45, -0.4)
## Where it waits and fights from: the field in front of the screen.
const HOME := Vector3(0.0, 0.0, -34.0)
## Metres from a goal at which it counts as there.
const ARRIVED := 1.5
## Seconds pressed against something before it sidesteps, and for how long.
const STUCK_AFTER := 0.5
const SIDESTEP_FOR := 0.6
const BIG_PRICE := 1 << 30
## Points it keeps back for rounds when it saves for a weapon.
const AMMO_MONEY := 120
## Ticks between two looks at where to shop (a path query per spot), and between two swaps.
const PLAN_EVERY := 30
const SWAP_EVERY := 20
## Metres a path may end short of a spot for the spot to count as reachable.
const REACHABLE := 2.5
## It melees a zombie this close.
const MELEE_RANGE := 1.9

var state: ClientState
var map: RID
## `Callable(from, to) -> float`: distance to the first wall on the way, or -1 when clear.
var sight: Callable = Callable()
## Metres a door's price needs, by id; where to stand to buy it; the order to buy in.
var prices: Dictionary = {}
var door_goals: Dictionary = {}
var order: Array[StringName] = []
## The shop spots (`NightWorld.shop_spots`: kind, shop_id, position); the price of each weapon on a
## wall and of the crane by shop id; the price of a whole ammunition purchase by weapon; the shop
## ids it wants, cheapest first, and how many crane prizes there are.
var spots: Array[Dictionary] = []
var prices_of_goods: Dictionary = {}
var ammo_prices: Dictionary = {}
var wanted: Array[StringName] = []
var crane_prizes := 0
## Where to stand to put boards back across each breach, by id, and how many a whole one holds.
var repair_goals: Dictionary = {}
var whole_boards: int = 1

var _yaw := 0.0
var _sidestep := 0.0
var _stuck_for := 0.0
var _last_pos := Vector3.ZERO
var _ticks := 0
var _swap_wait := 0
var _shopping: Dictionary = {}


func _init(p_state: ClientState, p_map: RID) -> void:
	state = p_state
	map = p_map


## The command for this tick.
func decide(delta: float) -> NightCommand:
	var command := NightCommand.new()
	command.player_id = state.player_id
	command.motion.yaw = _yaw
	if not state.has_frame() or state.me().get("downed", true):
		return command
	var here := state.position()
	var near := _nearest(here, false)
	var target := _nearest(here, true)
	var prompt: Dictionary = state.me().get("prompt", {})
	var kind: StringName = prompt.get("kind", &"")
	var wish := Vector3.ZERO
	_ticks += 1
	_swap_wait = maxi(_swap_wait - 1, 0)
	if _ticks % PLAN_EVERY == 1:
		_shopping = _plan_shopping(here)
	var held := _held()
	var melee := held != null and held.is_melee()
	var fleeing := not near.is_empty() and _flat(here, near["position"]) < KEEP_AWAY and not melee
	if fleeing:
		wish = _flee(here, near["position"])
	elif melee and not near.is_empty():
		wish = _toward(here, near["position"])
	elif kind != &"door":
		wish = _toward(here, _goal())
	wish = _unstuck(wish, here, delta)
	if wish != Vector3.ZERO:
		_yaw = atan2(-wish.x, -wish.z)
		command.motion.move = Vector2(0.0, -1.0)
		command.motion.sprint = fleeing
	command.motion.yaw = _yaw
	if not target.is_empty():
		_aim(command, here, target["position"], target.get("look", ZombieModels.DEFAULT))
		var close := _flat(here, target["position"]) < MELEE_RANGE
		command.fire = not state.me().get("reloading", false) and (close or not melee)
	if _swap_wait == 0 and _wants_swap(held):
		command.swap = true
		_swap_wait = SWAP_EVERY
	var dry: bool = state.me().get("ammo", 0) <= 0 and state.me().get("reserve", 0) > 0
	command.reload = dry and not state.me().get("reloading", false)
	if kind == &"door":
		command.use = state.points() >= int(prompt.get("price", BIG_PRICE))
	elif kind == &"weapon" or kind == &"crane":
		command.use = _wants(prompt) and state.points() >= int(prompt.get("price", BIG_PRICE))
	elif kind == &"ammo":
		command.use = _low_on_rounds(held) and state.points() >= int(prompt.get("price", BIG_PRICE))
	elif kind == &"repair":
		command.use = target.is_empty()
	return command


## The weapon in hand, or null.
func _held() -> WeaponDef:
	var id: StringName = state.me().get("weapon", &"")
	return WeaponCatalog.get_def(id) if id != &"" else null


## Rounds a carried weapon has, magazine and reserve.
func _rounds_of(weapon_id: StringName) -> int:
	var arms: Dictionary = state.me().get("arms", {})
	var counts: Array = arms.get(weapon_id, [0, 0])
	return int(counts[0]) + int(counts[1])


## A firearm down to its last magazine: worth a trip for rounds.
func _low_on_rounds(held: WeaponDef) -> bool:
	return held != null and not held.is_melee() and _rounds_of(held.id) <= held.magazine_size


## Swap away from a melee weapon or an empty gun to one that can shoot; from an empty gun to the
## melee weapon when nothing else can.
func _wants_swap(held: WeaponDef) -> bool:
	if held == null:
		return false
	if not held.is_melee() and _rounds_of(held.id) > 0:
		return false
	var arms: Dictionary = state.me().get("arms", {})
	if arms.size() < 2:
		return false
	var other_has_rounds := false
	for id: StringName in arms:
		if id != held.id and not WeaponCatalog.get_def(id).is_melee() and _rounds_of(id) > 0:
			other_has_rounds = true
	if held.is_melee():
		return other_has_rounds
	return true


## Whether it wants to buy what the prompt offers: a weapon or a crane prize it can afford with
## rounds to spare.
func _wants(prompt: Dictionary) -> bool:
	var id: StringName = prompt.get("id", &"")
	return wanted.has(id) and state.points() >= int(prompt.get("price", BIG_PRICE)) + AMMO_MONEY


## Where to shop next: `{}`, or the nearest shop spot worth the walk that a path reaches.
func _plan_shopping(here: Vector3) -> Dictionary:
	var held := _held()
	var best := {}
	var best_apart := INF
	for spot in spots:
		if not _is_goal(spot, held):
			continue
		var apart := _flat(here, spot["position"])
		if apart < best_apart and _reachable(here, spot["position"]):
			best = spot
			best_apart = apart
	return best


func _is_goal(spot: Dictionary, held: WeaponDef) -> bool:
	var kind: StringName = spot["kind"]
	var points := state.points()
	if kind == &"ammo":
		return _low_on_rounds(held) and points >= int(ammo_prices.get(held.id, BIG_PRICE))
	var id: StringName = spot["shop_id"]
	if kind == &"wall":
		var weapon := WeaponCatalog.catalog_id(id)
		if state.me().get("arms", {}).has(weapon):
			# Owned: the wall sells its rounds, but only when that is the gun in hand.
			return (
				held != null
				and held.id == weapon
				and _low_on_rounds(held)
				and points >= int(ammo_prices.get(weapon, BIG_PRICE))
			)
	if kind == &"crane" and state.bought.get(id, 0) >= crane_prizes:
		return false
	return wanted.has(id) and points >= int(prices_of_goods.get(id, BIG_PRICE)) + AMMO_MONEY


func _reachable(here: Vector3, goal: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(map, here, goal, true)
	return not path.is_empty() and _flat(path[path.size() - 1], goal) < REACHABLE


## Where to go: the standing place of the next door it can afford; in a break the nearest breach
## with a board down; else home.
func _goal() -> Vector3:
	# A gun nearly out of rounds comes before a door.
	if not _shopping.is_empty() and _low_on_rounds(_held()):
		return _shopping["position"]
	for door_id in order:
		if state.frame.get("doors", []).has(door_id):
			continue
		if state.points() >= prices.get(door_id, BIG_PRICE) and door_goals.has(door_id):
			return door_goals[door_id]
		break
	if not _shopping.is_empty():
		return _shopping["position"]
	if state.phase() == GameRules.Phase.BREAK:
		var spot := _nearest_broken()
		if spot != Vector3.INF:
			return spot
	return HOME


## The standing place at the nearest breach with a board down, or `Vector3.INF` when all are whole.
func _nearest_broken() -> Vector3:
	var here := state.position()
	var best := Vector3.INF
	var best_d := INF
	var boards: Dictionary = state.frame.get("barricades", {})
	for id: StringName in repair_goals:
		if boards.get(id, whole_boards) >= whole_boards:
			continue
		var d := _flat(here, repair_goals[id])
		if d < best_d:
			best_d = d
			best = repair_goals[id]
	return best


## The nearest zombie that is up and about; with `shootable`, the nearest one in range and in sight.
func _nearest(here: Vector3, shootable: bool) -> Dictionary:
	var best := {}
	var best_d := INF
	for zombie in state.zombies:
		if zombie["mode"] == ZombieBody.Mode.DYING or zombie["mode"] == ZombieBody.Mode.EMERGING:
			continue
		var d := _flat(here, zombie["position"])
		var look: StringName = zombie.get("look", ZombieModels.DEFAULT)
		var in_sight := shootable and d < SHOOT_RANGE and _clear(here, zombie["position"], look)
		if d < best_d and (not shootable or in_sight):
			best_d = d
			best = zombie
	return best


func _clear(here: Vector3, target: Vector3, look: StringName) -> bool:
	if not sight.is_valid():
		return true
	var eye := here + Vector3(0.0, EYE, 0.0)
	var aim := target + Vector3(0.0, _chest(look), 0.0)
	var barrel := here + Basis(Vector3.UP, _yaw) * MUZZLE
	# The camera sees the target past a corner the barrel does not clear: both must be open.
	return float(sight.call(eye, aim)) < 0.0 and float(sight.call(barrel, aim)) < 0.0


func _flee(here: Vector3, from: Vector3) -> Vector3:
	var away := here - from
	away.y = 0.0
	# Bend back toward home so it circles the field instead of running into a corner.
	var home := HOME - here
	home.y = 0.0
	return (away.normalized() + home.normalized() * 0.35).normalized()


func _toward(here: Vector3, goal: Vector3) -> Vector3:
	if _flat(here, goal) < ARRIVED:
		return Vector3.ZERO
	var next := goal
	for point in NavigationServer3D.map_get_path(map, here, goal, true):
		if _flat(here, point) > 0.8:
			next = point
			break
	var flat := next - here
	flat.y = 0.0
	return flat.normalized()


## A bot pressed against something steps sideways for a moment.
func _unstuck(wish: Vector3, here: Vector3, delta: float) -> Vector3:
	if wish == Vector3.ZERO:
		_stuck_for = 0.0
		_last_pos = here
		return wish
	if _flat(here, _last_pos) < 0.01:
		_stuck_for += delta
	else:
		_stuck_for = 0.0
	_last_pos = here
	if _stuck_for > STUCK_AFTER:
		_sidestep = SIDESTEP_FOR
		_stuck_for = 0.0
	if _sidestep > 0.0:
		_sidestep -= delta
		return wish.rotated(Vector3.UP, PI * 0.5)
	return wish


func _aim(command: NightCommand, here: Vector3, target: Vector3, look: StringName) -> void:
	var eye := here + Vector3(0.0, EYE, 0.0)
	var to := target + Vector3(0.0, _chest(look), 0.0) - eye
	command.origin = eye
	command.dir = to.normalized()
	command.muzzle = here + Basis(Vector3.UP, _yaw) * MUZZLE


## Where it aims on a zombie that stands as tall as the look says (a crawler lies low).
static func _chest(look: StringName) -> float:
	return CHEST * ZombieModels.aim_scale(look)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
