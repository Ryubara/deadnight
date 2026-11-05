extends Node
## Runs a proposed extraction chain (`ExtractionChains`) in a real night and says what it took
## (#1056, `docs/design/extraction.md`). A measuring tool: no step exists in the game, so this
## conducts them: it walks real bodies to each place, holds real bots there, keeps their trigger up
## while they work, buys real fuel, puts real boards back and adds the dead a loud step calls to the
## round's own plan. Bots go by the order a person would give them (`HOLD` at a place), and fight
## with their usual brains while nothing is asked of them.
##
##   godot --headless --path game res://tests/captures/extraction_probe.tscn -- \
##     --map=drive_in --chain=v2 --mode=night --bots=4 --count=2 --seed=1
##
## Modes:
## - `night`: bots in a real night, from round 1, buying the doors with what they earn.
## - `floor`: the least it can take: every door sold, no dead at all, `--bots` real player bodies
##   sprinting (`HumanWalker`) and sharing the steps. Walking and work, nothing else.
## - `stall`: a real night until round `--stall-from`, then no more of the round's dead: the best a
##   team can do by keeping one dead alive. Only what the steps call can come.
## - `base`: a night with no chain, for the kills and the time by round.
##
## Other arguments: `--quota=N` (kills; 0 is no quota), `--profile=rookie|regular|veteran|mixed`,
## `--tough=X` (every player's health as a multiple of the shipped: to see a chain's timing past
## the round a bot's aim and feet give out, never a survival number), `--minutes=M` (game minutes
## at most, 45), `--wall=S` (seconds of real time at most: a cut-off night still reports),
## `--out=file` (the report as one JSON document), `--trace` (a line every 15 game
## seconds). Prints `EXTRACTION {json}` at the end.

const STEP := SeatedNight.STEP
const SCENES := {
	&"drive_in": "res://world/drive_in_greybox.tscn",
	&"small_indoor": "res://world/smallmap/smallmap_greybox.tscn",
}
## Doors each chain's map must have open, cheapest first: bots that know the job buy these early.
const DOORS_FIRST := {
	&"drive_in":
	[
		&"weapon_shotgun",
		&"door_concession",
		&"door_yard",
		&"weapon_rifle",
		&"door_booth",
		&"door_back_lot",
		&"door_road",
		&"upgrade_weapon",
		&"tonic_hearty",
		&"crane_play",
		&"tonic_quick_load",
		&"tonic_swift_rescue",
	],
	&"small_indoor": [],
}
## Ticks between the physics frames the engine is given (a bought door needs them).
const FRAME_EVERY := 30
## A worker this near a dead one stops work and fights (a carrier goes on until a blow lands).
const ENGAGED := 3.5
## How near a dead must be to count as pressure on a worker.
const PRESSED := 10.0
## How near a place a worker must stand, on the flat and in height.
const REACH := 2.2
const REACH_HEIGHT := 1.6
## Seconds between the cans a worker buys.
const CAN_EVERY := 3.0
## Boards a window must hold to count as sealed, when the step does not say.
const BOARDS_ALL := 5
## The id of the one the rules are told is still up in a stall.
const KEPT_ALIVE := 999999
## Seconds a walker pushes against a corner before it steps round it.
const STALLED := 0.4
## The landing at the top of the lot's booth ramp.
const RAMP_TOP := Vector3(-4.8, 3.8, 31.2)
## The window the back rooms' charges blow out, the way onto the terrace.
const GATE_WINDOW := &"upper_a2"

var _args := {}
var _map: StringName = &"drive_in"
var _mode := "night"
var _night: SeatedNight
var _rules: GameRules
var _stages: Array = []
var _stage_index := -1
var _seats: Array[Dictionary] = []
var _now := 0.0
var _quota := 0
var _tally := 0
var _kills := 0
var _kills_all := 0
var _downs := 0
var _revives := 0
var _hurts := 0
var _most_alive := 0
var _stalling := false
var _won := false
var _round_ends: Dictionary = {}
var _kills_by_round: Dictionary = {}
var _doors: Dictionary = {}
var _no_fire: Dictionary = {}
var _no_run: Dictionary = {}
var _press_use: Dictionary = {}
var _knocked: Dictionary = {}
var _chain_started := -1.0
var _cut_off := false


