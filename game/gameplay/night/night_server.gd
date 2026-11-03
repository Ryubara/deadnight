class_name NightServer
extends RefCounted
## The authority of one night: the rules, the zombies, the weapons and the players' bodies, joined
## and stepped together. Everything that decides anything lives here; a client only sends
## `NightCommand`s and draws the events and frames that come back.
##
## Messages in (`apply`, plain dictionaries): `join` {player_id, local}, `leave` {player_id},
## `look` {player_id, packet} (a client's look, once after it joins), `start_night`, and one
## `command` (a `NightCommand`) per player per tick; the latest one is used, except that a pressed
## edge (use, reload, swap, jump) of a command the step has not met yet is kept. A command is the
## sender's: `apply` takes the player from its caller (`from_id`, the connection) and ignores the
## one the message names. A command that is not renewed for `NightTuning.command_ticks` steps is
## replaced by a neutral one that keeps only the view angles (a client that stalled or left stops
## walking and shooting). The look server answers a join and a look with `look_packet` events
## (`LOOK_PACKET`). `step(delta)` runs one fixed tick and returns the events for every client: the
## rules events (a zombie's blow is a `blow` action, answered by the rules' `player_hurt`), the
## weapons events (`CombatServer`), `player_damaged` (the blow as the world saw it: `from`, where it
## came from, and the zombie's id, type and `knockback`: metres the blow throws the player, recorded
## for the player's own motion to apply), and last a `frame`. A frame carries the whole picture a
## client or a HUD draws from. Frame fields: tick, phase, round, remaining, fuel, circuits ({id:
## on}), doors (open ids), barricades ({id: boards up}), pings ({player_id: {kind, pos, subject,
## left}}), zombies (`ZombieCodec` bytes), players {id: {pos, facing, health, downed, weapon, aim
## (the aim pose is held), pitch (the look up or down, `pitch_step`), stance (`PlayerStance` bits),
## ammo, reserve, reloading, arms (every weapon carried: id to [ammo, reserve, tier]), points,
## prompt, reviving (the teammate this one is raising, 0 for none), revive (0 to 1: how far the hold
## on this one, when downed, has got), ack (the `seq` of the command this step used: a predicting
## client replays from it), kills, downs, revives, dead (bled out), bleed (seconds a downed player
## has left) and reviver (who is raising this one, 0 for nobody)}}. Single-player runs this beside
## the client, joined by a `LoopbackLink`.

## Ticks between the asks which areas the map has taken in (a quarter second).
const SPAWN_RETRY_TICKS := 15
const COMMAND := &"command"
const JOIN := &"join"
const LEAVE := &"leave"
## A person takes the seat of a bot: `seat_person` {player_id}. The seat, its body, points and
## weapons stay as they are; the rules say `bot_replaced`.
const SEAT_PERSON := &"seat_person"
const START_NIGHT := &"start_night"
## A player marks something for the others: `ping` {kind, pos, subject}, see `PingBoard`.
const PING := &"ping"
const ORDER := BotOrders.ACTION  # `order` {order, at, bot_id}: a person orders the bots
## A bot calls out a line of `BotSay`: `say` {line, subject, pos}, see `SayBoard`.
const SAY := &"say"
## A player came back on a new connection: `resync` {player_id} tells it the looks again.
const RESYNC := &"resync"
## A client's look, as `LookWire.look` bytes: `look` {player_id, packet}.
const LOOK := &"look"
## The look server's answer to one client: `look_packet` {to, packet (`LookWire.player_look`)}.
const LOOK_PACKET := &"look_packet"
## The weapons events worth sending on (the rules events ride the rules signal; the weapons
## answer repeats them).
const COMBAT_EVENTS: Array[StringName] = [
	&"shot_fired",
	&"quick_melee",
	&"damage_dealt",
	&"target_killed",
	&"reload_started",
	&"reload_finished",
	&"reload_rejected",
	&"weapon_replaced",
	&"weapon_equipped",
	&"ammo_added",
	&"weapon_upgraded",
	&"projectile_spawned",
	&"projectile_burst",
	&"lure_started",
	&"fire_rejected",
]
## What the grenade server answers that is worth sending on (its answer also repeats the rules'
## events, which ride the rules signal). The night adds `throw_started` (player_id, underarm): the
## button came up and the arm swings; the grenade leaves a moment later (`grenade_thrown`).
const GRENADE_EVENTS: Array[StringName] = [
	&"cook_started",
	&"cook_rejected",
	&"throw_rejected",
	&"grenade_thrown",
	&"grenade_dropped",
	&"grenade_bounced",
	&"grenade_struck",
	&"grenade_exploded",
	&"blast_hit",
	&"player_blasted",
]
## The grenade the night throws.
const GRENADE_DEF := "res://gameplay/grenades/defs/frag.tres"
## A held trigger meets these every tick; they are not news.
const QUIET_REJECTIONS: Array[StringName] = [&"cooldown", &"reloading"]
## The frame names where a player looks up or down in steps of this many radians (3 degrees): a
## drawn copy only needs the barrel to follow, and a field that did not change costs nothing.
const PITCH_STEP := deg_to_rad(3.0)

