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
		_hud_binding = NightHudBinding.new(hud, state, server)
	link.delivered.connect(state.apply_events)
	link.send({"type": NightServer.JOIN, "player_id": PLAYER_ID, "local": mode == Mode.HUMAN})
	link.send({"type": NightServer.START_NIGHT})
	link.pump()
	var player := server.body_of(PLAYER_ID)
	var camera := player.camera_rig.camera()
	if mode == Mode.AUTOPILOT:
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
	night_over.connect(func(_r: int) -> void: running = false)
	state.event_received.connect(_on_event)
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
			link.send(autopilot.decide(STEP).to_dict())
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
	autopilot.whole_boards = tuning.barricades.boards
	for id in world.barricade_ids():
		autopilot.repair_goals[id] = world.repair_spot(id)
	for door_id in autopilot.order:
		var points := world.door_points(door_id)
		if not points.is_empty():
			autopilot.door_goals[door_id] = points[0]


## The bot's camera stays above and behind it, so a recording reads.
func _follow(_delta: float) -> void:
	if _spectator == null or not state.has_frame():
		return
	var at := state.position()
	_spectator.look_at_from_position(at + SPECTATOR_OFFSET, at + Vector3(0.0, 1.0, -3.0))
