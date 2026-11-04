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

## Sounds that may start in one frame during the night (`AudioService.starts_per_frame`): the
## frame of a kill starts six, and each costs about a millisecond in the browser.
const SOUND_STARTS_PER_FRAME := 2
## Share of the loading bar the lot's own build takes, before the warm-up starts.
const BUILD_SHARE := 0.15
## The fixed step of the night, the physics step.
const STEP := 1.0 / 60.0
const PLAYER_ID := 1
## The fixed seed of tests, benches and tours: a night that must play the same each time.
const SEED := 1958
## The server's events that move the Soldier's grenade clips.
const GRENADE_CLIP_EVENTS: Array[StringName] = [
	&"cook_started", &"throw_started", &"grenade_dropped", &"grenade_exploded"
]

## The server's events that move the Soldier's downed pose and kneel.
const REVIVE_CLIP_EVENTS: Array[StringName] = [
	&"player_downed", &"player_revived", &"revive_started", &"revive_stopped"
]

var mode := Mode.HUMAN
var world: NightWorld
var server: NightServer
var link: GameLink
## The person's word to the bots (`BotOrders`): its `issue` puts one order on the link, local or
## online, and the server's bots read it from every frame. Made with the link.
var bot_orders := BotOrders.new()
## The rules' numbers the client needs (the server's own, or the shipped table online).
var rules_tuning: RulesTuning
## True when the night runs on a game server (`start_remote`).
var remote := false
## Online: the other players, drawn from frames.
var avatars: RemoteAvatars
## Online: how far the server's answers have disagreed with this client's own body.
var reconciler := Reconciler.new()
## Watches for this client's own loop freezing (`StallGuard`).
var stalls := StallGuard.new()
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
## The bot host the autopilot runs on (`BotClient`, profile `BotProfile.autopilot()`): it decides
## with the autopilot every tick, as it always did, and counts what it sends.
var bot: BotClient
## The teammates the match settings asked for (`MatchSettings.bots`), seated beside the player at
## the start of a local night; null online, where the server seats them.
var bots: NightBots
## The match settings, set before `start`: the night's zombie intensity, alive cap and break. After
## `start_remote` they are the ones the server's WELCOME carried.
var match_settings := MatchSettings.new()
## The map's scene, set before `start`, for a night that is not on the registry's choice (a test, a
## capture); empty builds the map the match settings name (`NightWorld.scene`).
var scene: PackedScene
## `start_remote` only: the map to build before the server's WELCOME says which it is on (the lobby
## the player joined knows it); empty is the default map. A WELCOME that names another one has the
## world built again on that map.
var map_id := ""
## () -> bool, whether the touch layer is up, set by the screen that owns it. The touch player's
## aim help (`assist`) works only while it says yes.
var touch_active := Callable()
## The touch player's aim help, once the night has begun (a human's night only).
var assist: TouchAimAssist
## The HUD to feed, set before `start`: it hears the night from its first event.
var hud: Hud
## The player's challenges, set before `start` by the screen a person plays on (bots, captures and
## tests leave it empty, so they never touch the save). The night counts into it as it plays.
var challenge_board: ChallengeBoard
var challenges: ChallengeSession
## Puts the names and the next door on the HUD from the player's camera (made with the view, when
## there is a HUD).
var markers: NightMarkers
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
## The night's own numbers (hands, reach, the bot's camera): set before `start` to play another
## table; without one the shipped `night_tuning_default.tres` is read when the night starts.
var night_tuning: NightTuning

var _human := HumanController.new()
## Held here: a Callable does not keep its RefCounted alive.
var _throw_cast: WorldCast
var _spectator: Camera3D
## Online with a human: the body this client moves itself.
var _body: Player
var _mirror: WorldMirror
var _seq := 0
## Held here: a Callable does not keep its RefCounted alive.
var _sight: WorldProbe
var _hud_binding: NightHudBinding
## Held here: it listens to the session and the HUD, and nothing else keeps it alive.
var _challenge_link: ChallengeHudLink
## Held here: it listens to the client state and nothing else keeps it alive.
var _equip_sync: WeaponEquipSync
var _paused := false
## True while the warm-up runs.
var _warming := false
## The night is over on a game server and this client has left the seat: the link is read to the
## floor until its socket is closed (`_leave_server`).
var _leaving := false