var rules: GameRules
var combat: CombatServer
## Every grenade: who is cooking one, the ones in the air, the blasts (`GrenadeServer`).
var grenades: GrenadeServer
var sim: ZombieSim
var director: ZombieDirector
var world: NightWorld
## Every player's accepted look and seat (`docs/design/customization.md`, On the network).
var looks: LookServer
var tuning: NightTuning:
	set(value):
		tuning = value
		if _revive != null:
			_revive.tuning = value
			_ping_judge.tuning = value
var tick_count := 0
## The marks the players have put up.
var ping_board := PingBoard.new()
var bot_orders := BotOrders.new()
var say_board := SayBoard.new()
## Whether the players' bodies have the Soldier's model. A game server draws nothing, so it leaves
## them out (`NightHost`); in one process with its client the same bodies are drawn.
var drawn_bodies := true
## The round trip each connected player last reported, milliseconds (the game server fills it from
## their pings): a player with no entry has none to show, and a night on a loopback has no one's.
var pings: Dictionary[int, int] = {}
## The crowd this match stands, from the weakest client in it (`CrowdCeiling.set_platform`).
var crowd := CrowdCeiling.new()

var _pending: Dictionary[int, NightCommand] = {}
## Steps since each player's last command arrived.
var _silent: Dictionary[int, int] = {}
## The `seq` of the command each player's last step used.
var _acked: Dictionary[int, int] = {}
var _bodies: Dictionary[int, Player] = {}
var _shot_seq: Dictionary[int, int] = {}
var _hand_wait: Dictionary[int, float] = {}
## The breach each player's held `use` is repairing (`&""`: none): from a press at a breach until
## the button comes up, the breach is whole or out of reach, or the player acts, is hit or falls.
var _repairing: Dictionary[int, StringName] = {}
## The breach each player last put a board back across, and how long (s) the body still turns to
## face it (#245): a repair is allowed by place, not by facing, so the body turns to the boards
## while the clip hammers them (walking or aiming turns it the player's way).
var _facing_breach: Dictionary[int, StringName] = {}
var _face_left: Dictionary[int, float] = {}
## The teammates raising downed players (held `use` beside a downed one).
var _revive: ReviveChannel
## What decides whether a ping is true, and whether an order to the bots is taken.
var _ping_judge: PingJudge
var _order_judge: OrderJudge
var _outbox: Array[Dictionary] = []
var _probe: WorldProbe
## Held here: a Callable does not keep its RefCounted alive.
var _cast: WorldCast
## Each player's side of a throw: the grenade buttons of their commands as cook and throw actions.
var _throwers: Dictionary[int, GrenadeThrower] = {}


func _init(
	p_world: NightWorld,
	p_seed: int = 1,
	p_tuning: NightTuning = null,
	p_rules_tuning: RulesTuning = null,
	p_settings: MatchSettings = null
) -> void:
	world = p_world
	looks = LookServer.new(_send_look)
	tuning = p_tuning if p_tuning != null else NightTuning.shipped()
	ping_board.seconds = tuning.ping_seconds
	ping_board.gap = tuning.ping_gap
	rules = GameRules.new(p_rules_tuning, p_seed, p_settings)
	_probe = WorldProbe.new(world.get_world_3d().direct_space_state)
	combat = CombatServer.new(WeaponCatalog.all(), rules, _probe.callable(), p_seed)
	_cast = WorldCast.new(world.get_world_3d().direct_space_state)
	grenades = GrenadeServer.new(
		load(GRENADE_DEF) as GrenadeDef, rules, _cast.callable(), _probe.callable()
	)
	sim = ZombieSim.new(null, p_seed)
	sim.rounds = rules.tuning.rounds
	sim.pathing = NavmeshPathing.new(world.map())
	world.equip(sim, _probe.callable())
	sim.barricades = rules.barricades
	sim.board_seconds = rules.tuning.barricades.seconds_per_board
	_revive = ReviveChannel.new(tuning, rules, _bodies, _announce)
	_ping_judge = PingJudge.new(tuning, ping_board, rules, world, sim, _bodies, _announce)
	_order_judge = OrderJudge.new(_ping_judge, bot_orders, rules, world, _bodies, _announce)
	director = ZombieDirector.new(rules, sim, world.spawn_points())
	director.spawn_gates = world.spawn_gates()
	director.player_struck.connect(_on_player_struck)
	world.bind(rules)
	rules.event_emitted.connect(_on_rules_event)
	crowd.bind(rules, sim)


## Stops listening to the rules and the doors, so nothing calls into a finished night. Call when
## the night is over.
func close() -> void:
	combat.detach()
	director.close()
	if rules.event_emitted.is_connected(_on_rules_event):
		rules.event_emitted.disconnect(_on_rules_event)


