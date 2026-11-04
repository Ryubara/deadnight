class_name Autopilot
extends RefCounted
## A bot that plays the night through the same `NightCommand` a person sends. It sees only what a
## client sees (`ClientState`, and the level's navigation map): its own position, the zombies in
## the latest frame, its points and the prompt the server shows for what is in reach. It keeps
## its distance from the nearest zombie, turns to it and shoots, reloads when the magazine runs
## dry, walks to the next door when it can afford it and buys it, buys rounds when the gun in hand
## is nearly out, buys the weapons on the walls and the crane with points to spare, swaps to a gun
## that has rounds, re-cuts one weapon at the bench and drinks the hearty tonic when it can pay, and
## puts boards back when it is standing at one with nothing to shoot. It throws the breaker of an
## area it has bought (`AutopilotSwitches`), and back off when the tank runs low; and it buys a can
## of fuel when the tank is low and it has the points (`AutopilotFuel`). A downed teammate it can
## reach safely is pulled up before anything else (`AutopilotRevive`).

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
## Metres of height within which it counts as being at a goal (a locker on the floor above, a
## metre or two over its head, is not arrived at), and the metres of walk a metre of height counts
## for when it picks the nearest spot (the floors are far apart by the stairs).
const ARRIVE_HEIGHT := 1.5
const RISE_WEIGHT := 8.0
## How hard a flight bends toward home, and toward the shop when the gun in hand is nearly out
## (1.0 would be as hard as the flight itself).
const HOME_PULL := 0.35
const SHOP_PULL := 0.8
## Metres within which a zombie is a threat for the choice of the weapon in hand: an empty gun is
## put away for a blade only with one this near, and with none the gun to buy rounds for is taken
## up.
const THREAT_RANGE := 12.0
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
## ids it wants, cheapest first, and the crane's prizes (shop ids).
var spots: Array[Dictionary] = []
var prices_of_goods: Dictionary = {}
var ammo_prices: Dictionary = {}
var wanted: Array[StringName] = []
var crane_pool: Array[StringName] = []
## What a re-cut and the hearty tonic cost at their machines (the shop's base prices), or 0 when
## the bot does not shop for it. The bot re-cuts one weapon and drinks one tonic a night.
var recut_price: int = 0
var tonic_price: int = 0
## The tonic it drinks (the one that raises health, at `tonic_price`): the other machines are not
## its errand, and a different tonic's price is not the one it saved for.
var tonic_id: StringName = &""
## Where to stand to put boards back across each breach, by id, and how many a whole one holds.
var repair_goals: Dictionary = {}
var whole_boards: int = 1
## The breaker posts and when to use them.
var switches := AutopilotSwitches.new()
## The fuel can spots and when to buy at them.
var fuel := AutopilotFuel.new()
## When to go and pull a downed teammate up.
var revive := AutopilotRevive.new()

var _yaw := 0.0
var _sidestep := 0.0
var _stuck_for := 0.0
var _last_pos := Vector3.ZERO
var _ticks := 0
var _swap_wait := 0
var _shopping: Dictionary = {}
var _had_tonic := false


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
	var patient := revive.choose(state.frame, state.player_id, here, state.zombies)
	if patient != 0:
		return _revive_command(
			command, here, state.frame["players"][patient]["pos"], patient, delta
		)
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
	elif not _buying_door(kind, prompt):
		wish = _toward(here, _destination())
	wish = _unstuck(wish, here, delta)
	if wish != Vector3.ZERO:
		_yaw = atan2(-wish.x, -wish.z)
		command.motion.move = Vector2(0.0, -1.0)
		command.motion.sprint = fleeing
	command.motion.yaw = _yaw
	if not target.is_empty():
		_aim(command, here, target)
		var close := _flat(here, target["position"]) < MELEE_RANGE
		command.fire = not state.me().get("reloading", false) and (close or not melee)
	var threatened := not near.is_empty() and _flat(here, near["position"]) < THREAT_RANGE
	if _swap_wait == 0 and (_wants_swap(held, threatened) or _wants_refill_gun(held, threatened)):
		command.swap = true
		_swap_wait = SWAP_EVERY
	var dry: bool = state.me().get("ammo", 0) <= 0 and state.me().get("reserve", 0) > 0
	command.reload = dry and not state.me().get("reloading", false)
	if kind == &"door":
		command.use = state.points() >= int(prompt.get("price", BIG_PRICE))
	elif kind == &"crane_take":
		command.use = _worth_taking(WeaponCatalog.catalog_id(prompt.get("weapon", &"")))
	elif kind == &"weapon" or kind == &"crane":
		command.use = _wants(prompt) and state.points() >= int(prompt.get("price", BIG_PRICE))
	elif kind == &"ammo":
		command.use = _low_on_rounds(held) and state.points() >= int(prompt.get("price", BIG_PRICE))
	elif kind == &"recut":
		# One weapon a night: the price once grew with each re-cut and kept the bot to one (#909).
		command.use = (
			recut_price > 0
			and _recut_wanted(held)
			and state.points() >= int(prompt.get("price", BIG_PRICE))
		)
	elif kind == &"tonic":
		command.use = (
			tonic_price > 0
			and prompt.get("id", &"") == tonic_id
			and state.points() >= int(prompt.get("price", BIG_PRICE))
		)
	elif kind == &"tonic_owned":
		_had_tonic = _had_tonic or prompt.get("id", &"") == tonic_id
	elif kind == &"repair":
		command.use = target.is_empty()
	elif kind == &"circuit":
		command.use = switches.wants_use(prompt, state.frame)
	elif kind == &"fuel":
		command.use = fuel.wants_use(prompt, state.frame, state.points())
	return command


