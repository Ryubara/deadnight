class_name Autopilot
extends RefCounted
## A bot that plays the night through the same `NightCommand` a person sends. It sees only what a
## client sees (`ClientState`, and the level's navigation map): its own position, the zombies in
## the latest frame, its points and the prompt the server shows for what is in reach. It keeps
## its distance from the nearest zombie, turns to it and shoots, reloads when the magazine runs
## dry, walks to the next door when it can afford it and buys it, and puts boards back when it is
## standing at one with nothing to shoot.

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

var state: ClientState
var map: RID
## `Callable(from, to) -> float`: distance to the first wall on the way, or -1 when clear.
var sight: Callable = Callable()
## Metres a door's price needs, by id; where to stand to buy it; the order to buy in.
var prices: Dictionary = {}
var door_goals: Dictionary = {}
var order: Array[StringName] = []

var _yaw := 0.0
var _sidestep := 0.0
var _stuck_for := 0.0
var _last_pos := Vector3.ZERO


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
	var fleeing := not near.is_empty() and _flat(here, near["position"]) < KEEP_AWAY
	if fleeing:
		wish = _flee(here, near["position"])
	elif kind != &"door":
		wish = _toward(here, _goal())
	wish = _unstuck(wish, here, delta)
	if wish != Vector3.ZERO:
		_yaw = atan2(-wish.x, -wish.z)
		command.motion.move = Vector2(0.0, -1.0)
		command.motion.sprint = fleeing
	command.motion.yaw = _yaw
	if not target.is_empty():
		_aim(command, here, target["position"])
		command.fire = not state.me().get("reloading", false)
	var dry: bool = state.me().get("ammo", 0) <= 0 and state.me().get("reserve", 0) > 0
	command.reload = dry and not state.me().get("reloading", false)
	if kind == &"door":
		command.use = state.points() >= int(prompt.get("price", BIG_PRICE))
	elif kind == &"repair":
		command.use = target.is_empty()
	return command


## Where to go: the standing place of the next door it can afford, else home.
func _goal() -> Vector3:
	for door_id in order:
		if state.frame.get("doors", []).has(door_id):
			continue
		if state.points() >= prices.get(door_id, BIG_PRICE) and door_goals.has(door_id):
			return door_goals[door_id]
		break
	return HOME


## The nearest zombie that is up and about; with `shootable`, the nearest one in range and in sight.
func _nearest(here: Vector3, shootable: bool) -> Dictionary:
	var best := {}
	var best_d := INF
	for zombie in state.zombies:
		if zombie["mode"] == ZombieBody.Mode.DYING or zombie["mode"] == ZombieBody.Mode.EMERGING:
			continue
		var d := _flat(here, zombie["position"])
		if d < best_d and (not shootable or (d < SHOOT_RANGE and _clear(here, zombie["position"]))):
			best_d = d
			best = zombie
	return best


func _clear(here: Vector3, target: Vector3) -> bool:
	if not sight.is_valid():
		return true
	var eye := here + Vector3(0.0, EYE, 0.0)
	var aim := target + Vector3(0.0, CHEST, 0.0)
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


func _aim(command: NightCommand, here: Vector3, target: Vector3) -> void:
	var eye := here + Vector3(0.0, EYE, 0.0)
	var to := target + Vector3(0.0, CHEST, 0.0) - eye
	command.origin = eye
	command.dir = to.normalized()
	command.muzzle = here + Basis(Vector3.UP, _yaw) * MUZZLE


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