func _ready() -> void:
	_args = _parse_args()
	_map = StringName(_args.get("map", "drive_in"))
	_mode = String(_args.get("mode", "night"))
	_quota = int(_args.get("quota", 0))
	var seed_value := int(_args.get("seed", 1))
	var count := int(_args.get("bots", 1))
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.health.max_health *= float(_args.get("tough", 1.0))
	_night = await SeatedNight.start(
		self, count, tuning, seed_value, _mode != "floor", load(SCENES[_map])
	)
	_rules = _night.server.rules
	_rules.settings.count_multiplier = float(_args.get("count", 1.0))
	_night.on_event = _on_event
	_night.on_action = _on_action
	if _mode == "floor":
		await _seat_walkers(count)
		_wear_for_the_floor()
	else:
		_seat_bots(count, seed_value)
	_stages = ExtractionChains.stages(_map, StringName(_args.get("chain", "v2")))
	var map_rid := _night.world.map()
	for stage: Dictionary in _stages:
		for step: Dictionary in stage["steps"]:
			step.merge(_blank_step())
			# A place is on the ground a body walks: a body cannot stand in a parked car.
			for key in ["at", "from", "to"]:
				if step.has(key):
					step[key] = NavigationServer3D.map_get_closest_point(map_rid, step[key])
	_night.start_round()
	await _run(int(float(_args.get("minutes", 45)) * 60.0 * 60.0))
	_finish()


func _blank_step() -> Dictionary:
	return {
		"state": &"waiting",
		"progress": 0.0,
		"opened": -1.0,
		"started": -1.0,
		"done": -1.0,
		"round_opened": 0,
		"round_done": 0,
		"work_s": 0.0,
		"walk_s": 0.0,
		"fight_s": 0.0,
		"pressed_s": 0.0,
		"downs": 0,
		"hurts": 0,
		"resets": 0,
		"people": {},
		"lifted": false,
		"carrier": 0,
		"place": Vector3.INF,
		"surged": false,
		"seconds_left": 0.0,
	}


func _seat_bots(count: int, seed_value: int) -> void:
	var kind := String(_args.get("profile", "regular"))
	for i in count:
		var profile := BotProfile.regular()
		match kind:
			"rookie":
				profile = BotProfile.rookie()
			"veteran":
				profile = BotProfile.veteran()
			"mixed":
				profile = [BotProfile.regular(), BotProfile.veteran(), BotProfile.rookie()][i % 3]
		var bot := _night.seat(i + 1, profile, 1000 + 100 * seed_value + i)
		_seats.append({"id": i + 1, "bot": bot, "walker": null, "job": {}, "going": Vector3.INF})
	var first: Array = DOORS_FIRST.get(_map, [])
	var shop: BotShop = _night.level.shop
	if not first.is_empty() and shop != null:
		shop.shopping.assign(first)


func _seat_walkers(count: int) -> void:
	for item in _rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR and not _rules.is_door_open(item.id):
			_night.open_door(item.id)
	await _night.settle_doors()
	for i in count:
		_rules.apply(RulesAction.grant_points(i + 1, 100000))
		var walker := _night.human(i + 1)
		walker.sprint = true
		_seats.append({"id": i + 1, "bot": null, "walker": walker, "job": {}, "going": Vector3.INF})


## An empty night has a full tank and whole windows: the floor starts from what a team has by the
## time the chain opens, half a tank and every board down.
func _wear_for_the_floor() -> void:
	if _rules.generator != null:
		_rules.generator.fuel = _rules.tuning.fuel.capacity * 0.5
	for id: StringName in _night.world.barricade_ids():
		for _board in _rules.tuning.barricades.boards:
			_rules.barricades.tear(id)


