class_name Night
extends Node3D
## One playable night on the drive-in lot, for one player, run as a server and a client in this
## process, joined by a loopback link (`docs/design/networking.md`). Each physics tick: the link
## delivers what the client sent and what the server answered last tick, the server steps, and the
## client reads its controls (or the autopilot decides) and sends the next `NightCommand`.
##
## The server owns the rules, the zombies, the weapons and the bodies; the client state and the
## view are made from events only. In this single-process shortcut the world and the players'
## bodies are one scene shared by both; with a second machine the bodies split into server bodies
## and drawn avatars.

signal ready_to_play
signal night_over(round_reached: int)
## After every tick of the night, whatever drove it.
signal ticked

## MANUAL makes no commands: the caller sends them through `link` (the tests do).
enum Mode { HUMAN, AUTOPILOT, MANUAL }

## The fixed step of the night, the physics step.
const STEP := 1.0 / 60.0
const PLAYER_ID := 1
const SEED := 1958
const SPECTATOR_OFFSET := Vector3(0.0, 11.0, 8.0)
## How far past the low-tank line (a fraction of a full tank) the bot waits before it lights an
## area again.
const SWITCH_RESUME_MARGIN := 0.15

var mode := Mode.HUMAN
var world: NightWorld
var server: NightServer
var link: LoopbackLink
var state: ClientState
## Every player's look and seat as this client heard them from the server; the bodies are dressed
## from it.
var looks := LookRegistry.new()
## The look the local player sends on join, set before `start`; without one, the look saved in the
## wardrobe (`LookStore`).
var own_look: CharacterLook
var view: NightView
var autopilot: Autopilot
## The HUD to feed, set before `start`: it hears the night from its first event.
var hud: Hud
## Ticks run in each physics frame: 1 is real time; a test turns it up to play faster.
## (Engine.time_scale would scale the step itself, which is not the same night.)
var ticks_per_frame := 1
## Autopilot only: film the bot through its own shoulder camera, as a player sees it.
var shoulder_camera := false
## False before the night starts, while paused and after it is over.
var running := false

var _human := HumanController.new()
var _spectator: Camera3D
## Held here: a Callable does not keep its RefCounted alive.
var _sight: WorldProbe
var _hud_binding: NightHudBinding
var _paused := false


## Builds the lot and the server, joins the player, and starts the night.
func start(
	p_mode: Mode = Mode.HUMAN, p_seed: int = SEED, p_rules_tuning: RulesTuning = null
) -> void:
	mode = p_mode
	world = NightWorld.new()
	add_child(world)
	await world.build()
	server = NightServer.new(world, p_seed, null, p_rules_tuning)
	link = LoopbackLink.new(server)
	state = ClientState.new()
	state.player_id = PLAYER_ID
	if hud != null:
		_hud_binding = NightHudBinding.new(hud, state, server, looks)
	link.delivered.connect(_on_delivered)
	looks.changed.connect(_dress_bodies)
	link.send({"type": NightServer.JOIN, "player_id": PLAYER_ID, "local": mode == Mode.HUMAN})
	var wanted := own_look if own_look != null else LookStore.load_look()
	link.send({"type": NightServer.LOOK, "player_id": PLAYER_ID, "packet": LookWire.look(wanted)})
	link.send({"type": NightServer.START_NIGHT})
	link.pump()
	var player := server.body_of(PLAYER_ID)
	var camera := player.camera_rig.camera()
	if mode == Mode.AUTOPILOT and shoulder_camera:
		camera.make_current()
		_make_autopilot()
	elif mode == Mode.AUTOPILOT:
		_spectator = Camera3D.new()
		_spectator.fov = 60.0
		add_child(_spectator)
		_spectator.make_current()
		camera = _spectator
		_make_autopilot()
	view = NightView.new()
	add_child(view)
	view.setup(state, camera, _telegraphs(), _board_seconds())
	view.barricade_points = _barricade_points()
	view.show_lamps(world.greybox, server.rules.tuning.fuel)
	_add_sounds()
	view.hear(world)
	night_over.connect(func(_r: int) -> void: running = false)
	state.event_received.connect(_on_event)
	running = true
	ready_to_play.emit()