## A seed for a night nobody asked to repeat: the dice of every stream (spawns, shop, crane) come
## from it. The game server draws its nights' seeds the same way (`NightHost`).
static func fresh_seed() -> int:
	return randi()


func _init() -> void:
	# The night hangs under a screen, and a Control is not physics-interpolated: left to inherit,
	# the whole lot and everyone on it would be drawn at the last tick (issues #344 and #353).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON


## Builds the lot and the server, joins the player, and starts the night.
func start(
	p_mode: Mode = Mode.HUMAN, p_seed: int = SEED, p_rules_tuning: RulesTuning = null
) -> void:
	mode = p_mode
	if night_tuning == null:
		night_tuning = NightTuning.shipped()
	loading.emit(0.0, "Building the lot")
	if warm_up:
		# The build takes the main thread for seconds: let the loading screen be drawn first.
		await get_tree().process_frame
		await get_tree().process_frame
	world = NightWorld.new()
	world.scene = scene
	add_child(world)
	await world.build(MapRegistry.of(match_settings.map))
	loading.emit(BUILD_SHARE, "Setting up")
	# A map with its own rules overlay plays by it, over the shared table (or over the table given).
	var table := p_rules_tuning if p_rules_tuning != null else load(GameRules.DEFAULT_TUNING_PATH)
	server = NightServer.new(world, p_seed, night_tuning, world.rules_for(table), match_settings)
	rules_tuning = server.rules.tuning
	link = LoopbackLink.new(server, 0, PLAYER_ID)
	bot_orders.sender = link.send
	state = ClientState.new()
	state.player_id = PLAYER_ID
	_track_challenges()
	if hud != null:
		_hud_binding = NightHudBinding.new(hud, state, rules_tuning, looks, world.layout.words())
	_equip_sync = WeaponEquipSync.new(state, server.body_of)
	link.delivered.connect(_on_delivered)
	looks.changed.connect(_dress_bodies)
	link.send({"type": NightServer.JOIN, "player_id": PLAYER_ID, "local": mode == Mode.HUMAN})
	link.send(
		{"type": NightServer.LOOK, "player_id": PLAYER_ID, "packet": LookWire.look(_wanted_look())}
	)
	link.send({"type": NightServer.START_NIGHT})
	link.pump()
	_seat_bots(p_seed)
	var player := server.body_of(PLAYER_ID)
	var camera := player.camera_rig.camera()
	if mode == Mode.AUTOPILOT and shoulder_camera:
		player.look_through()
		_make_autopilot()
	elif mode == Mode.AUTOPILOT:
		camera = _make_spectator()
		player.make_viewless()
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
	if night_tuning == null:
		night_tuning = NightTuning.shipped()
	world = NightWorld.new()
	add_child(world)
	await world.build(MapRegistry.of(map_id))
	rules_tuning = load(GameRules.DEFAULT_TUNING_PATH)
	var online := p_link if p_link != null else WebSocketLink.new()
	link = online
	bot_orders.sender = link.send
	state = ClientState.new()
	_track_challenges()
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
	await _use_map_of_server(MatchSettings.from_snapshot(welcome["snapshot"]).map)
	# The map's own rules overlay over the shared table, as the server plays it (#792): the cards, the
	# offers and the snapshot's tuning id all read it.
	rules_tuning = world.rules_for(load(GameRules.DEFAULT_TUNING_PATH))
	state.player_id = online.player_id
	state.load_names(welcome["snapshot"])
	var camera: Camera3D
	var has_body := mode == Mode.HUMAN or (mode == Mode.AUTOPILOT and shoulder_camera)
	if has_body:
		var spawn: Vector3 = _last_frame(early)["players"][state.player_id]["pos"]
		_body = world.add_body(spawn, mode == Mode.HUMAN)
		camera = _body.camera_rig.camera()
		if mode == Mode.AUTOPILOT:
			_body.look_through()
	else:
		camera = _make_spectator()
	if mode == Mode.AUTOPILOT:
		_make_autopilot()
	var open_doors: Array = welcome["snapshot"].get("doors_open", [])
	if hud != null:
		_hud_binding = NightHudBinding.new(hud, state, rules_tuning, looks, world.layout.words())
		hud.state.load_snapshot(welcome["snapshot"])
	match_settings = MatchSettings.from_snapshot(welcome["snapshot"])
	# Our own body holds what the server says; the drawn avatars of the others are not `Player`s.
	_equip_sync = WeaponEquipSync.new(state, _body_of)
	online.delivered.disconnect(keep)
	_build_view(camera)
	if markers != null:
		markers.load_doors(open_doors)
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


