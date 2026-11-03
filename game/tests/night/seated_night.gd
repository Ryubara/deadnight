class_name SeatedNight
extends RefCounted
## A night with several players seated, for the suites that run bots: the lot and the server with no
## client of its own (as `NightHost` builds them), `count` players joined with ids 1 to `count`,
## and a `BotHost` that hears every step and sends every command through `NightServer.apply` as a
## socket would (the action is turned into bytes and back, so only plain data gets through).
## Ticks are run by hand: no await, no clock.

const STEP := Night.STEP

var world: NightWorld
var server: NightServer
var host := BotHost.new()
## Seats played by a stand-in for a person (`HumanWalker`): the bots take them for humans.
var walkers: Array[HumanWalker] = []
var level: BotLevel
## Every action a bot sent: `{tick, player_id, action}`, when `recording`.
var recorded: Array[Dictionary] = []
var recording := false
## The newest frame, and every event of the last step.
var frame: Dictionary = {}
var last_events: Array[Dictionary] = []
## Called with every event of every step.
var on_event := Callable()
## When on, every zombie is put once, as soon as it is up, on the walkable open ground 10 to 16 m in
## front of one of the players (in id order), and walks from there in a straight line: a short run
## has a fight in it without waiting for the dead to walk the lot, and no route round an obstacle
## to choose between. Done the same way in `replay`.
var stage_the_dead := false
## When on, every command the bots send leaves with the trigger up: the bots move, look and dodge
## as they would but never shoot (a test of the legs alone, on a zombie a hit would stagger).
var hold_fire := false
## When on, the bots seated from now on hold where they stand unless an errand or a revive moves
## them (`BotProfile.follows` off): with no order given a bot roams, and a test about the fight, or
## about one errand, wants a bot that stays where it was put.
var stand_still := false
## When above 0, the state hash after every this many steps is kept in `hashes`.
var hash_every := 0
var hashes: Array[int] = []

## What the server answered to the actions the bots and the people sent (a `bot_say`, a ping's mark,
## an order taken or refused): heard with
## the next step's events, as a server's broadcast would be.
var _answers: Array[Dictionary] = []
## The dead already staged (`stage_the_dead`).
var _staged := {}
var _probe: WorldProbe


## Builds the lot and the server and joins `players`; the night is started but still in its first
## break. A seated night is freed with `dispose()`.
static func start(
	parent: Node,
	players: int,
	rules_tuning: RulesTuning = null,
	seed_value: int = 7,
	shopping: bool = false
) -> SeatedNight:
	var night := SeatedNight.new()
	night.world = NightWorld.new()
	parent.add_child(night.world)
	await night.world.build()
	night.server = NightServer.new(
		night.world, seed_value, NightTuning.shipped(), rules_tuning, MatchSettings.new()
	)
	night.server.drawn_bodies = false
	for id in range(1, players + 1):
		night.server.apply({"type": NightServer.JOIN, "player_id": id, "local": false})
	night.server.apply({"type": NightServer.START_NIGHT})
	night._probe = WorldProbe.new(night.world.get_world_3d().direct_space_state)
	night.level = BotLevel.new(
		night._probe.callable(),
		night.world.is_lit,
		night.server.rules.tuning.rounds,
		night.world.map()
	)
	# Bots do errands (shopping, boards, the generator) only when the level gives them the shop.
	LotBotData.fill(night.level, night.world, night.server.rules.tuning if shopping else null)
	# The bodies are indexed by the physics server on its next step.
	await parent.get_tree().physics_frame
	return night


## Seats a bot with `profile` at player `id`. `legacy` makes the autopilot's brain run on it;
## `hashing` makes it hash every command it sends (a replay or golden test; it costs time).
func seat(
	id: int, profile: BotProfile, bot_seed: int, legacy: bool = false, hashing: bool = false
) -> BotClient:
	var state := ClientState.new()
	state.player_id = id
	if stand_still:
		profile.follows = false
	var bot := BotClient.new(state, profile, bot_seed, Callable(self, &"_send").bind(id), level)
	if legacy:
		var autopilot := Autopilot.new(state, world.map())
		autopilot.sight = level.sight
		bot.legacy = autopilot
	bot.telemetry.hashing = hashing
	host.add(bot)
	return bot