func _run(limit: int) -> void:
	var ticks := 0
	var wall_end := Time.get_ticks_msec() + int(float(_args.get("wall", 3600)) * 1000.0)
	while ticks < limit and _rules.phase != GameRules.Phase.OVER and not _won:
		if ticks % 600 == 0 and Time.get_ticks_msec() > wall_end:
			_cut_off = true
			break
		_night.tick()
		ticks += 1
		_now = float(ticks) * STEP
		_most_alive = maxi(_most_alive, _night.server.sim.standing_count())
		if _mode == "floor":
			_rules._plan.clear()
		elif _mode == "stall" and _rules.round_number >= int(_args.get("stall-from", 8)):
			if not _stalling and _rules.phase == GameRules.Phase.ACTIVE:
				# The crawler a team keeps alive: the round never ends, and no more of it comes.
				_stalling = true
				_rules._plan.clear()
				_rules._zombies[KEPT_ALIVE] = ZombieState.new(KEPT_ALIVE, 1.0, &"walker", 1.0)
		if _mode != "base":
			_conduct()
		if _args.has("trace") and ticks % (15 * 60) == 0:
			_trace()
		if ticks % FRAME_EVERY == 0:
			await get_tree().physics_frame


## The stage in force, its steps, and who does what.
func _conduct() -> void:
	if _stages.is_empty():
		return
	_walkers_on()
	if _stage_index < 0 or _stage_done(_stages[_stage_index]):
		if _stage_index + 1 >= _stages.size():
			_won = true
			return
		if _quota > 0 and _tally < int(ceil(_stages[_stage_index + 1]["tier"] * _quota)):
			_release_all()
			return
		_stage_index += 1
		if _chain_started < 0.0:
			_chain_started = _now
		for step: Dictionary in _stages[_stage_index]["steps"]:
			step["state"] = &"open"
	var stage: Dictionary = _stages[_stage_index]
	for step: Dictionary in stage["steps"]:
		if step["state"] == &"done":
			continue
		if step["opened"] < 0.0:
			# A step behind a shut door is not begun: a window or a tank is whole before it opens.
			if not _door_ready(step):
				continue
			step["opened"] = _now
			step["round_opened"] = _rules.round_number
		_step(step)
	_assign(stage)


func _stage_done(stage: Dictionary) -> bool:
	for step: Dictionary in stage["steps"]:
		if step["state"] != &"done":
			return false
	return true


func _door_ready(step: Dictionary) -> bool:
	var door: StringName = step.get("door", &"")
	if door != &"" and not _rules.is_door_open(door):
		return false
	for other: StringName in step.get("doors", []):
		if not _rules.is_door_open(other):
			return false
	return true


## A walker that came up the ramp goes on to the place it was sent to.
func _walkers_on() -> void:
	for seat in _seats:
		var going: Vector3 = seat["going"]
		var walker: HumanWalker = seat["walker"]
		if walker == null or going == Vector3.INF:
			continue
		if seat.get("round_for", 0.0) > 0.0:
			seat["round_for"] -= STEP
			if seat["round_for"] <= 0.0:
				walker.goto(_way_to(seat, going))
		elif walker.stalled > STALLED:
			# Pushed against a corner the path cuts: a person steps back and round it.
			var side := Vector3(-walker.position().z + going.z, 0.0, walker.position().x - going.x)
			var out := side.normalized() * (1.5 if int(_now) % 2 == 0 else -1.5)
			walker.goto(walker.position() + out + Vector3(0.0, 0.0, 0.0))
			seat["round_for"] = 0.5
		elif _pos(seat).y >= 3.6:
			walker.goto(going)


## A free live seat for each step that needs one, nearest first; a seat with no job fights.
func _assign(stage: Dictionary) -> void:
	for step: Dictionary in stage["steps"]:
		if step["state"] == &"done" or step["opened"] < 0.0:
			continue
		var all_hands: bool = step["kind"] == ExtractionChains.STAND
		var windows_left: int = (
			_unsealed(step).size() if step["kind"] == ExtractionChains.SEAL else 0
		)
		var wanted := _seats.size() if all_hands else maxi(1, windows_left)
		for seat in _seats:
			if seat["job"] == step:
				wanted -= 1
		while wanted > 0:
			var seat := _free_seat(_place_of(step))
			if seat.is_empty():
				break
			seat["job"] = step
			wanted -= 1


func _place_of(step: Dictionary) -> Vector3:
	match step["kind"]:
		ExtractionChains.CARRY:
			if step["carrier"] != 0:
				return step["to"]
			return step["place"] if step["place"] != Vector3.INF else step["from"]
		ExtractionChains.SEAL:
			var left := _unsealed(step)
			if left.is_empty():
				return _night.world.repair_spot(step["windows"][0])
			return _night.world.repair_spot(left[0])
		ExtractionChains.LOAD:
			return Vector3.INF
	return step["at"]


