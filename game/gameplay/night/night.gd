class_name Night
extends Node3D
## One playable night on the drive-in lot. `start` runs it for one player as a server and a client
## in this process, joined by a loopback link (`docs/design/networking.md`). Each physics tick: the
## link delivers what the client sent and what the server answered last tick, the server steps, and
## the client reads its controls (or the autopilot decides) and sends the next `NightCommand`.
## `start_remote` joins a night on a game server instead (`docs/research/testing-multiplayer.md`):
## the same client over a `WebSocketLink`, with no server here.
##
## The server owns the rules, the zombies, the weapons and the bodies; the client state and the
## view are made from events only. In the single-process shortcut the world and the players'
## bodies are one scene shared by both. Online, this machine has its own copy of the lot: a human's
## own body moves here at once and the server corrects it (`Reconciler`), and the other players are
## `RemoteAvatars` drawn from frames.

signal ready_to_play
## How far the night has got in getting ready (0 to 1) and what it is doing, for a loading screen.
signal loading(fraction: float, text: String)
signal night_over(round_reached: int)
## `start_remote` could not join: why, in words for the player.
signal connect_failed(reason: String)
## After every tick of the night, whatever drove it.
signal ticked
## A game-server night lost its socket and is trying to get the seat back; it did; it could not
## (the time ran out, or the server gave the seat away). The night is the server's and goes on
## meanwhile; this client's player stands still until it is back.
signal connection_lost
signal connection_resumed
signal connection_ended

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
## The server's events that move the Soldier's grenade clips.
const GRENADE_CLIP_EVENTS: Array[StringName] = [
	&"cook_started", &"throw_started", &"grenade_dropped", &"grenade_exploded"
]

var mode := Mode.HUMAN
var world: NightWorld
var server: NightServer
var link: GameLink
## The rules' numbers the client needs (the server's own, or the shipped table online).
var rules_tuning: RulesTuning
## True when the night runs on a game server (`start_remote`).
var remote := false
## Online: the other players, drawn from frames.
var avatars: RemoteAvatars
## Online: how far the server's answers have disagreed with this client's own body.
var reconciler := Reconciler.new()
var state: ClientState
## Every player's look and seat as this client heard them from the server; the bodies are dressed
## from it.
var looks := LookRegistry.new()
## The look the local player sends on join, set before `start`; without one, the look saved in the
## wardrobe (`LookStore`).
var own_look: CharacterLook
var view: NightView
## Where the grenade in the local player's hand would go (`show_throw`).
var preview: GrenadePreview
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
## Held here: a Callable does not keep its RefCounted alive.
var _throw_cast: WorldCast
var _spectator: Camera3D
## Online with a human: the body this client moves itself.
var _body: Player
var _mirror: WorldMirror
var _seq := 0
var _repair_interval := NightTuning.new().repair_interval
## Held here: a Callable does not keep its RefCounted alive.
var _sight: WorldProbe
var _hud_binding: NightHudBinding
## Held here: it listens to the client state and nothing else keeps it alive.
var _equip_sync: WeaponEquipSync
var _paused := false
## True while the warm-up runs.
var _warming := false


func _init() -> void:
	# The night hangs under a screen, and a Control is not physics-interpolated: left to inherit,
	# the whole lot and everyone on it would be drawn at the last tick (issues #344 and #353).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON


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
	rules_tuning = server.rules.tuning
	link = LoopbackLink.new(server, 0, PLAYER_ID)
	state = ClientState.new()
	state.player_id = PLAYER_ID
	if hud != null:
		_hud_binding = NightHudBinding.new(hud, state, rules_tuning, looks)
	_equip_sync = WeaponEquipSync.new(state, server.body_of)
	link.delivered.connect(_on_delivered)
	looks.changed.connect(_dress_bodies)
	link.send({"type": NightServer.JOIN, "player_id": PLAYER_ID, "local": mode == Mode.HUMAN})
	link.send(
		{"type": NightServer.LOOK, "player_id": PLAYER_ID, "packet": LookWire.look(_wanted_look())}
	)
	link.send({"type": NightServer.START_NIGHT})
	link.pump()
	var player := server.body_of(PLAYER_ID)
	var camera := player.camera_rig.camera()
	if mode == Mode.AUTOPILOT and shoulder_camera:
		camera.make_current()
		_make_autopilot()
	elif mode == Mode.AUTOPILOT:
		camera = _make_spectator()
		_make_autopilot()
	_build_view(camera)
	await _go()


