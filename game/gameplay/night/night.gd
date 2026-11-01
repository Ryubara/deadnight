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
## How far the night has got in getting ready (0 to 1) and what it is doing, for a loading screen.
signal loading(fraction: float, text: String)
signal night_over(round_reached: int)
## After every tick of the night, whatever drove it.
signal ticked

## MANUAL makes no commands: the caller sends them through `link` (the tests do).
enum Mode { HUMAN, AUTOPILOT, MANUAL }

## Share of the loading bar the lot's own build takes, before the warm-up starts.
const BUILD_SHARE := 0.15
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
## Draw and load everything the night uses once before it starts (`NightWarmup`), behind a loading
## screen. The game turns it on; a test that needs no pictures leaves it off, which saves seconds.
var warm_up := false
## The warm-up, once it ran: it holds what it loaded for as long as the night lasts.
var warmup: NightWarmup

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
	loading.emit(0.0, "Building the lot")
	if warm_up:
		# The build takes the main thread for seconds: let the loading screen be drawn first.
		await get_tree().process_frame
		await get_tree().process_frame
	world = NightWorld.new()
	add_child(world)
	await world.build()
	loading.emit(BUILD_SHARE, "Setting up")
	server = NightServer.new(world, p_seed, null, p_rules_tuning)
	link = LoopbackLink.new(server)
	state = ClientState.new()
	state.player_id = PLAYER_ID
	if hud != null:
		_hud_binding = NightHudBinding.new(hud, state, server)
	link.delivered.connect(state.apply_events)
	link.send({"type": NightServer.JOIN, "player_id": PLAYER_ID, "local": mode == Mode.HUMAN})
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
	view.hear(world)
	night_over.connect(func(_r: int) -> void: running = false)
	state.event_received.connect(_on_event)
	if warm_up:
		warmup = NightWarmup.new()
		add_child(warmup)
		warmup.progress.connect(
			func(fraction: float, text: String) -> void:
				loading.emit(lerpf(BUILD_SHARE, 1.0, fraction), text)
		)
		await warmup.run(self)
	running = true
	ready_to_play.emit()


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