## The one way in. Returns the events the message caused. `from_id` is the player whose
## connection the message came in on (0 when there is only one, as in single-player): a command is
## always that player's.
func apply(action: Dictionary, from_id: int = 0) -> Array[Dictionary]:
	_outbox = []
	match action.get("type"):
		JOIN:
			_join(action["player_id"], action.get("local", false), action.get("bot", false))
		LEAVE:
			_leave(action["player_id"])
		SEAT_PERSON, RulesAction.SEAT_BOT:
			rules.apply({"type": action["type"], "player_id": action["player_id"]})
		START_NIGHT:
			rules.apply(RulesAction.start())
		LOOK:
			looks.receive(action["player_id"], action["packet"])
		PING:
			ping(from_id if from_id > 0 else action.get("player_id", 1), action)
		ORDER:
			_order_judge.give(from_id if from_id > 0 else action.get("player_id", 1), action)
		SAY:
			say(from_id if from_id > 0 else action.get("player_id", 1), action)
		RESYNC:
			if _bodies.has(action["player_id"]):
				looks.sync(action["player_id"])
		COMMAND:
			submit(
				from_id if from_id > 0 else action.get("player_id", 1),
				NightCommand.from_dict(action)
			)
	return _outbox


## The most zombies alive at once in this match now (`crowd`).
func crowd_ceiling() -> int:
	return rules.crowd_ceiling


## Keeps the newest command of a player, with the pressed edges of the one it replaces if no step
## has used that one yet.
func submit(player_id: int, command: NightCommand) -> void:
	if not _bodies.has(player_id):
		return
	command.player_id = player_id
	if command.view_step >= 0:
		command.view_tick = _view_tick_of(command.view_step)
	var old: NightCommand = _pending.get(player_id)
	if old != null:
		command.inherit_edges(old)
		command.motion.jump = command.motion.jump or old.motion.jump
		command.motion.melee = command.motion.melee or old.motion.melee
		command.motion.swap_shoulder = command.motion.swap_shoulder or old.motion.swap_shoulder
	_pending[player_id] = command
	_silent[player_id] = 0


## The step of the frame's `pitch` for a look of `radians` (up is positive).
static func pitch_step(radians: float) -> int:
	return roundi(clampf(radians, -PI / 2.0, PI / 2.0) / PITCH_STEP)


## The look up or down a step of the frame's `pitch` means.
static func pitch_from_step(step: int) -> float:
	return step * PITCH_STEP


## The server step a shooter's view step (the low 16 bits) means: the latest step with those bits
## that is not in the future, so the wrap of a long night is no matter.
func _view_tick_of(view_step: int) -> int:
	var behind := (tick_count - view_step) & 0xFFFF
	return tick_count - behind if behind <= 0x7FFF else tick_count


func body_of(player_id: int) -> Player:
	return _bodies.get(player_id)


func health_of(player_id: int) -> float:
	return rules.health_of(player_id)


## One fixed tick. Returns every event of it, the frame last.
func step(delta: float, with_frame := true) -> Array[Dictionary]:
	_outbox = []
	tick_count += 1
	var began := PerfProbe.begin()
	_move_players()
	PerfProbe.end(&"server.move", began)
	if tick_count % SPAWN_RETRY_TICKS == 0:
		director.spawn_points = world.spawn_points()
	began = PerfProbe.begin()
	director.tick(delta, _chase_targets())
	PerfProbe.end(&"server.zombies", began)
	began = PerfProbe.begin()
	rules.apply(RulesAction.tick(delta, _revive.held_targets()))
	PerfProbe.end(&"server.rules", began)
	began = PerfProbe.begin()
	var target_list := _target_list()
	PerfProbe.end(&"server.target_list", began)
	began = PerfProbe.begin()
	_combat(CombatAction.targets(target_list))
	_combat(CombatAction.tick(delta))
	PerfProbe.end(&"server.combat", began)
	began = PerfProbe.begin()
	_revive.begin_tick()
	for player_id in _bodies:
		_act(player_id, delta)
	_revive.finish_tick(delta)
	PerfProbe.end(&"server.act", began)
	began = PerfProbe.begin()
	_outbox.append_array(ping_board.step(delta))
	bot_orders.step(delta)
	say_board.step(delta)
	_throw_grenades(delta)
	if with_frame:
		_outbox.append(_frame())
	PerfProbe.end(&"server.frame", began)
	return _outbox


# --- Players ---


func _join(player_id: int, local: bool, bot := false) -> void:
	if _bodies.has(player_id):
		return
	_bodies[player_id] = world.add_body(world.player_spawn(_bodies.size()), local, drawn_bodies)
	crowd.join(player_id, OS.has_feature("web") if local else true)
	looks.join(player_id)
	_shot_seq[player_id] = 0
	_hand_wait[player_id] = 0.0
	_repairing[player_id] = &""
	var thrower := GrenadeThrower.new(player_id, grenades.def)
	thrower.release_over = tuning.grenade_release_over
	thrower.release_under = tuning.grenade_release_under
	_throwers[player_id] = thrower
	rules.apply(RulesAction.add_player(player_id, bot))
	# What the rules say the player starts with, the firearm last so it is the one in hand.
	for shop_id in rules.players[player_id].weapons:
		_combat(CombatAction.give_weapon(player_id, WeaponCatalog.catalog_id(shop_id)))