## Joins the night of a game server at `url` (`ws://host:port`): builds the lot, connects, and
## starts once the server has welcomed us and sent its first frame. Returns false, after
## `connect_failed`, when it could not (nothing there, the server full or of another version, or no
## answer within `seconds`). `p_link` is the connection to use (a new `WebSocketLink` by default).
## The night is the server's: it began when the first player came, and goes on whatever this
## client does, including pausing.
func start_remote(
	url: String, p_mode: Mode = Mode.HUMAN, seconds: float = 10.0, p_link: WebSocketLink = null
) -> bool:
	mode = p_mode
	remote = true
	world = NightWorld.new()
	add_child(world)
	await world.build()
	rules_tuning = load(GameRules.DEFAULT_TUNING_PATH)
	var online := p_link if p_link != null else WebSocketLink.new()
	link = online
	state = ClientState.new()
	var failure := {"reason": ""}
	var welcome := {}
	online.welcomed.connect(func(snapshot: Dictionary) -> void: welcome["snapshot"] = snapshot)
	online.refused.connect(func(why: int) -> void: failure["reason"] = _refusal_text(why))
	online.closed.connect(func() -> void: failure["reason"] = "The server closed the connection.")
	# Until the view exists, what the server says waits here.
	var early: Array = []
	var keep := func(events: Array) -> void: early.append_array(events)
	online.delivered.connect(keep)
	var started := online.connect_to(url)
	if started != OK:
		return _fail("Not a server address: %s" % url)
	var began := Time.get_ticks_msec()
	while failure["reason"] == "" and not (welcome.has("snapshot") and _has_frame(early)):
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			failure["reason"] = "No answer from %s." % url
			break
		online.pump()
		await get_tree().physics_frame
	if failure["reason"] != "":
		online.close()
		return _fail(failure["reason"])
	state.player_id = online.player_id
	var camera: Camera3D
	var has_body := mode == Mode.HUMAN or (mode == Mode.AUTOPILOT and shoulder_camera)
	if has_body:
		var spawn: Vector3 = _last_frame(early)["players"][state.player_id]["pos"]
		_body = world.add_body(spawn, mode == Mode.HUMAN)
		camera = _body.camera_rig.camera()
		if mode == Mode.AUTOPILOT:
			camera.make_current()
	else:
		camera = _make_spectator()
	if mode == Mode.AUTOPILOT:
		_make_autopilot()
	if hud != null:
		_hud_binding = NightHudBinding.new(hud, state, rules_tuning, looks)
		hud.state.load_snapshot(welcome["snapshot"])
	# Our own body holds what the server says; the drawn avatars of the others are not `Player`s.
	_equip_sync = WeaponEquipSync.new(state, _body_of)
	online.delivered.disconnect(keep)
	_build_view(camera)
	view.step = Night.STEP * NightHost.SEND_EVERY
	_mirror = WorldMirror.new(world, view)
	avatars = RemoteAvatars.new()
	add_child(avatars)
	avatars.setup(looks, state.player_id if has_body else 0, Night.STEP)
	online.delivered.connect(_on_delivered)
	state.event_received.connect(_on_remote_event)
	online.lost.connect(func() -> void: connection_lost.emit())
	online.resumed.connect(_on_resumed)
	online.closed.connect(func() -> void: connection_ended.emit())
	looks.changed.connect(_dress_bodies)
	online.send({"type": NightServer.LOOK, "packet": LookWire.look(_wanted_look())})
	_on_delivered(early)
	await _go()
	return true


func _fail(reason: String) -> bool:
	connect_failed.emit(reason)
	return false


func _refusal_text(reason: int) -> String:
	match reason:
		NetWire.Refusal.FULL:
			return "The night is full."
		NetWire.Refusal.VERSION:
			return _version_text(
				(link as WebSocketLink).server_version if link is WebSocketLink else 0
			)
		NetWire.Refusal.DENIED:
			return "The server did not let us in."
	return "The server turned us away."


## Which side is behind: a server that speaks a newer version means this page is out of date.
func _version_text(server_version: int) -> String:
	if server_version > NetWire.VERSION:
		return "This game is out of date. Reload the page to update it."
	if server_version > 0:
		return "The server is older than this game (it speaks version %d)." % server_version
	return "The server speaks another version of the game."


func _has_frame(events: Array) -> bool:
	return not _last_frame(events).is_empty()


func _last_frame(events: Array) -> Dictionary:
	for i in range(events.size() - 1, -1, -1):
		if events[i].get("type") == &"frame":
			return events[i]
	return {}