## The guns, the grenades and the lot's machines and shop sound from the same events as the view.
func _add_sounds() -> void:
	var weapons := WeaponSounds.new()
	weapons.name = "WeaponSounds"
	add_child(weapons)
	weapons.setup(state)
	var grenades := GrenadeSounds.new()
	grenades.name = "GrenadeSounds"
	add_child(grenades)
	grenades.setup(state)
	var lot := WorldSounds.new()
	lot.name = "WorldSounds"
	add_child(lot)
	var tuning: RulesTuning = server.rules.tuning
	var generator := world.greybox.get_node_or_null("GeneratorYard/Generator") as Node3D
	lot.setup(state, tuning.fuel, tuning.economy, generator, _post_point, _crane_point)


## Where the prize crane stands at `spot` (the rules' list of crane places), or null.
func _crane_point(spot: int) -> Variant:
	for place in world.shop_spots():
		if place["kind"] == &"crane" and place["crane_spot"] == spot:
			return place["position"]
	return null


## Where a circuit's breaker post stands, or null.
func _post_point(circuit_id: StringName) -> Variant:
	var post := world.switches.post(circuit_id)
	return post.global_position if post != null else null


## Seconds each look's blow takes to land, for the looks of the types that telegraph it.
func _telegraphs() -> Dictionary[StringName, float]:
	var telegraphs: Dictionary[StringName, float] = {}
	for type in server.rules.tuning.roster.types:
		if type.telegraph_seconds > 0.0:
			for look in type.looks:
				telegraphs[look] = type.telegraph_seconds
	return telegraphs


## Seconds each look's type takes to pull one board off, for its tear clip (`ZombieView`).
func _board_seconds() -> Dictionary[StringName, float]:
	var seconds: Dictionary[StringName, float] = {}
	var per_board := server.rules.tuning.barricades.seconds_per_board
	for type in server.rules.tuning.roster.types:
		if type.barrier_speed > 0.0:
			for look in type.looks:
				seconds[look] = per_board / type.barrier_speed
	return seconds


## Where each breach's boards stand, for the effects of tearing and mending them.
func _barricade_points() -> Dictionary[StringName, Vector3]:
	var points: Dictionary[StringName, Vector3] = {}
	for id in world.barricade_ids():
		points[id] = world.barricade(id).centre()
	return points


func player() -> Player:
	return server.body_of(PLAYER_ID)


func is_paused() -> bool:
	return _paused


## Freezes the night and frees the mouse, or resumes.
func set_paused(paused: bool) -> void:
	_paused = paused
	running = not paused and not state.over
	if mode == Mode.HUMAN and player() != null:
		player().set_controls_enabled(not paused)


func _exit_tree() -> void:
	if server != null:
		server.close()
	if mode == Mode.HUMAN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(_delta: float) -> void:
	for _i in ticks_per_frame:
		if not running:
			return
		tick()


## One fixed tick of the night.
func tick() -> void:
	link.pump()
	link.broadcast(server.step(STEP))
	match mode:
		Mode.AUTOPILOT:
			var command := autopilot.decide(STEP)
			if shoulder_camera:
				_aim_rig(command)
			link.send(command.to_dict())
		Mode.HUMAN:
			link.send(_human_command().to_dict())
	if mode == Mode.AUTOPILOT:
		_follow(STEP)
	ticked.emit()


func _human_command() -> NightCommand:
	return _human.command(player(), PLAYER_ID)


## What the server answered: the look server's packets go to the look table, the rest to the
## client's state.
func _on_delivered(events: Array) -> void:
	var rest := []
	for event: Dictionary in events:
		if event["type"] == NightServer.LOOK_PACKET:
			if event["to"] == PLAYER_ID:
				looks.receive(event["packet"])
		else:
			rest.append(event)
	state.apply_events(rest)