func _leave(player_id: int) -> void:
	if _bodies.has(player_id):
		_bodies[player_id].queue_free()
		_bodies.erase(player_id)
		crowd.leave(player_id)
		_pending.erase(player_id)
		_silent.erase(player_id)
		_acked.erase(player_id)
		pings.erase(player_id)
		_repairing.erase(player_id)
		_revive.forget(player_id)
		ping_board.forget(player_id)
		bot_orders.forget(player_id)
		say_board.forget(player_id)
		_throwers.erase(player_id)
		_facing_breach.erase(player_id)
		_face_left.erase(player_id)
		looks.leave(player_id)
		rules.apply(RulesAction.remove_player(player_id))


## The look server's way to reach one client: an event for it, carried like any other.
func _send_look(player_id: int, packet: PackedByteArray) -> void:
	_outbox.append({"type": LOOK_PACKET, "to": player_id, "packet": packet})


func _announce(event: Dictionary) -> void:
	_outbox.append(event)


func _is_downed(player_id: int) -> bool:
	var state: PlayerState = rules.players.get(player_id)
	return state == null or state.downed


func _move_players() -> void:
	for player_id in _bodies:
		_silent[player_id] = _silent.get(player_id, 0) + 1
		var command := _pending.get(player_id) as NightCommand
		if command != null and _silent[player_id] > tuning.command_ticks:
			command = _neutral_after(command)
			_pending[player_id] = command
		var motion := PlayerCommand.new()
		if command != null:
			_acked[player_id] = command.seq
			motion.yaw = command.motion.yaw
			motion.pitch = command.motion.pitch
			if not _is_downed(player_id):
				motion = command.motion
				# The trigger is the command's own, whoever made the motion.
				motion.fire = command.fire
		_bodies[player_id].tick(motion)
		if command != null:
			# Pressed edges are used once.
			command.motion.jump = false
			command.motion.melee = false
			command.motion.swap_shoulder = false


## What a command that was not renewed becomes: standing still with the trigger released, looking
## where it looked.
func _neutral_after(old: NightCommand) -> NightCommand:
	var command := NightCommand.new()
	command.player_id = old.player_id
	command.seq = old.seq
	command.motion.yaw = old.motion.yaw
	command.motion.pitch = old.motion.pitch
	command.dir = old.dir
	command.origin = old.origin
	return command


func _chase_targets() -> Dictionary:
	var targets := {}
	for player_id in _bodies:
		if not _is_downed(player_id):
			targets[player_id] = _bodies[player_id].global_position
	return targets


func _on_player_struck(player_id: int, zombie_id: int, damage: float) -> void:
	if not _bodies.has(player_id) or _is_downed(player_id):
		return
	var zombie: ZombieBody = sim.zombies.get(zombie_id)
	var from := _position_of_zombie(zombie_id)
	rules.apply(RulesAction.blow(player_id, damage, _bearing(player_id, from), zombie_id))
	(
		_outbox
		. append(
			{
				"type": &"player_damaged",
				"player_id": player_id,
				"damage": damage,
				"health": rules.health_of(player_id),
				"from": from,
				"zombie_id": zombie_id,
				"zombie_type": zombie.profile.type if zombie != null else &"",
				"knockback": zombie.profile.knockback if zombie != null else 0.0,
			}
		)
	)


## Radians clockwise from -z (seen from above) from the player to `from`: the bearing the rules
## carry, so a client can turn it toward where its own player faces.
func _bearing(player_id: int, from: Vector3) -> float:
	var offset := from - _bodies[player_id].global_position
	return atan2(offset.x, -offset.z)


## Where a zombie stands (the bearing of a blow); the player's own spot when it is gone.
func _position_of_zombie(zombie_id: int) -> Vector3:
	var zombie: ZombieBody = sim.zombies.get(zombie_id)
	return zombie.position if zombie != null else Vector3.ZERO


# --- What the rules decided ---


func _on_rules_event(event: Dictionary) -> void:
	_outbox.append(event)
	match event["type"]:
		&"player_hurt":
			_repairing[event["player_id"]] = &""
		&"purchase_made":
			_deliver(event["player_id"], event["detail"])
		&"crane_prize_taken":
			_deliver(event["player_id"], {"weapon": event["weapon"], "released": event["released"]})


# --- Grenades ---


## One tick of every grenade: tells the grenade server where the players and the dead stand, turns
## each player's grenade buttons into cook and throw actions, and steps the fuses and the flights.
## The blasts are the rules' (`explosion`), the thrower's own share reaches their health.
func _throw_grenades(delta: float) -> void:
	var standing: Array = []
	for player_id in _bodies:
		standing.append({"id": player_id, "pos": _bodies[player_id].global_position})
	_grenade(GrenadeAction.players(standing))
	_grenade(GrenadeAction.targets(_target_list()))
	for player_id in _bodies:
		_throw_of(player_id, delta)
	_grenade(GrenadeAction.tick(delta))