## The night the server welcomed us to is on the map `id`: when the world built before the WELCOME
## is another one (the player joined by an address, or a lobby that did not say), it is built again
## on the right one.
func _use_map_of_server(id: String) -> void:
	var wanted := MapRegistry.of(id)
	if world.map_info == wanted:
		return
	world.queue_free()
	world = NightWorld.new()
	add_child(world)
	await world.build(wanted)


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


## Counts the night into the player's challenges, when there is a board to count into.
func _track_challenges() -> void:
	if challenge_board != null:
		challenges = ChallengeSession.new(challenge_board, rules_tuning)
		challenges.attach(state)
		if hud != null:
			_challenge_link = ChallengeHudLink.new(challenges, hud)


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
	if hud != null:
		_add_markers()
	night_over.connect(_on_over)
	state.event_received.connect(_on_event)


## The night ended: the ticks stop. Online the client has nothing more to say or hear, so it
## leaves the seat at once (the server frees it) instead of leaving the socket unread, where a
## browser's buffer fills with snapshots ("Buffer payload full").
func _on_over(_round_reached: int) -> void:
	running = false
	if remote:
		_leave_server.call_deferred()


## Closes the link and drops what is still in flight: the night has ended, so frames that arrive
## now change nothing. `_physics_process` goes on reading until the socket has closed.
func _leave_server() -> void:
	if link == null or _leaving:
		return
	if link.delivered.is_connected(_on_delivered):
		link.delivered.disconnect(_on_delivered)
	_leaving = true
	link.close()


## The world markers of the HUD: the other players' names and the next door, projected through
## whichever camera is current; the damage numbers follow their hits the same way.
func _add_markers() -> void:
	markers = NightMarkers.new()
	markers.name = "NightMarkers"
	add_child(markers)
	markers.setup(hud.state, state, world, rules_tuning)
	markers.drawn = _drawn_player
	hud.crosshair.projector = markers.screen_of


## The node a player is drawn by on this client: their body here, or their avatar from the frames.
func _drawn_player(player_id: int) -> Node3D:
	if not remote:
		return server.body_of(player_id)
	if player_id == state.player_id and _body != null:
		return _body
	return avatars.avatar(player_id) if avatars != null else null


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
	# Only the game limits them: a test that needs no pictures hears every sound at once.
	Audio.starts_per_frame = SOUND_STARTS_PER_FRAME if warm_up else 0
	if mode == Mode.HUMAN:
		_make_assist()
	running = true
	ready_to_play.emit()


## The touch player's aim help, over the picture of the night this client has.
func _make_assist() -> void:
	if _sight == null:
		_sight = WorldProbe.new(get_world_3d().direct_space_state)
	assist = TouchAimAssist.new(get_tree(), state, _sight.callable())
	assist.touch_active = func() -> bool: return touch_active.is_valid() and touch_active.call()
	_human.assist = assist


## The look this client wears: the one a test or `--look` set, else the saved one.
func _wanted_look() -> CharacterLook:
	return own_look if own_look != null else LookStore.load_look()


func _make_spectator() -> Camera3D:
	_spectator = Camera3D.new()
	_spectator.fov = night_tuning.spectator_fov
	add_child(_spectator)
	_spectator.make_current()
	return _spectator