## The view and the sounds, once there is a camera to look through.
func _build_view(camera: Camera3D) -> void:
	view = NightView.new()
	add_child(view)
	view.setup(state, camera, _telegraphs(), _board_seconds())
	view.barricade_points = _barricade_points()
	view.bodies = _body_of
	view.repair_interval = _repair_seconds
	view.show_lamps(world.greybox, rules_tuning.fuel)
	view.show_crane(world, rules_tuning)
	view.show_grenades(load(NightServer.GRENADE_DEF) as GrenadeDef)
	_add_throw_preview(load(NightServer.GRENADE_DEF) as GrenadeDef)
	add_child(NightLight.new(world.greybox.get_node("Lighting"), rules_tuning.rounds, state))
	_add_sounds()
	view.hear(world)
	night_over.connect(func(_r: int) -> void: running = false)
	state.event_received.connect(_on_event)


## The warm-up (when asked for), then the first tick. A client on a game server goes on reading
## what the server says meanwhile (`_physics_process`), so nothing piles up behind the loading
## screen.
func _go() -> void:
	if warm_up:
		_warming = true
		warmup = NightWarmup.new()
		add_child(warmup)
		warmup.progress.connect(
			func(fraction: float, text: String) -> void:
				loading.emit(lerpf(BUILD_SHARE, 1.0, fraction), text)
		)
		await warmup.run(self)
		_warming = false
	running = true
	ready_to_play.emit()


## The look this client wears: the one a test or `--look` set, else the saved one.
func _wanted_look() -> CharacterLook:
	return own_look if own_look != null else LookStore.load_look()


func _make_spectator() -> Camera3D:
	_spectator = Camera3D.new()
	_spectator.fov = 60.0
	add_child(_spectator)
	_spectator.make_current()
	return _spectator


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
	var tuning: RulesTuning = rules_tuning
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
	for type in rules_tuning.roster.types:
		if type.telegraph_seconds > 0.0:
			for look in type.looks:
				telegraphs[look] = type.telegraph_seconds
	return telegraphs


## Seconds each look's type takes to pull one board off, for its tear clip (`ZombieView`).
func _board_seconds() -> Dictionary[StringName, float]:
	var seconds: Dictionary[StringName, float] = {}
	var per_board := rules_tuning.barricades.seconds_per_board
	for type in rules_tuning.roster.types:
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


## The body this client moves: the shared one in the single-process night, its own copy online
## (null for an autopilot or a hand-driven client, which have no body of their own).
func player() -> Player:
	if remote:
		return _body
	return server.body_of(PLAYER_ID)


func is_paused() -> bool:
	return _paused


## Freezes the night and frees the mouse, or resumes.
func set_paused(paused: bool) -> void:
	_paused = paused
	# Online the night goes on without us: the link keeps being read and the body stands still.
	running = (remote or not paused) and not state.over
	if mode == Mode.HUMAN and player() != null:
		player().set_controls_enabled(not paused)


func _exit_tree() -> void:
	running = false
	if server != null:
		server.close()
	if remote and link != null:
		link.close()
	if mode == Mode.HUMAN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(_delta: float) -> void:
	if _warming and remote:
		link.pump()
	for _i in ticks_per_frame:
		if not running:
			return
		tick()


## One fixed tick of the night.
func tick() -> void:
	if remote:
		_tick_remote()
		return
	link.pump()
	link.broadcast(server.step(STEP))
	match mode:
		Mode.AUTOPILOT:
			var command := autopilot.decide(STEP)
			if shoulder_camera:
				_aim_rig(command)
			link.send(command.to_dict())
		Mode.HUMAN:
			var human := _human_command()
			show_throw(human)
			link.send(human.to_dict())
	if mode == Mode.AUTOPILOT:
		_follow(STEP)
	ticked.emit()


## One fixed tick of a client on a game server: read what arrived, move the body we own (the
## server will check it), and send the next command.
func _tick_remote() -> void:
	link.pump()
	if not link.is_open():
		# The socket is down: nothing to send, and the body waits where it is until the server's
		# answer comes back.
		if _body == null:
			_follow(STEP)
		ticked.emit()
		return
	var command: NightCommand = null
	match mode:
		Mode.HUMAN:
			command = _human_command()
			show_throw(command)
		Mode.AUTOPILOT:
			command = autopilot.decide(STEP)
			if _body != null:
				_aim_rig(command)
	if command != null:
		# The body moves with the command as the server will read it, not as it was sampled.
		command = NetWire.quantize(command)
		if _body != null:
			_body.tick(command.motion)
		_seq += 1
		command.seq = _seq
		command.player_id = state.player_id
		if _body != null:
			reconciler.record(_seq, _body.state.position)
		link.send(command.to_dict())
	if _body == null:
		_follow(STEP)
	ticked.emit()