func _throw_of(player_id: int, delta: float) -> void:
	var thrower: GrenadeThrower = _throwers[player_id]
	var command := _pending.get(player_id) as NightCommand
	var motion := PlayerCommand.new()
	var look := Vector3.ZERO
	if command != null:
		look = command.dir
		if not _is_downed(player_id):
			motion = command.motion
	var body := _bodies[player_id]
	var launch := GrenadeThrower.launch(
		grenades.def, tuning.grenade_hand_reach, body.global_position, body.state.facing, look
	)
	var actions := thrower.step(motion, launch["hand"], launch["aim"], body.state.velocity, delta)
	if thrower.swing_began() != &"":
		(
			_outbox
			. append(
				{
					"type": &"throw_started",
					"player_id": player_id,
					"underarm": thrower.swing_began() == &"under",
				}
			)
		)
	for action in actions:
		_grenade(action)


func _grenade(action: Dictionary) -> void:
	var blast_at := Vector3.ZERO
	for event in grenades.apply(action):
		if not GRENADE_EVENTS.has(event["type"]):
			continue
		_outbox.append(event)
		match event["type"]:
			&"cook_rejected":
				_throwers[event["player_id"]].abandon()
			&"grenade_dropped":
				_throwers[event["thrower_id"]].abandon()
			&"grenade_exploded":
				blast_at = event["point"]
				if event["in_hand"]:
					_throwers[event["thrower_id"]].abandon()
			&"blast_hit":
				sim.blast(event["target_id"], event["impulse"], event["stun"])
			&"player_blasted":
				_blast_player(event, blast_at)


## The blast reached a player (the thrower, unless friendly fire is on): their health takes it.
func _blast_player(event: Dictionary, from: Vector3) -> void:
	var player_id: int = event["player_id"]
	if not _bodies.has(player_id):
		return
	rules.apply(RulesAction.blow(player_id, event["damage"], _bearing(player_id, from)))


# --- Weapons and hands ---


## A purchase for a player, as the shop sells it. Items in the shop: `weapon_shotgun`, the crane's
## `weapon_smg`; the weapons know `shotgun`, `smg`. This is the one place that translates.
## Ammunition: the rules priced exactly the rounds that fitted. Returns the rules' events.
func buy(player_id: int, item_id: StringName) -> Array[Dictionary]:
	var item := rules.tuning.economy.item(item_id)
	var rounds := -1
	var weapon: StringName = &""
	if item != null and item.kind == ShopItem.Kind.AMMO:
		rounds = ammo_room(player_id, item.weapon)
	if item != null and item.kind in [ShopItem.Kind.UPGRADE, ShopItem.Kind.WEAPON]:
		weapon = MachineOffers.weapon_for(self, player_id)
	return rules.apply(RulesAction.buy(player_id, item_id, rounds, weapon))


## Rounds the player's reserve of this weapon has room for; 0 for a weapon not carried.
func ammo_room(player_id: int, weapon_id: StringName) -> int:
	var state := combat.state_of(player_id, weapon_id)
	if state == null or not state.uses_ammo():
		return 0
	return state.def.reserve_max - state.reserve


func _deliver(player_id: int, detail: Dictionary) -> void:
	var weapon: StringName = detail.get("weapon", &"")
	if weapon != &"":
		var released := WeaponCatalog.catalog_id(detail.get("released", &""))
		_combat(CombatAction.give_weapon(player_id, WeaponCatalog.catalog_id(weapon), released))
	var ammo: StringName = detail.get("ammo", &"")
	if ammo != &"":
		_combat(CombatAction.add_ammo(player_id, ammo, detail["rounds"]))
	var upgrade: StringName = detail.get("upgrade", &"")
	if upgrade != &"":
		_combat(CombatAction.upgrade_weapon(player_id, upgrade))


func _combat(action: Dictionary) -> void:
	for event in combat.apply(action):
		if not COMBAT_EVENTS.has(event["type"]):
			continue
		if event["type"] == &"fire_rejected" and QUIET_REJECTIONS.has(event["reason"]):
			continue
		if event["type"] == &"lure_started":
			sim.add_lure(event["lure_id"], event["point"], event["radius"], event["seconds"])
		_outbox.append(event)


func _target_list() -> Array:
	var list: Array = []
	for zombie: ZombieBody in sim.zombies.values():
		if zombie.is_alive():
			(
				list
				. append(
					{
						"id": zombie.id,
						"pos": zombie.position,
						"yaw": zombie.yaw,
						"scale": zombie.profile.hit_scale(),
						"weak": zombie.profile.weak,
					}
				)
			)
	return list