## Whether it stands at a door it can pay for (it holds still to buy it): at a door it cannot pay
## for it walks on, or a person who is dry and short of a door's price would stand there for good.
func _buying_door(kind: StringName, prompt: Dictionary) -> bool:
	return kind == &"door" and state.points() >= int(prompt.get("price", BIG_PRICE))


## Walks to a downed teammate and holds `use` beside them: no shooting, reloading or swapping (the
## server lets go of a hold for any of them).
func _revive_command(
	command: NightCommand, here: Vector3, there: Vector3, patient: int, delta: float
) -> NightCommand:
	var wish := _unstuck(_toward(here, there), here, delta)
	if wish != Vector3.ZERO:
		_yaw = atan2(-wish.x, -wish.z)
		command.motion.move = Vector2(0.0, -1.0)
	elif _flat(here, there) > 0.01:
		_yaw = atan2(-(there.x - here.x), -(there.z - here.z))
	command.motion.yaw = _yaw
	if revive.in_reach(here, there):
		command.use_held = true
		command.use = state.frame["players"][patient].get("reviver", 0) == 0
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


## The firearm to buy rounds for: the one in hand when it is nearly out; when the hand holds a blade
## (a gun that ran dry was put away for it), the carried firearm that is. Null for none: a gun that
## has rounds in hand needs no trip.
func _refill_gun(held: WeaponDef) -> WeaponDef:
	if held == null:
		return null
	if not held.is_melee():
		return held if _low_on_rounds(held) else null
	var gun: WeaponDef = null
	var fewest := INF
	for id: StringName in state.me().get("arms", {}):
		var def := WeaponCatalog.get_def(id)
		if def == null or def.is_melee() or not ammo_prices.has(id):
			continue
		var rounds := _rounds_of(id)
		if rounds <= def.magazine_size and rounds < fewest:
			gun = def
			fewest = rounds
	return gun


## Whether to take the gun that needs rounds back in hand from a blade: nothing threatens, and it
## can pay for them (rounds are bought for the gun in hand).
func _wants_refill_gun(held: WeaponDef, threatened: bool) -> bool:
	if threatened or held == null or not held.is_melee():
		return false
	var gun := _refill_gun(held)
	return gun != null and state.points() >= int(ammo_prices.get(gun.id, BIG_PRICE))


## Swap away from a melee weapon or an empty gun to one that can shoot; from an empty gun to the
## melee weapon when nothing else can.
func _wants_swap(held: WeaponDef, threatened: bool = true) -> bool:
	if held == null:
		return false
	if not held.is_melee() and _rounds_of(held.id) > 0:
		return false
	var arms: Dictionary = state.me().get("arms", {})
	if arms.size() < 2:
		return false
	var other_has_rounds := false
	var other_is_melee := false
	for id: StringName in arms:
		if id == held.id:
			continue
		if WeaponCatalog.get_def(id).is_melee():
			other_is_melee = true
		elif _rounds_of(id) > 0:
			other_has_rounds = true
	if held.is_melee():
		return other_has_rounds
	# An empty gun goes to a gun that can shoot, or to a blade when something is near, and not to
	# another empty gun (it would swap back and forth for as long as it stays dry).
	return other_has_rounds or (other_is_melee and threatened)


## Whether it wants to buy what the prompt offers: a weapon or a crane prize it can afford with
## rounds to spare.
func _wants(prompt: Dictionary) -> bool:
	var id: StringName = prompt.get("id", &"")
	var kind: StringName = prompt.get("kind", &"")
	if kind == &"weapon" and not _worth_taking(WeaponCatalog.catalog_id(id)):
		return false
	if kind == &"crane" and not _some_prize_worth_taking():
		return false
	return wanted.has(id) and state.points() >= int(prompt.get("price", BIG_PRICE)) + AMMO_MONEY