## A stand-in for a person at seat `id`: it walks where it is told and is no bot.
func human(id: int) -> HumanWalker:
	var walker := HumanWalker.new(server, world.map(), id)
	walkers.append(walker)
	return walker


## The person at seat `issuer` gives the bots `order`, as the command wheel does through
## `BotOrders.issue`: the connection of that seat carries the action (bytes and back) and the server
## decides. Returns what was sent. The bots read it from the next frame.
func give_order(order: StringName, issuer: int, at: Vector3, bot_id := 0) -> Dictionary:
	var orders := BotOrders.new()
	orders.sender = Callable(self, &"_send").bind(issuer)
	return orders.issue(order, issuer, at, bot_id)


## Sells `door_id` to player 1 through the rules, as a purchase would: the lot opens it and the
## navigation takes the mesh of the new set in. Give the engine a few frames (`settle`) after.
func open_door(door_id: StringName) -> void:
	server.rules.apply(RulesAction.grant_points(1, 100000))
	var result := RulesFixture.buy(server.rules, 1, door_id)
	assert(result == GameRules.BuyResult.OK, "could not buy %s: %d" % [door_id, result])


## Ends the break and starts the round, and lets the bots hear what that said (`round_started` and
## the rest): the rules' answer to a direct action is not part of a server step, so the bots would
## not hear it otherwise.
func start_round() -> void:
	host.hear(server.rules.apply(RulesAction.skip_break()))


## Lets the engine take `frames` physics frames (the navigation map takes a new mesh in over a few).
func settle(frames: int) -> void:
	for _i in frames:
		await world.get_tree().physics_frame


## One tick of the night: the server steps, the stand-ins and the bots hear it, decide and send.
func tick() -> void:
	last_events.assign(_answers)
	_answers.clear()
	last_events.append_array(server.step(STEP))
	frame = last_events.back()
	_stage()
	if hash_every > 0 and server.tick_count % hash_every == 0:
		hashes.append(state_hash())
	if on_event.is_valid():
		for event in last_events:
			on_event.call(event)
	for walker in walkers:
		walker.tick()
	host.hear(last_events)
	host.tick(STEP)


func run(count: int) -> void:
	for _i in count:
		tick()


## Puts the seated players side by side on the open field in front of the screen, looking down it
## (where `stage_the_dead` puts the dead): the spawn spots are at the back of the lot.
func gather() -> void:
	var seats: Array = server.rules.players.keys()
	seats.sort()
	for i in seats.size():
		var at := (
			Autopilot.HOME + Vector3(3.0 * (float(i) - 0.5 * float(seats.size() - 1)), 0.1, 0.0)
		)
		server.body_of(seats[i]).teleport(at)


## Runs until the rules have put a zombie on the lot, then takes it out of the director's hands:
## it stands at `at` and chases (at `speed`, or the speed the rules rolled when that is negative).
## A tuning with one zombie to a round (`one_a_round`) makes it the only one.
func drop_zombie(at: Vector3, speed := -1.0, max_ticks := 900) -> ZombieBody:
	for _i in max_ticks:
		if not server.sim.zombies.is_empty():
			break
		tick()
	var zombie: ZombieBody = server.sim.zombies.values()[0]
	zombie.position = at
	zombie.gate_id = &""
	if speed >= 0.0:
		zombie.speed = speed
	zombie.enter(ZombieBody.Mode.CHASE)
	return zombie


## The shipped table with one zombie to a round, coming at once.
static func one_a_round() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.count_base = 1.0
	tuning.rounds.count_linear = 0.0
	tuning.rounds.count_quadratic = 0.0
	tuning.rounds.first_spawn_delay = 0.1
	return tuning


## The shipped table with the dead walking fast from the first round, so a short run has a fight
## in it (the golden and replay runs are a few hundred steps long).
static func brisk() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.speed_base = 5.0
	tuning.rounds.speed_step = 0.0
	tuning.rounds.speed_jitter = 0.0
	tuning.rounds.first_spawn_delay = 0.1
	return tuning