func _free_seat(near: Vector3) -> Dictionary:
	var best := {}
	var best_apart := INF
	for seat in _seats:
		if not seat["job"].is_empty() or _down(seat["id"]):
			continue
		var apart := 0.0 if near == Vector3.INF else _pos(seat).distance_to(near)
		if apart < best_apart:
			best_apart = apart
			best = seat
	return best


func _step(step: Dictionary) -> void:
	var workers: Array[Dictionary] = []
	for seat in _seats:
		if seat["job"] == step:
			if _down(seat["id"]):
				_drop_job(seat)
			else:
				workers.append(seat)
	match step["kind"]:
		ExtractionChains.WORK, ExtractionChains.BREAKER:
			_step_work(step, workers)
		ExtractionChains.CARRY:
			_step_carry(step, workers)
		ExtractionChains.STAND:
			_step_stand(step, workers)
		ExtractionChains.TANK:
			_step_tank(step, workers)
		ExtractionChains.LOAD:
			_step_load(step, workers)
		ExtractionChains.SEAL:
			_step_seal(step, workers)


func _step_work(step: Dictionary, workers: Array[Dictionary]) -> void:
	for seat in workers:
		_send_to(seat, step["at"])
		var at_it := _at(seat, step["at"])
		var nearest := _nearest_dead(seat)
		_note(step, seat, at_it, nearest)
		if not at_it:
			_free_hands(seat)
			continue
		_begin(step)
		if nearest < ENGAGED:
			_free_hands(seat)
			step["fight_s"] += STEP
			continue
		_no_fire[seat["id"]] = true
		step["progress"] += STEP
		step["work_s"] += STEP
		if step["progress"] >= step["seconds"]:
			if step["kind"] == ExtractionChains.BREAKER:
				_rules.apply(RulesAction.set_circuit(step["circuit"], true))
			_complete(step)
			return


func _step_carry(step: Dictionary, workers: Array[Dictionary]) -> void:
	if step["place"] == Vector3.INF:
		step["place"] = step["from"]
	for seat in workers:
		var nearest := _nearest_dead(seat)
		var id: int = seat["id"]
		if step["carrier"] == id:
			step["place"] = _pos(seat)
			if _knocked.has(id):
				# A blow knocks the load out of the hands, where it is. Near is not enough: by round
				# 12 a dead is always near, and no small team got a lamp 60 m.
				_knocked.erase(id)
				step["carrier"] = 0
				step["progress"] = 0.0
				step["lifted"] = true
				_free_hands(seat)
				_note(step, seat, false, nearest)
				continue
			_no_fire[id] = true
			_no_run[id] = true
			_send_to(seat, step["to"])
			var there := _at(seat, step["to"])
			_note(step, seat, there, nearest)
			if there:
				step["progress"] += STEP
				step["work_s"] += STEP
				if step["progress"] >= step["lift"]:
					_complete(step)
					return
			continue
		_send_to(seat, step["place"])
		var at_it := _at(seat, step["place"])
		_note(step, seat, at_it, nearest)
		if not at_it:
			_free_hands(seat)
			continue
		_begin(step)
		if nearest < ENGAGED:
			_free_hands(seat)
			step["fight_s"] += STEP
			continue
		_no_fire[id] = true
		step["progress"] += STEP
		step["work_s"] += STEP
		var needed: float = 1.0 if step["lifted"] else step["lift"]
		if step["progress"] >= needed:
			step["carrier"] = id
			step["progress"] = 0.0
			step["people"][id] = true
			_knocked.erase(id)