## The seat is ours again: the rules as the server has them now, in place of the events missed.
func _on_resumed(snapshot: Dictionary) -> void:
	if hud != null:
		hud.state.load_snapshot(snapshot)
	connection_resumed.emit()


## A frame from the server: the lot, the other players, and our own body's correction.
func _on_remote_event(event: Dictionary) -> void:
	if event["type"] != &"frame":
		return
	_mirror.follow(event)
	avatars.apply_frame(event)
	var me: Dictionary = event["players"].get(state.player_id, {})
	if _body == null or me.is_empty():
		return
	var shift := reconciler.correction(me["ack"], me["pos"])
	if shift != Vector3.ZERO:
		_body.state.position += shift
		PlayerSimulation.restore(_body, _body.state, get_physics_process_delta_time())


## Shows, for the command the local player is about to send, where the grenade they are holding
## would go if they let go now; nothing when no grenade button is held.
func show_throw(command: NightCommand) -> void:
	preview.follow(command, player(), STEP, state.me().get("downed", false))


func _add_throw_preview(def: GrenadeDef) -> void:
	preview = GrenadePreview.new()
	preview.name = "GrenadePreview"
	add_child(preview)
	_throw_cast = WorldCast.new(get_world_3d().direct_space_state)
	preview.setup(def, _throw_cast.callable())
	var night_tuning: NightTuning = server.tuning if server != null else NightTuning.new()
	preview.hand_reach = night_tuning.grenade_hand_reach
	preview.release_over = night_tuning.grenade_release_over
	preview.release_under = night_tuning.grenade_release_under


func _human_command() -> NightCommand:
	return _human.command(player(), state.player_id)


## What the server answered: the look server's packets go to the look table, the rest to the
## client's state.
func _on_delivered(events: Array) -> void:
	var rest := []
	for event: Dictionary in events:
		if event["type"] == NightServer.LOOK_PACKET:
			if event["to"] == state.player_id:
				looks.receive(event["packet"])
		else:
			rest.append(event)
	state.apply_events(rest)


## A look arrived or changed: every body of this process wears what the table says (a lookalike
## has its main colour moved on, so a change of one look can change another's).
func _dress_bodies(_player_id: int) -> void:
	var resolved := looks.resolved()
	for id: int in resolved:
		var body := _body_of(id)
		if body != null:
			body.dress(resolved[id], looks.seats[id])


## The body of a player in this process: the server's, or (online) our own.
func _body_of(player_id: int) -> Player:
	if remote:
		return _body if player_id == state.player_id else null
	return server.body_of(player_id)


func _on_event(event: Dictionary) -> void:
	if (
		preview != null
		and event["type"] == &"grenade_count_changed"
		and event["player_id"] == state.player_id
	):
		preview.grenades_left = event["count"]
	if event["type"] == &"game_over":
		night_over.emit(event["round_reached"])
	else:
		_show_grenade(event)


## The Soldier's grenade clips follow the server's events: the pin, the throw, a grenade that went
## off or was dropped in the hand.
func _show_grenade(event: Dictionary) -> void:
	if not GRENADE_CLIP_EVENTS.has(event["type"]):
		return
	var animation := _animation_of(event.get("player_id", event.get("thrower_id", -1)))
	if animation == null:
		return
	match event["type"]:
		&"cook_started":
			animation.grenade(&"cook")
		&"throw_started":
			animation.grenade(&"throw", event["underarm"])
		&"grenade_dropped":
			animation.grenade(&"gone")
		&"grenade_exploded":
			if event["in_hand"]:
				animation.grenade(&"gone")


func _animation_of(player_id: int) -> PlayerAnimation:
	var body := _body_of(player_id)
	return body.get_node_or_null(^"AnimationTree") as PlayerAnimation if body else null


## The seconds between boards: the server's in this process, else the shared default.
func _repair_seconds() -> float:
	return server.tuning.repair_interval if server != null else _repair_interval


func _make_autopilot() -> void:
	autopilot = Autopilot.new(state, world.map())
	_sight = WorldProbe.new(get_world_3d().direct_space_state)
	autopilot.sight = _sight.callable()
	var tuning: RulesTuning = rules_tuning
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