## Plays `recorded` (the actions bots sent, `{tick, player_id, action}`) into this night, which has
## no bots: after each step, the actions that were sent after that step. Returns the state hash
## after every `every` steps, `steps` steps in all.
func replay(recorded_actions: Array[Dictionary], steps: int, every: int) -> Array[int]:
	var by_tick := {}
	for entry in recorded_actions:
		if not by_tick.has(entry["tick"]):
			by_tick[entry["tick"]] = []
		by_tick[entry["tick"]].append(entry)
	var hashes: Array[int] = []
	for _i in steps:
		last_events.assign(server.step(STEP))
		frame = last_events.back()
		_stage()
		if server.tick_count % every == 0:
			hashes.append(state_hash())
		for entry: Dictionary in by_tick.get(server.tick_count, []):
			server.apply(entry["action"], entry["player_id"])
	return hashes


## The server's word on the state, coarse on purpose: the rules (round, phase, the dead left), each
## player's place in quarter metres, health, ammunition, points, kills and downs, and how many dead
## stand. Two things are left out because two runs of the same commands do not agree on them to
## the last bit: a body the physics engine moves (it meets the floor's contacts in an order that
## follows ids) and the way a zombie walks round an obstacle when two routes tie (the navigation
## mesh breaks the tie by polygon ids, which differ between worlds). A zombie's place is the
## second: it differed by 0.75 m in about a run in four.
func state_hash() -> int:
	var parts: Array = [frame["tick"], frame["phase"], frame["round"], frame["remaining"]]
	var seats: Array = frame["players"].keys()
	seats.sort()
	for seat in seats:
		var p: Dictionary = frame["players"][seat]
		(
			parts
			. append_array(
				[
					_snap(p["pos"]),
					roundi(p["health"]),
					p["downed"],
					p["weapon"],
					p["ammo"],
					p["reserve"],
					p["points"],
					p["kills"],
					p["downs"],
				]
			)
		)
	var ids: Array = server.sim.zombies.keys()
	ids.sort()
	for id in ids:
		var zombie: ZombieBody = server.sim.zombies[id]
		parts.append_array([id, zombie.mode, _snap(zombie.position)])
	return hash(var_to_bytes(parts))


static func _snap(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x * 4.0), roundi(point.y * 4.0), roundi(point.z * 4.0))


func dispose() -> void:
	# A handler that names the night would keep it alive in a cycle.
	on_event = Callable()
	server.close()
	world.queue_free()


## See `stage_the_dead`.
func _stage() -> void:
	if not stage_the_dead:
		return
	var ids: Array = server.sim.zombies.keys()
	ids.sort()
	var seats: Array = server.rules.players.keys()
	seats.sort()
	for id: int in ids:
		var zombie: ZombieBody = server.sim.zombies[id]
		if _staged.has(id) or zombie.mode == ZombieBody.Mode.DYING:
			continue
		_staged[id] = true
		var owner := server.body_of(seats[id % seats.size()]).global_position
		var around := deg_to_rad(float((id * 37) % 80) - 40.0)
		var ahead := Vector3(-sin(around), 0.0, -cos(around)) * (10.0 + float(id % 4) * 2.0)
		zombie.position = NavigationServer3D.map_get_closest_point(world.map(), owner + ahead)
		zombie.gate_id = &""
		zombie.enter(ZombieBody.Mode.CHASE)


## What a bot sends: plain data, to the server as a connection's message from player `id`. (A
## callable to a method, not a lambda: a lambda naming a member would hold this object, which holds
## the bots, which hold the lambda.)
func _send(action: Dictionary, id: int) -> void:
	var plain: Dictionary = bytes_to_var(var_to_bytes(action))
	if hold_fire:
		plain["fire"] = false
	if recording and plain.get("type") != NightServer.SAY:
		recorded.append({"tick": server.tick_count, "player_id": id, "action": plain})
	for event in server.apply(plain, id):
		if (
			event["type"] == &"bot_say"
			or event["type"] == &"ping_placed"
			or event["type"] == BotOrders.EVENT_SET
			or event["type"] == BotOrders.EVENT_REFUSED
		):
			_answers.append(event)