func _step_stand(step: Dictionary, workers: Array[Dictionary]) -> void:
	var inside := 0
	var gate: Vector3 = step.get("gate", Vector3.INF)
	if gate != Vector3.INF and not step.get("blown", false):
		step["blown"] = true
		for _board in _rules.tuning.barricades.boards:
			_rules.barricades.tear(GATE_WINDOW)
	for seat in workers:
		var beyond: bool = _flat(_pos(seat), step["at"]) <= step["radius"]
		if gate != Vector3.INF and not beyond:
			_send_to(seat, gate)
			if _at(seat, gate):
				# The blown wall is a metre of floor to cross; the mesh a bot walks has no way
				# through it, so the crossing is a step on the spot.
				_night.server.body_of(seat["id"]).teleport(step["at"])
				seat["going"] = Vector3.INF
			_note(step, seat, false, _nearest_dead(seat))
			continue
		_send_to(seat, step["at"])
		var nearest := _nearest_dead(seat)
		var at_it: bool = _flat(_pos(seat), step["at"]) <= step["radius"]
		_note(step, seat, at_it, nearest)
		if at_it:
			inside += 1
	if inside > 0:
		_begin(step)
		step["progress"] += STEP
		step["work_s"] += STEP
		if step["progress"] >= step["seconds"]:
			step["stood"] = inside
			_complete(step)


func _step_tank(step: Dictionary, workers: Array[Dictionary]) -> void:
	var tank: GeneratorState = _rules.generator
	if tank.fraction() >= step["need"] - 0.001:
		_begin(step)
		_complete(step)
		return
	for seat in workers:
		_send_to(seat, step["at"])
		var at_it := _at(seat, step["at"])
		var nearest := _nearest_dead(seat)
		_note(step, seat, at_it, nearest)
		if not at_it or nearest < ENGAGED:
			_free_hands(seat)
			continue
		_begin(step)
		step["seconds_left"] -= STEP
		step["work_s"] += STEP
		if step["seconds_left"] <= 0.0:
			step["seconds_left"] = CAN_EVERY
			_rules.apply(RulesAction.buy(seat["id"], &"fuel_can"))


func _step_load(step: Dictionary, _workers: Array[Dictionary]) -> void:
	_begin(step)
	var tank: GeneratorState = _rules.generator
	var on := tank.is_powered()
	for circuit: StringName in [&"screen_lot", &"concession", &"booth", &"back_lot"]:
		on = on and tank.is_lit(circuit)
	if not on:
		if step["progress"] > 0.0:
			step["resets"] += 1
		step["progress"] = 0.0
		return
	step["progress"] += STEP
	if step["progress"] >= step["seconds"]:
		_complete(step)


func _step_seal(step: Dictionary, workers: Array[Dictionary]) -> void:
	var left := _unsealed(step)
	if left.is_empty():
		_begin(step)
		step["progress"] += STEP
		if step["progress"] >= step["seconds"]:
			_complete(step)
		return
	if step["progress"] > 0.0:
		step["resets"] += 1
	step["progress"] = 0.0
	for i in workers.size():
		var seat := workers[i]
		var window: StringName = left[mini(i, left.size() - 1)]
		var spot := _night.world.repair_spot(window)
		_send_to(seat, spot)
		var at_it := _at(seat, spot)
		var nearest := _nearest_dead(seat)
		_note(step, seat, at_it, nearest)
		if not at_it:
			_free_hands(seat)
			continue
		_begin(step)
		if nearest < ENGAGED:
			# Clear the window, then mend: nobody does both at once.
			_free_hands(seat)
			step["fight_s"] += STEP
			continue
		_no_fire[seat["id"]] = true
		_press_use[seat["id"]] = true
		step["work_s"] += STEP
		if _mode == "floor":
			step["seconds_left"] -= STEP
			if step["seconds_left"] <= 0.0:
				step["seconds_left"] = NightTuning.shipped().repair_interval
				_rules.apply(RulesAction.repair(seat["id"], window))


func _unsealed(step: Dictionary) -> Array[StringName]:
	var left: Array[StringName] = []
	for window: StringName in step["windows"]:
		if _rules.barricades.boards_of(window) < int(step.get("boards", BOARDS_ALL)):
			left.append(window)
	return left


func _begin(step: Dictionary) -> void:
	if step["started"] >= 0.0:
		return
	step["started"] = _now
	if float(step.get("surge", 0.0)) > 0.0:
		_surge(float(step["surge"]))


