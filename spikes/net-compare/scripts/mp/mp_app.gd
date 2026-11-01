class_name MpApp
extends Node
## Entry for `--mode=mp`: the same command line as the own-protocol spike, but on the built-in
## MultiplayerAPI (WebSocketMultiplayerPeer). `--server` or `--client`, `--url=`, `--port=`,
## `--zombies=`.

var _args: NetArgs
var _client: MpClient


func _init(args: NetArgs) -> void:
	name = "MpApp"
	_args = args


func _ready() -> void:
	MpEntity.packed = _args.has("pack")
	MpEntity.client_auth = _args.has("client-auth")
	var world := MpWorld.new()
	world.name = "World"
	add_child(world)
	if _args.has("run-seconds"):
		get_tree().create_timer(_args.get_float("run-seconds")).timeout.connect(_finish)
	if _args.has("local"):
		var local_server := MpServer.new()
		local_server.name = "Server"
		add_child(local_server)
		_client = MpClient.new()
		_client.name = "Client"
		add_child(_client)
		_client.start_offline(world, InputSampler.new(_args.get_int("bot-seed", 0)))
		local_server.start_offline(world, _args.get_int("seed", 1), _args.get_int("zombies"))
	elif _args.has("server"):
		var server := MpServer.new()
		server.name = "Server"
		add_child(server)
		var port := _args.get_int("port", NetArgs.DEFAULT_PORT)
		server.start(world, port, _args.get_int("seed", 1), _args.get_int("zombies"))
	else:
		_client = MpClient.new()
		_client.name = "Client"
		add_child(_client)
		var url := _args.get_string("url", "ws://127.0.0.1:%d" % NetArgs.DEFAULT_PORT)
		_client.start(world, url, InputSampler.new(_args.get_int("bot-seed", 0)))


func _finish() -> void:
	if _client:
		print(_client.final_report())
	get_tree().quit()