## The guns, the grenades, the lot's machines and shop and the soldiers' voices sound from the same
## events as the view.
func _add_sounds() -> void:
	var weapons := WeaponSounds.new()
	weapons.name = "WeaponSounds"
	add_child(weapons)
	weapons.setup(state)
	var energy := EnergySounds.new()
	energy.name = "EnergySounds"
	add_child(energy)
	energy.setup(state)
	var recut := RecutLayer.new()
	recut.name = "RecutLayer"
	add_child(recut)
	recut.setup(state)
	var grenades := GrenadeSounds.new()
	grenades.name = "GrenadeSounds"
	add_child(grenades)
	grenades.setup(state)
	grenades.where_is = view.grenade_position
	var lot := WorldSounds.new()
	lot.name = "WorldSounds"
	add_child(lot)
	var tuning: RulesTuning = rules_tuning
	var generator := world.greybox.get_node_or_null("GeneratorYard/Generator") as Node3D
	lot.setup(state, tuning.fuel, tuning.economy, generator, _post_point, _crane_point)
	var voice := SoldierVoice.new()
	voice.name = "SoldierVoice"
	voice.looks = looks
	add_child(voice)
	voice.setup(state)


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
	Audio.starts_per_frame = 0
	running = false
	if challenges != null:
		challenges.flush()
	if server != null:
		server.close()
	if remote and link != null:
		link.close()
	if mode == Mode.HUMAN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(_delta: float) -> void:
	if (_warming or _leaving) and remote:
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
	var began := PerfProbe.begin()
	link.pump()
	PerfProbe.end(&"tick.pump", began)
	began = PerfProbe.begin()
	var events := server.step(STEP)
	PerfProbe.end(&"tick.server", began)
	began = PerfProbe.begin()
	link.broadcast(events)
	PerfProbe.end(&"tick.client", began)
	if bots != null:
		began = PerfProbe.begin()
		bots.tick(STEP)
		PerfProbe.end(&"tick.bots", began)
	match mode:
		Mode.AUTOPILOT:
			began = PerfProbe.begin()
			var command := bot.decide(STEP)
			PerfProbe.end(&"tick.bot", began)
			if shoulder_camera:
				_aim_rig(command)
			_send_command(command)
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
	match stalls.check(Time.get_ticks_msec()):
		StallGuard.Verdict.RESYNC:
			_resync_body()
		StallGuard.Verdict.SKIP:
			# A tick the engine ran to catch up with a freeze: the server would take the newest of
			# these commands and none of the steps, so there is neither a step nor a command.
			ticked.emit()
			return
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
			command = bot.decide(STEP)
			if _body != null:
				_aim_rig(command)
	if command != null:
		# The body moves with the command as the server will read it, not as it was sampled.
		# The frame the player is looking at: the server judges the shot against it.
		if state.has_frame():
			command.view_step = int(state.frame.get("tick", 0)) & 0xFFFF
		command = NetWire.quantize(command)
		if _body != null:
			# Stopped by the dead the frame in hand shows, which is what the server will use
			# (`NightServer._dead_seen_by` takes the frame the command names).
			_body.dead.fill(DeadSnapshot.of_entries(state.zombies), _body.state.position)
			_body.tick(command.motion)
		_seq += 1
		command.seq = _seq
		command.player_id = state.player_id
		if _body != null:
			reconciler.record(_seq, _body.state.position)
		_send_command(command)
	if _body == null:
		_follow(STEP)
	ticked.emit()


## The loop froze and the server went on without us: the body is where the server has the player
## (the newest frame the backlog held), and the commands in flight are forgotten, since the answers
## to them are no longer about this body.
func _resync_body() -> void:
	reconciler.reset()
	if _body == null or not state.has_frame() or state.me().is_empty():
		return
	_body.state.position = state.position()
	_body.state.velocity = Vector3.ZERO
	PlayerSimulation.restore(_body, _body.state, get_physics_process_delta_time())


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
	var shift := reconciler.correction(me["ack"], me["pos"], _body.state.position)
	if shift != Vector3.ZERO:
		_body.state.position += shift
		PlayerSimulation.restore(_body, _body.state, get_physics_process_delta_time())
		if shift.length() > Reconciler.SNAP:
			# The server moved the player (back at the start after leaving the map): the body is
			# drawn there from this frame on, not blended across the map from its last tick. The
			# camera snaps by itself past `PlayerTuning.snap_distance`.
			_body.reset_physics_interpolation()
	if me.get("turn", false):
		_body.state.facing = me["facing"]
		_body.rotation.y = _body.state.facing


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
	preview.zombies = func() -> Array[Dictionary]: return state.zombies
	preview.hand_reach = night_tuning.grenade_hand_reach
	preview.release_over = night_tuning.grenade_release_over
	preview.release_under = night_tuning.grenade_release_under


## Orders the bots as this player, standing where they are now: `bot_id` 0 for the team's bots.
## Returns what was sent (`{}` for an order that cannot be given).
func give_bot_order(order: StringName, bot_id := 0) -> Dictionary:
	var body := _body_of(state.player_id)
	var at := body.global_position if body != null else Vector3.INF
	return bot_orders.issue(order, state.player_id, at, bot_id)