## Where to shop next: `{}`, or the nearest shop spot worth the walk that a path reaches.
func _plan_shopping(here: Vector3) -> Dictionary:
	var held := _held()
	var best := {}
	var best_apart := INF
	for spot in spots:
		if not _is_goal(spot, held):
			continue
		var apart := _flat(here, spot["position"]) + RISE_WEIGHT * absf(here.y - spot["position"].y)
		if apart < best_apart and _reachable(here, spot["position"]):
			best = spot
			best_apart = apart
	return best


func _is_goal(spot: Dictionary, held: WeaponDef) -> bool:
	var kind: StringName = spot["kind"]
	var points := state.points()
	if kind == &"ammo":
		var gun := _refill_gun(held)
		return gun != null and points >= int(ammo_prices.get(gun.id, BIG_PRICE))
	if kind == MachineOffers.UPGRADE_SPOT:
		return recut_price > 0 and _recut_wanted(held) and points >= recut_price + AMMO_MONEY
	if kind == MachineOffers.PERK_SPOT:
		return (
			tonic_price > 0
			and spot["shop_id"] == tonic_id
			and not _had_tonic
			and points >= tonic_price + AMMO_MONEY
		)
	var id: StringName = spot["shop_id"]
	if kind == &"wall":
		var weapon := WeaponCatalog.catalog_id(id)
		if state.me().get("arms", {}).has(weapon):
			# Owned: the wall sells its rounds, but only when that is the gun in hand.
			return (
				_refill_gun(held) != null
				and _refill_gun(held).id == weapon
				and points >= int(ammo_prices.get(weapon, BIG_PRICE))
			)
	var pointless := kind == &"wall" and not _worth_taking(WeaponCatalog.catalog_id(id))
	if pointless or (kind == &"crane" and not _crane_here_with_prizes(spot)):
		return false
	return wanted.has(id) and points >= int(prices_of_goods.get(id, BIG_PRICE)) + AMMO_MONEY


## Whether the weapon in hand is worth a trip to the re-cut bench: a firearm, not yet re-cut, and
## nothing else re-cut yet (the bot re-cuts one weapon a night).
func _recut_wanted(held: WeaponDef) -> bool:
	# The purchase event reaches the bot before the next frame shows the weapon re-cut, and a second
	# press in between buys the next weapon's re-cut too.
	if held == null or held.is_melee() or state.bought.get(&"upgrade_weapon", 0) > 0:
		return false
	var arms: Dictionary = state.me().get("arms", {})
	for counts: Array in arms.values():
		if counts.size() > 2 and int(counts[2]) > 0:
			return false
	return true


## Whether this crane spot is where the crane stands now and a prize is left that the bot lacks.
func _crane_here_with_prizes(spot: Dictionary) -> bool:
	if spot.get("crane_spot", 0) != state.frame.get("crane", {}).get("spot", 0):
		return false
	return _some_prize_worth_taking()


## Whether the crane's pool holds a prize worth taking: nobody pays for a play whose prize they
## would leave on the glass.
func _some_prize_worth_taking() -> bool:
	for prize in crane_pool:
		if _worth_taking(WeaponCatalog.catalog_id(prize)):
			return true
	return false


## Whether a weapon (a catalogue id) is worth taking: a free hand takes anything; full hands only
## a weapon worth `WeaponWorth.REPLACE_GAIN` times the one in hand, which is the one it replaces
## (without the margin the bot buys in circles). A weapon it already carries is not "taken".
func _worth_taking(weapon_id: StringName) -> bool:
	var arms: Dictionary = state.me().get("arms", {})
	if arms.has(weapon_id):
		return false
	if arms.size() < WeaponCatalog.CARRY_LIMIT:
		return true
	var held := _held()
	return held != null and WeaponWorth.beats(WeaponCatalog.get_def(weapon_id), held)


## Where the crane stands now, or `Vector3.INF` when the lot has no spot for it.
func _crane_position() -> Vector3:
	var at: int = state.frame.get("crane", {}).get("spot", 0)
	for spot in spots:
		if spot["kind"] == &"crane" and spot.get("crane_spot", 0) == at:
			return spot["position"]
	return Vector3.INF


## Where to walk: the glass of its own crane play while that runs, else `_goal`.
func _destination() -> Vector3:
	var crane_at := _crane_position()
	return crane_at if _waiting_on_crane() and crane_at != Vector3.INF else _goal()