## The dead a loud step calls: a share of this round's own count, added to the round's plan; in a
## break it ends the break, as the noise would.
func _surge(share: float) -> void:
	if _mode == "floor":
		return
	var players := maxi(_rules.players.size(), 1)
	var normal := _rules.settings.scaled_count(
		_rules.tuning.rounds.zombies_for_round(_rules.round_number, players)
	)
	var count := maxi(1, roundi(normal * share))
	if _rules.phase != GameRules.Phase.ACTIVE:
		_night.host.hear(_rules.apply(RulesAction.skip_break()))
	_rules._plan.append_array(
		_rules.tuning.roster.plan_for_round(_rules.round_number, count, _rules._spawn_rng)
	)


func _complete(step: Dictionary) -> void:
	step["state"] = &"done"
	step["done"] = _now
	step["round_done"] = _rules.round_number
	for seat in _seats:
		if seat["job"] == step:
			_drop_job(seat)


func _drop_job(seat: Dictionary) -> void:
	seat["job"] = {}
	_free_hands(seat)
	_send_to(seat, Vector3.INF)


func _release_all() -> void:
	for seat in _seats:
		if not seat["job"].is_empty():
			_drop_job(seat)


func _free_hands(seat: Dictionary) -> void:
	_no_fire.erase(seat["id"])
	_no_run.erase(seat["id"])
	_press_use.erase(seat["id"])


## Sends a seat to a place, or back to its own business with `Vector3.INF`.
func _send_to(seat: Dictionary, at: Vector3) -> void:
	if seat["going"] == at:
		return
	seat["going"] = at
	if seat["walker"] != null:
		if at == Vector3.INF:
			seat["walker"].stop()
		else:
			seat["walker"].goto(_way_to(seat, at))
		return
	var orders: BotOrders = _night.server.bot_orders
	var id: int = seat["id"]
	if at == Vector3.INF:
		orders.issue(BotOrders.ROAM, id, _pos(seat), id)
	else:
		orders._wait.erase(id)
		orders.issue(BotOrders.HOLD, id, at, id)


## Where a walker heads for `at`: its look-ahead cuts the corner at the top of the lot's booth ramp
## into the upper floor's edge, so it goes by the landing. (A bot's legs get round it.)
func _way_to(seat: Dictionary, at: Vector3) -> Vector3:
	if _map == &"drive_in" and at.y > 2.0 and _pos(seat).y < 3.6:
		return RAMP_TOP
	return at


func _note(step: Dictionary, seat: Dictionary, at_it: bool, nearest: float) -> void:
	step["people"][seat["id"]] = true
	if not at_it:
		step["walk_s"] += STEP
	if nearest < PRESSED:
		step["pressed_s"] += STEP


func _at(seat: Dictionary, place: Vector3) -> bool:
	var here := _pos(seat)
	return _flat(here, place) <= REACH and absf(here.y - place.y) <= REACH_HEIGHT


func _pos(seat: Dictionary) -> Vector3:
	return _night.server.body_of(seat["id"]).global_position


func _down(id: int) -> bool:
	var state: PlayerState = _rules.players.get(id)
	return state == null or state.downed


## Metres to the nearest dead on this floor; `INF` for none.
func _nearest_dead(seat: Dictionary) -> float:
	var here := _pos(seat)
	var best := INF
	for zombie: ZombieBody in _night.server.sim.zombies.values():
		if zombie.mode == ZombieBody.Mode.DYING or zombie.mode == ZombieBody.Mode.EMERGING:
			continue
		if absf(zombie.position.y - here.y) > 1.7:
			continue
		best = minf(best, _flat(zombie.position, here))
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _on_action(action: Dictionary, id: int) -> void:
	if _press_use.has(id):
		action["use"] = true
		action["use_held"] = true
	if _no_fire.has(id):
		action["fire"] = false
		if action.has("motion"):
			action["motion"]["fire"] = false
			action["motion"]["aim"] = false
	if _no_run.has(id) and action.has("motion"):
		action["motion"]["sprint"] = false


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"zombie_removed":
			_kills_all += 1
			if int(event.get("killer_id", 0)) > 0:
				_kills += 1
				_kills_by_round[_rules.round_number] = (
					int(_kills_by_round.get(_rules.round_number, 0)) + 1
				)
				var cap := _tally_cap()
				if _tally < cap:
					_tally += 1
		&"player_downed":
			_downs += 1
			for step in _active_steps():
				step["downs"] += 1
		&"player_hurt":
			_hurts += 1
			_knocked[int(event.get("player_id", 0))] = true
			for step in _active_steps():
				step["hurts"] += 1
		&"player_revived":
			_revives += 1
		&"round_ended":
			_round_ends[int(event.get("round", _rules.round_number))] = _now
		&"door_opened":
			_doors[String(event.get("door_id", ""))] = {"round": _rules.round_number, "t": _now}