func _human_command() -> NightCommand:
	var command := _human.command(player(), state.player_id)
	if _human.ping_pressed(player()):
		link.send(_ping_request(command))
	return command


## What the ping key marks: what the crosshair is on, else where its ray lands (`PingAim`).
func _ping_request(aim: NightCommand) -> Dictionary:
	var landed := Vector3.INF
	var cast := PhysicsRayQueryParameters3D.create(
		aim.origin,
		aim.origin + aim.dir * PingAim.REACH,
		CameraProbe.PLAYER_MASK | PhysicsLayers.BODY
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(cast)
	if not hit.is_empty():
		landed = hit["position"]
	var shut := {}
	var index := 0
	for door_id in world.door_ids():
		if not state.frame.get("doors", []).has(door_id):
			shut[index] = world.door_points(door_id)
		index += 1
	var ammo: Array[Vector3] = []
	for spot in world.shop_spots():
		if spot["kind"] == &"ammo":
			ammo.append(spot["position"])
	return PingAim.pick(
		aim.origin,
		aim.dir,
		state.zombies,
		state.frame.get("players", {}),
		state.player_id,
		shut,
		ammo,
		landed
	)


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
		# A puppet is dressed by the avatars that place it (`RemoteAvatars`).
		if body != null and not body.is_puppet:
			body.dress(resolved[id], looks.seats[id])


## The body that draws a player on this screen: the server's in this process; online, our own, or
## the puppet the frames place for any other (and for ours when this client plays no body).
func _body_of(player_id: int) -> Player:
	if remote:
		if _body != null and player_id == state.player_id:
			return _body
		return avatars.avatar(player_id) if avatars != null else null
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
		_show_revive(event)


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


## The Soldier's downed pose and kneel follow the server's events: a player going down or getting
## up, and a teammate beginning or ending the hold (DownedPose).
func _show_revive(event: Dictionary) -> void:
	var type: StringName = event["type"]
	if not REVIVE_CLIP_EVENTS.has(type):
		return
	var animation := _animation_of(event["player_id"])
	if animation != null:
		match type:
			&"player_downed":
				animation.set_downed(true)
			&"player_revived":
				animation.set_downed(false)
			&"revive_started":
				animation.set_reviving(true)
			&"revive_stopped":
				animation.set_reviving(false)
	if type == &"player_revived" and event["reviver_id"] > 0:
		var reviver := _animation_of(event["reviver_id"])
		if reviver != null:
			reviver.set_reviving(false)


func _animation_of(player_id: int) -> PlayerAnimation:
	var body := _body_of(player_id)
	return body.get_node_or_null(^"AnimationTree") as PlayerAnimation if body else null


## The seconds between boards: the server's in this process, else the shared default.
func _repair_seconds() -> float:
	return night_tuning.repair_interval


## Sends a command and, when a bot made it, counts it in the bot's telemetry.
func _send_command(command: NightCommand) -> void:
	var action := command.to_dict()
	if bot != null:
		bot.telemetry.note_command(action)
	link.send(action)


## Seats the bots the match settings ask for beside the player (a local night only). They hear what
## the player's client hears, so a ping the player places reaches them as it would reach a person.
func _seat_bots(p_seed: int) -> void:
	bots = NightBots.new(server, world, p_seed, Callable(self, &"_bots_answered"))
	link.broadcast(bots.fill(server.rules.settings.bots, [PLAYER_ID]))
	link.delivered.connect(bots.hear)


## What the server answered a bot's command with goes to the player's client like any event.
func _bots_answered(events: Array) -> void:
	link.broadcast(events)


func _make_autopilot() -> void:
	autopilot = Autopilot.new(state, world.map())
	_sight = WorldProbe.new(get_world_3d().direct_space_state)
	autopilot.sight = _sight.callable()
	var level := BotLevel.new(_sight.callable(), world.is_lit, rules_tuning.rounds, world.map())
	bot = BotClient.new(state, BotProfile.autopilot(), SEED, link.send, level)
	bot.legacy = autopilot
	AutopilotSetup.configure(autopilot, world, rules_tuning, night_tuning)


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
	_spectator.look_at_from_position(
		at + night_tuning.spectator_offset, at + night_tuning.spectator_look_at
	)