func _act(player_id: int, delta: float) -> void:
	_hand_wait[player_id] = maxf(_hand_wait[player_id] - delta, 0.0)
	var command := _pending.get(player_id) as NightCommand
	if command == null or _is_downed(player_id):
		_repairing[player_id] = &""
		_revive.stop(player_id, &"down")
		return
	if command.reload:
		_combat(CombatAction.reload_weapon(player_id))
	# The shot leaves when the body faces the view (the press waits for the turn, #477): the
	# simulation says when, from the same commands a predicting client runs.
	if _bodies[player_id].state.shot_ready:
		_shoot(player_id, command, delta)
	if command.swap:
		_combat(CombatAction.swap(player_id))
	if command.slot != WeaponSlots.NONE:
		_combat(CombatAction.select_slot(player_id, command.slot))
	if _bodies[player_id].state.melee_ready:
		_repairing[player_id] = &""
		_quick_melee(player_id, command, delta)
	if command.swap or command.slot != WeaponSlots.NONE or command.fire or command.reload:
		_repairing[player_id] = &""
	if command.use:
		_use(player_id)
	_hold_repair(player_id, command)
	_revive.hold(player_id, command.use_held)
	_face_breach(player_id, delta)
	# Edges are used once.
	command.clear_edges()


func _shoot(player_id: int, command: NightCommand, delta: float) -> void:
	if not aims_with_view(command):
		_outbox.append(
			{"type": &"fire_rejected", "player_id": player_id, "reason": &"aim_mismatch"}
		)
		return
	var body := _bodies[player_id]
	var head := body.global_position + Vector3(0.0, tuning.eye_height, 0.0)
	var origin := command.origin
	if origin.distance_to(head) > tuning.origin_slack:
		origin = head + (origin - head).normalized() * tuning.origin_slack
	# A blow reaches from the body, not from the shoulder camera 2.3 m behind it: swept from the
	# camera, a crowbar's 1.9 m fell short of a zombie standing at the player's face (#285).
	var held := combat.weapon_of(player_id)
	if held != null and held.def.is_melee():
		origin = head
	var muzzle := body.global_position + Basis(Vector3.UP, body.state.facing) * tuning.muzzle_offset
	_shot_seq[player_id] += 1
	# The shot is judged against the world the shooter saw (`LagCompensator` caps how far back).
	var view_time := combat.now
	if command.view_step >= 0:
		view_time -= float(maxi(tick_count - command.view_tick, 0)) * delta
	_combat(
		CombatAction.fire(player_id, _shot_seq[player_id], origin, command.dir, muzzle, view_time)
	)


## The quick melee button (#411): a blow along the view from the head, whatever the player holds
## (the server's cooldown is its own). Not while a grenade is cooking in the hand (the arm is busy).
func _quick_melee(player_id: int, command: NightCommand, delta: float) -> void:
	if grenades.is_cooking(player_id):
		return
	if not aims_with_view(command):
		_outbox.append(
			{"type": &"fire_rejected", "player_id": player_id, "reason": &"aim_mismatch"}
		)
		return
	var body := _bodies[player_id]
	var head := body.global_position + Vector3(0.0, tuning.eye_height, 0.0)
	var muzzle := body.global_position + Basis(Vector3.UP, body.state.facing) * tuning.muzzle_offset
	_shot_seq[player_id] += 1
	var view_time := combat.now
	if command.view_step >= 0:
		view_time -= float(maxi(tick_count - command.view_tick, 0)) * delta
	_combat(
		CombatAction.quick_melee(
			player_id, _shot_seq[player_id], head, command.dir, muzzle, view_time
		)
	)


## Where a view with this turn and look points (the camera's forward: yaw 0 and pitch 0 look down
## -z, a positive pitch looks up). What a shot's direction is checked against.
static func view_dir(yaw: float, pitch: float) -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD


## Whether the command's shot goes where its own view points, within `aim_slack_degrees`. A person
## shoots along the camera, so this is always true for one; a client that shoots at a zombie it is
## not looking at (a bot that skipped the turn, a tampered client) is false.
func aims_with_view(command: NightCommand) -> bool:
	var view := view_dir(command.motion.yaw, command.motion.pitch)
	var shot := command.dir
	if not shot.is_finite() or shot.length() < 0.5:
		return false
	return rad_to_deg(view.angle_to(shot.normalized())) <= tuning.aim_slack_degrees


## What `use` would do for a player right now: `{}`, a door to buy, a weapon on a wall, the crane
## or rounds to buy (the nearest shop spot in reach), `{"kind": &"repair", "id", "boards"}` for a
## breach with a board down that the player stands inside, in reach of, or `{"kind": &"circuit",
## "id", "on"}` for a breaker post in reach (`on`: how the circuit is now), or `{"kind": &"fuel",
## "id", "item", "price", "units"}` at a fuel can spot (what the rules would sell now: `units` and
## `price` are 0 when the tank is full), or `{"kind": &"revive", "id", "progress", "bleed"}` beside
## a downed teammate (`progress`: 0 to 1 of the hold, `bleed`: seconds left; it comes first).
func use_target(player_id: int) -> Dictionary:
	var body := _bodies.get(player_id) as Player
	if body == null:
		return {}
	var here := body.global_position
	var raise := _revive.in_reach(player_id)
	if raise != 0:
		return {
			"kind": &"revive",
			"id": raise,
			"progress": _revive.progress(raise),
			"bleed": rules.bleed_left_of(raise),
		}
	var door := UseOffers.door(world, rules, tuning, here)
	if not door.is_empty():
		return door
	var offer := _spot_offer(player_id, here)
	if not offer.is_empty():
		return offer
	var post := UseOffers.post(world, rules, tuning, here)
	if not post.is_empty():
		return post
	return UseOffers.fuel(world, rules, tuning, here)