## The kills the tally may hold now: the next stage's tier; the tally never runs ahead of the steps.
func _tally_cap() -> int:
	if _quota <= 0:
		return 0
	var next := mini(_stage_index + 1, _stages.size() - 1)
	return int(ceil(float(_stages[next]["tier"]) * _quota)) if next >= 0 else 0


func _active_steps() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if _stage_index < 0:
		return found
	for step: Dictionary in _stages[_stage_index]["steps"]:
		if step["state"] != &"done" and step["opened"] >= 0.0:
			found.append(step)
	return found


func _trace() -> void:
	var stage := "-" if _stage_index < 0 else String(_stages[_stage_index]["id"])
	var rows := PackedStringArray()
	for seat in _seats:
		var job: Dictionary = seat["job"]
		(
			rows
			. append(
				(
					"%d:%s(%.1f,%.1f,%.1f)%s"
					% [
						seat["id"],
						"-" if job.is_empty() else String(job["id"]),
						_pos(seat).x,
						_pos(seat).y,
						_pos(seat).z,
						"D" if _down(seat["id"]) else "",
					]
				)
			)
		)
	print(
		(
			"t=%.0f round %d stage %s tally %d/%d kills %d alive %d pts %d tank %.0f %s"
			% [
				_now,
				_rules.round_number,
				stage,
				_tally,
				_quota,
				_kills,
				_night.server.sim.standing_count(),
				_rules.points_of(1),
				_rules.generator.fuel if _rules.generator != null else 0.0,
				" ".join(rows),
			]
		)
	)


func _finish() -> void:
	var report := {
		"map": _map,
		"chain": _args.get("chain", "v2"),
		"mode": _mode,
		"bots": _seats.size(),
		"count": float(_args.get("count", 1.0)),
		"seed": int(_args.get("seed", 1)),
		"profile": _args.get("profile", "regular"),
		"won": _won,
		"cut_off": _cut_off,
		"seconds": _now,
		"round": _rules.round_number,
		"kills": _kills,
		"quota": _quota,
		"tally": _tally,
		"downs": _downs,
		"revives": _revives,
		"hurts": _hurts,
		"most_alive": _most_alive,
		"stage_reached": _stage_index,
		"chain_started": _chain_started,
		"kills_by_round": _kills_by_round,
		"round_ends": _round_ends,
		"doors": _doors,
		"steps": _step_rows(),
	}
	print("EXTRACTION ", JSON.stringify(report))
	var out := String(_args.get("out", ""))
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report))
			file.close()
	for _i in 600:
		if not _night.world.navigation.is_busy():
			break
		await get_tree().process_frame
	_night.dispose()
	await get_tree().process_frame
	get_tree().quit()


func _step_rows() -> Array:
	var rows := []
	for stage: Dictionary in _stages:
		for step: Dictionary in stage["steps"]:
			(
				rows
				. append(
					{
						"stage": stage["id"],
						"id": step["id"],
						"kind": step["kind"],
						"opened": snappedf(step["opened"], 0.1),
						"started": snappedf(step["started"], 0.1),
						"done": snappedf(step["done"], 0.1),
						"round_opened": step["round_opened"],
						"round_done": step["round_done"],
						"walk_s": snappedf(step["walk_s"], 0.1),
						"work_s": snappedf(step["work_s"], 0.1),
						"fight_s": snappedf(step["fight_s"], 0.1),
						"pressed_s": snappedf(step["pressed_s"], 0.1),
						"downs": step["downs"],
						"hurts": step["hurts"],
						"resets": step["resets"],
						"people": step["people"].size(),
						"stood": step.get("stood", 0),
					}
				)
			)
	return rows


func _parse_args() -> Dictionary:
	var found := {}
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