## A look arrived or changed: every body of this process wears what the table says (a lookalike
## has its main colour moved on, so a change of one look can change another's).
func _dress_bodies(_player_id: int) -> void:
	var resolved := looks.resolved()
	for id: int in resolved:
		var body := server.body_of(id)
		if body != null:
			body.dress(resolved[id], looks.seats[id])


func _on_event(event: Dictionary) -> void:
	if event["type"] == &"game_over":
		night_over.emit(event["round_reached"])
	elif event["type"] == &"board_repaired":
		_show_repair(event["player_id"])


## The player who put a board back hammers it home: the repair clip lands on this event.
func _show_repair(player_id: int) -> void:
	var body := server.body_of(player_id)
	var animation := body.get_node_or_null(^"AnimationTree") as PlayerAnimation if body else null
	if animation != null:
		animation.board_repaired(server.tuning.repair_interval)


func _make_autopilot() -> void:
	autopilot = Autopilot.new(state, world.map())
	_sight = WorldProbe.new(get_world_3d().direct_space_state)
	autopilot.sight = _sight.callable()
	var tuning: RulesTuning = server.rules.tuning
	for item in tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			autopilot.prices[item.id] = item.price
			autopilot.order.append(item.id)
	autopilot.spots = world.shop_spots()
	for item in tuning.economy.items:
		match item.kind:
			ShopItem.Kind.WEAPON, ShopItem.Kind.CRANE:
				autopilot.prices_of_goods[item.id] = item.price
				autopilot.wanted.append(item.id)
				if item.kind == ShopItem.Kind.CRANE:
					autopilot.crane_pool.assign(item.pool)
			ShopItem.Kind.AMMO:
				autopilot.ammo_prices[item.weapon] = item.price
	autopilot.wanted.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			return autopilot.prices_of_goods[a] < autopilot.prices_of_goods[b]
	)
	autopilot.whole_boards = tuning.barricades.boards
	autopilot.switches.capacity = tuning.fuel.capacity
	autopilot.switches.save_below = tuning.fuel.low_fraction
	autopilot.switches.resume_above = tuning.fuel.low_fraction + SWITCH_RESUME_MARGIN
	for circuit_id in world.switches.circuit_ids():
		autopilot.switches.goals[circuit_id] = world.switches.standing_point(circuit_id)
		autopilot.switches.doors[circuit_id] = world.switches.door_of(circuit_id)
	autopilot.fuel.capacity = tuning.fuel.capacity
	autopilot.fuel.refuel_at = tuning.fuel.low_fraction
	autopilot.fuel.fill_to = tuning.fuel.low_fraction + SWITCH_RESUME_MARGIN
	for item in tuning.economy.items:
		if item.kind == ShopItem.Kind.FUEL:
			autopilot.fuel.item = item
	for id in world.fuel.ids():
		autopilot.fuel.goals[id] = world.fuel.standing_point(id)
		autopilot.fuel.doors[id] = world.fuel.door_of(id)
	for id in world.barricade_ids():
		autopilot.repair_goals[id] = world.repair_spot(id)
	for door_id in autopilot.order:
		var points := world.door_points(door_id)
		if not points.is_empty():
			autopilot.door_goals[door_id] = points[0]


## The shoulder camera looks where the bot looks: the bot's yaw arrives in steps, and the rig
## turns toward it with its own spring (`PlayerTuning.steer_frequency`), as it follows a player.
func _aim_rig(command: NightCommand) -> void:
	var pitch := 0.0
	if command.fire:
		pitch = asin(clampf(command.dir.y, -1.0, 1.0))
	player().camera_rig.steer(command.motion.yaw, pitch)


## The bot's camera stays above and behind it, so a recording reads.
func _follow(_delta: float) -> void:
	if _spectator == null or not state.has_frame():
		return
	var at := state.position()
	_spectator.look_at_from_position(at + SPECTATOR_OFFSET, at + Vector3(0.0, 1.0, -3.0))
