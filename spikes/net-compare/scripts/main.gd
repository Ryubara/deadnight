extends Node
## Entry point. One program, three shapes, chosen on the command line (after `--`):
##   --server   (or any headless run)  the authoritative server over WebSocket, port --port / $PORT
##   (default)                         a client that connects to --url over WebSocket
##   --local                           single-player: the same server runs in this process
## Link trouble for testing, on any client: --latency=ms (one way) --jitter=ms --loss=0..1

const WORLD_SCENE := preload("res://scenes/world.tscn")

var _client: GameClient
var _hud: Label


func _ready() -> void:
	var args := NetArgs.new()
	var headless := DisplayServer.get_name() == "headless"
	if args.get_string("mode") == "mp":
		Engine.max_fps = 60  # a headless server otherwise spins; same cap for both modes below
		add_child(MpApp.new(args))
		return
	Engine.max_fps = 60
	if args.has("run-seconds"):
		# For scripted runs (measurements, captures): leave after this many seconds.
		get_tree().create_timer(args.get_float("run-seconds")).timeout.connect(_finish)
	if args.has("server") or (headless and not args.has("client")):
		_start_server(args)
	else:
		_start_client(args)


func _process(_delta: float) -> void:
	if _client and _hud:
		_hud.text = _client.status_text()


func _start_server(args: NetArgs) -> void:
	var server := GameServer.new()
	server.name = "Server"
	server.snapshot_every = args.get_int("snapshot-every", 1)
	server.use_deltas = not args.has("full-snapshots")
	add_child(server)
	var port_env := OS.get_environment("PORT")  # Railway says which port through $PORT
	var port := args.get_int(
		"port", int(port_env) if not port_env.is_empty() else NetArgs.DEFAULT_PORT
	)
	server.start(
		WebSocketServerTransport.new(), port, args.get_int("seed", 1), args.get_int("zombies")
	)


func _start_client(args: NetArgs) -> void:
	var view: WorldView = WORLD_SCENE.instantiate()
	add_child(view)
	_build_hud()
	var transport: ClientTransport
	if args.has("local"):
		var loopback := LoopbackServerTransport.new()
		var server := GameServer.new()
		server.name = "Server"
		add_child(server)  # before the client: the server ticks first each frame
		server.start(loopback, 0, args.get_int("seed", 1), args.get_int("zombies"))
		transport = LoopbackClientTransport.new(loopback)
	else:
		transport = WebSocketClientTransport.new()
	var lossy := args.get_float("loss") > 0.0
	if args.has("latency") or args.has("jitter") or lossy:
		var conditioned := ConditionedTransport.new(transport, args.get_int("seed", 1))
		conditioned.delay_ms = args.get_float("latency")
		conditioned.jitter_ms = args.get_float("jitter")
		conditioned.loss = args.get_float("loss")
		transport = conditioned
	_client = GameClient.new()
	_client.name = "Client"
	_client.input_redundancy = args.get_int("input-redundancy", 3 if lossy else 1)
	_client.interp_ticks = args.get_float("interp-ms", 100.0) * GameSim.TICK_RATE / 1000.0
	add_child(_client)
	var bot_seed := -1
	if args.has("bot-seed") or args.has("bot"):
		bot_seed = args.get_int("bot-seed", 0)
	_client.start(transport, _resolve_url(args), view, InputSampler.new(bot_seed))


func _resolve_url(args: NetArgs) -> String:
	if args.has("url"):
		return args.get_string("url")
	if OS.has_feature("web"):
		# `?url=wss://host` in the page address wins; otherwise the server is on the page's own host.
		return (
			"ws://%s:%d" % [JavaScriptBridge.eval("window.location.hostname"), NetArgs.DEFAULT_PORT]
		)
	return "ws://127.0.0.1:%d" % args.get_int("port", NetArgs.DEFAULT_PORT)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(12, 8)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)
	add_child(layer)


func _finish() -> void:
	if _client:
		print(_client.final_report())
	get_tree().quit()