## Whether the bot's own crane play is running (the dig, or the prize held out): it waits at the
## glass for it.
func _waiting_on_crane() -> bool:
	var crane: Dictionary = state.frame.get("crane", {})
	return (
		crane.get("buyer", -1) == state.player_id
		and crane.get("stage", 0) in [CraneState.Stage.SPIN, CraneState.Stage.GRAB]
	)


func _reachable(here: Vector3, goal: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(map, here, goal, true, NavLayers.WALK)
	return (
		not path.is_empty()
		and _flat(path[path.size() - 1], goal) < REACHABLE
		and absf(path[path.size() - 1].y - goal.y) < ARRIVE_HEIGHT
	)


## What comes before a door: a fuel can when the tank is low and it can pay for one, then rounds
## for a gun nearly out. `Vector3.INF` when nothing is that urgent.
func _urgent_goal() -> Vector3:
	var cans := fuel.next_goal(state.frame, state.position(), state.points())
	if cans != Vector3.INF:
		return cans
	if not _shopping.is_empty() and _refill_gun(_held()) != null:
		return _shopping["position"]
	return Vector3.INF


## Where to go: what is urgent; the standing place of the next door it can afford; a breaker post it
## wants thrown; in a break the nearest breach with a board down; else home.
func _goal() -> Vector3:
	var urgent := _urgent_goal()
	if urgent != Vector3.INF:
		return urgent
	for door_id in order:
		if state.frame.get("doors", []).has(door_id):
			continue
		if state.points() >= prices.get(door_id, BIG_PRICE) and door_goals.has(door_id):
			return door_goals[door_id]
		break
	if not _shopping.is_empty():
		return _shopping["position"]
	var post := switches.next_goal(
		state.frame, state.position(), state.phase() == GameRules.Phase.BREAK
	)
	if post != Vector3.INF:
		return post
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
		var in_sight := shootable and d < SHOOT_RANGE and _clear(here, zombie)
		if d < best_d and (not shootable or in_sight):
			best_d = d
			best = zombie
	return best


func _clear(here: Vector3, zombie: Dictionary) -> bool:
	if not sight.is_valid():
		return true
	var eye := here + Vector3(0.0, EYE, 0.0)
	var aim := _body_of(zombie)
	# It turns to the target to shoot, so the barrel is where it will be then.
	var to := aim - eye
	var barrel := here + Basis(Vector3.UP, atan2(-to.x, -to.z)) * MUZZLE
	# The camera sees the target past a corner the barrel does not clear: both must be open.
	return float(sight.call(eye, aim)) < 0.0 and float(sight.call(barrel, aim)) < 0.0


func _flee(here: Vector3, from: Vector3) -> Vector3:
	var away := here - from
	away.y = 0.0
	# Bend back toward home so it circles the field instead of running into a corner; with a gun
	# nearly out, bend toward the shop it has planned instead, so the chase leads to rounds (#998).
	var bend := HOME - here
	var pull := HOME_PULL
	if not _shopping.is_empty() and _refill_gun(_held()) != null:
		bend = _shopping["position"] - here
		pull = SHOP_PULL
	bend.y = 0.0
	return (away.normalized() + bend.normalized() * pull).normalized()


func _toward(here: Vector3, goal: Vector3) -> Vector3:
	if _flat(here, goal) < ARRIVED and absf(here.y - goal.y) < ARRIVE_HEIGHT:
		return Vector3.ZERO
	var next := goal
	for point in NavigationServer3D.map_get_path(map, here, goal, true, NavLayers.WALK):
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


func _aim(command: NightCommand, here: Vector3, zombie: Dictionary) -> void:
	var eye := here + Vector3(0.0, EYE, 0.0)
	var to := _body_of(zombie) - eye
	command.origin = eye
	command.aim_along(to)
	command.muzzle = here + Basis(Vector3.UP, _yaw) * MUZZLE
	# The view turns to the target and the body goes on walking its way, as a person does with the
	# camera on a zombie: the server refuses a shot that does not follow the view
	# (`NightServer.aims_with_view`).
	if command.motion.move != Vector2.ZERO:
		var apart := command.motion.yaw - _yaw
		command.motion.move = Vector2(sin(apart), -cos(apart))


## Where it aims on a zombie: the middle of its body as its look and pose have it (a crawler lies
## low and its body is ahead of its feet).
static func _body_of(zombie: Dictionary) -> Vector3:
	var look: StringName = zombie.get("look", ZombieModels.DEFAULT)
	var mode: int = zombie.get("mode", ZombieBody.Mode.CHASE)
	var offset := ZombiePose.aim_offset(look, mode, float(zombie.get("yaw", 0.0)))
	return (zombie["position"] as Vector3) + offset


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