## The offer of the nearest shop spot in reach that has one, or `{}`.
func _spot_offer(player_id: int, here: Vector3) -> Dictionary:
	var best := {}
	var best_apart := INF
	for spot in world.shop_spots():
		var apart := world.reach_distance(here, spot["position"])
		if apart > tuning.use_reach or apart >= best_apart:
			continue
		var offer := _offer_at(player_id, spot)
		if not offer.is_empty():
			best = offer
			best_apart = apart
	return best


## What one spot sells this player: a wall gives its weapon, or the rounds for it once owned; the
## crane gives a prize while the pool lasts; a locker gives rounds for the weapon in hand.
func _offer_at(player_id: int, spot: Dictionary) -> Dictionary:
	match spot["kind"]:
		&"wall":
			var weapon := WeaponCatalog.catalog_id(spot["shop_id"])
			if combat.state_of(player_id, weapon) != null:
				return _ammo_offer(player_id, weapon)
			return {
				"kind": &"weapon",
				"id": spot["shop_id"],
				"weapon": weapon,
				"price": rules.price_of(spot["shop_id"]),
				"replaces": MachineOffers.replaces(self, player_id, weapon),
			}
		&"crane":
			return _crane_offer(player_id, spot)
		MachineOffers.UPGRADE_SPOT, MachineOffers.PERK_SPOT, MachineOffers.RACK_SPOT:
			return MachineOffers.offer(self, player_id, spot)
		&"ammo":
			var held := combat.weapon_of(player_id)
			return _ammo_offer(player_id, held.def.id) if held != null else {}
	return {}


## The crane at its current spot: a play to buy while it is free, the prize to take for the buyer
## while it is held out, and for anyone else "only the buyer" (`kind` `crane_busy`, with `buyer`).
## Nothing at a spot the crane is not standing on, and nothing once the pool is empty for you.
func _crane_offer(player_id: int, spot: Dictionary) -> Dictionary:
	var crane := rules.crane
	if spot["crane_spot"] != crane.spot:
		return {}
	var item := rules.tuning.economy.item(spot["shop_id"])
	var owned: Array[StringName] = rules.players[player_id].weapons
	if item == null:
		return {}
	if crane.is_ready():
		if item.pool_without(owned).is_empty():
			return {}
		return {"kind": &"crane", "id": item.id, "price": rules.price_of(item.id)}
	if crane.buyer_id == player_id and crane.stage == CraneState.Stage.GRAB:
		return {
			"kind": &"crane_take",
			"id": item.id,
			"weapon": crane.weapon,
			"left": crane.left,
			"replaces": MachineOffers.replaces(self, player_id, crane.weapon),
		}
	return {"kind": &"crane_busy", "id": item.id, "buyer": crane.buyer_id}


## Rounds for a weapon, as many as fit (one purchase at most), or `{}` when none do or are sold.
func _ammo_offer(player_id: int, weapon: StringName) -> Dictionary:
	var item := rules.tuning.economy.ammo_item_for(weapon)
	if item == null:
		return {}
	var rounds := mini(ammo_room(player_id, weapon), int(item.amount))
	if rounds <= 0:
		return {}
	return {
		"kind": &"ammo",
		"id": item.id,
		"weapon": weapon,
		"rounds": rounds,
		"price": item.ammo_price(rules.round_number, rounds),
	}


func _use(player_id: int) -> void:
	var target := use_target(player_id)
	match target.get("kind"):
		&"door", &"weapon", &"ammo", &"grenades", &"crane", &"recut", &"tonic":
			buy(player_id, target["id"])
		&"crane_take":
			var held := MachineOffers.weapon_for(self, player_id)
			rules.apply(RulesAction.crane_take(player_id, held))
		&"repair":
			_repairing[player_id] = target["id"]
			_repair(player_id, target["id"])
		&"circuit":
			if _hand_wait[player_id] <= 0.0:
				_hand_wait[player_id] = tuning.switch_interval
				rules.apply(RulesAction.set_circuit(target["id"], not target["on"]))
		&"fuel":
			if _hand_wait[player_id] <= 0.0:
				_hand_wait[player_id] = tuning.fuel_interval
				buy(player_id, target["item"])


## The revive channel (for tests and the picture): `progress(target_id)`, `is_reviving(player_id)`.
func revive() -> ReviveChannel:
	return _revive


## A player marks something (`ping` {kind, pos, subject}); the answer is `&""` when the mark went
## up, else why not (`PingJudge`).
func ping(player_id: int, action: Dictionary) -> StringName:
	return _ping_judge.place(player_id, action)


## A bot calls out a line (`say`): everyone hears a `bot_say` when `SayBoard` lets it through.
func say(player_id: int, action: Dictionary) -> bool:
	var event := say_board.from_action(player_id, action) if _bodies.has(player_id) else {}
	if not event.is_empty():
		_outbox.append(event)
	return not event.is_empty()


## One board back if this hand is free: the first at the press, then one every `repair_interval`.
func _repair(player_id: int, breach: StringName) -> void:
	if _hand_wait[player_id] <= 0.0:
		_hand_wait[player_id] = tuning.repair_interval
		rules.apply(RulesAction.repair(player_id, breach))
		_facing_breach[player_id] = breach
		_face_left[player_id] = tuning.repair_interval


## Turns the body toward the breach it is putting boards back across, at the body's own turn speed,
## for an interval after each board.
func _face_breach(player_id: int, delta: float) -> void:
	var left: float = _face_left.get(player_id, 0.0)
	if left <= 0.0:
		return
	_face_left[player_id] = left - delta
	var body := _bodies[player_id]
	var to := world.barricade(_facing_breach[player_id]).global_position - body.global_position
	if Vector2(to.x, to.z).length() < 0.01:
		return
	body.state.facing = rotate_toward(
		body.state.facing, atan2(-to.x, -to.z), body.tuning.turn_speed * delta
	)


## The held `use`: goes on with the breach the press began at while the button stays down and the
## player is still in reach of it with a board missing; anything else lets go, and the next board
## needs a new press. (The pay and the cap are the rules': this only paces the boards.)
func _hold_repair(player_id: int, command: NightCommand) -> void:
	var breach := _repairing[player_id]
	if breach == &"":
		return
	var target := use_target(player_id) if command.use_held and tuning.repair_hold else {}
	if target.get("kind") != &"repair" or target["id"] != breach:
		_repairing[player_id] = &""
		return
	_repair(player_id, breach)


## Whether this player's held `use` is putting boards back now (for tests and the picture).
func is_repairing(player_id: int) -> bool:
	return _repairing.get(player_id, &"") != &""


# --- The picture clients draw ---


func _frame() -> Dictionary:
	var players := {}
	for player_id in _bodies:
		var body := _bodies[player_id]
		var weapon := combat.weapon_of(player_id)
		players[player_id] = {
			"pos": body.global_position,
			"facing": body.state.facing,
			"health": rules.health_of(player_id),
			"downed": _is_downed(player_id),
			"weapon": weapon.def.id if weapon != null else &"",
			"aim": body.state.holds_aim(body.tuning.hip_fire_hold),
			"pitch": pitch_step(body.state.view_pitch),
			"stance": PlayerStance.pack(body.state),
			"ammo": weapon.ammo if weapon != null else 0,
			"reserve": weapon.reserve if weapon != null else 0,
			"reloading": weapon != null and weapon.is_reloading(),
			"arms": _arms_of(player_id),
			"points": rules.points_of(player_id),
			# A player on the ground can use nothing, so the card says nothing.
			"prompt": {} if _is_downed(player_id) else use_target(player_id),
			"ack": _acked.get(player_id, 0),
			"reviving": _revive.target_of(player_id),
			"revive": _revive.progress(player_id),
			"reviver": _revive.holder_of(player_id),
			"kills": rules.kills_of(player_id),
			"downs": rules.downs_of(player_id),
			"revives": rules.revives_of(player_id),
			"dead": rules.is_dead(player_id),
			"bleed": rules.bleed_left_of(player_id),
		}
		if pings.has(player_id):
			players[player_id]["ping"] = pings[player_id]
		if _face_left.get(player_id, 0.0) > 0.0:
			# The server is turning this body (toward a breach it is repairing); its owner's
			# predicted body takes that facing (it cannot know, the turn is not in any command).
			players[player_id]["turn"] = true
	return {
		"type": &"frame",
		"tick": tick_count,
		"phase": rules.phase,
		"round": rules.round_number,
		"remaining": rules.zombies_remaining(),
		"clock": floori(rules.night_time),
		"fuel": rules.generator.fuel,
		"circuits": rules.generator.circuits.duplicate(),
		"doors": rules.doors_open.duplicate(),
		"crane": _crane_frame(),
		"pings": ping_board.marks(),
		BotOrders.FRAME_KEY: bot_orders.to_frame(),
		"barricades": rules.barricades.to_dict(),
		"zombies": _encode_zombies(),
		"players": players,
	}


func _encode_zombies() -> PackedByteArray:
	var began := PerfProbe.begin()
	var bytes := ZombieCodec.encode(sim.zombies)
	PerfProbe.end(&"server.encode", began)
	return bytes


## The crane for the picture: where it stands, which stage it is in, whose play it is, the prize
## held out (a shop id) and the seconds left in the stage.
func _crane_frame() -> Dictionary:
	var crane := rules.crane
	return {
		"spot": crane.spot,
		"stage": crane.stage,
		"buyer": crane.buyer_id,
		"weapon": crane.weapon,
		"left": crane.left,
	}


## Every weapon the player carries: its id to [ammo in the magazine, rounds in reserve].
func _arms_of(player_id: int) -> Dictionary:
	var arms := {}
	for weapon_id: StringName in combat.carried(player_id):
		var state := combat.state_of(player_id, weapon_id)
		arms[weapon_id] = [state.ammo, state.reserve, state.tier()]
	return arms


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
