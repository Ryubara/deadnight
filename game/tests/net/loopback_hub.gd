class_name LoopbackHub
extends RefCounted
## A stand-in for the real connection, for tests: one `LookServer` and any number of clients
## (a `LookRegistry` each), with packets carried between them in order through plain queues.
## Nothing here is timing-dependent; `pump` delivers everything that is waiting.

var server: LookServer
var clients: Dictionary = {}

## Every packet that went up, for sizing and sniffing.
var uplink: Array[PackedByteArray] = []
## Every packet that went down.
var downlink: Array[PackedByteArray] = []

var _to_client: Dictionary = {}
var _to_server: Array = []
var _next_id := 1


## `unlocks_for` is the server's answer to "what may this player wear"; without one every player
## has the whole wardrobe (a test of the lock gives one).
func _init(unlocks_for: Callable = Callable()) -> void:
	if not unlocks_for.is_valid():
		unlocks_for = func(_id: int) -> LookUnlocks:
			return LookUnlocks.at_level(LevelCurve.MAX_LEVEL)
	server = LookServer.new(_send_down, unlocks_for)


## Connects a new client; returns its player id.
func connect_client() -> int:
	var id := _next_id
	_next_id += 1
	clients[id] = LookRegistry.new()
	_to_client[id] = []
	server.join(id)
	return id


func disconnect_client(id: int) -> void:
	server.leave(id)
	clients.erase(id)
	_to_client.erase(id)
	for other: int in clients:
		(clients[other] as LookRegistry).remove(id)


## The client sends its look, as it does once on join.
func send_look(id: int, look: CharacterLook) -> void:
	var packet := LookWire.look(look)
	uplink.append(packet)
	_to_server.append([id, packet])


## Sends raw bytes from a client (a hostile or broken one).
func send_raw(id: int, packet: PackedByteArray) -> void:
	uplink.append(packet)
	_to_server.append([id, packet])


func pump() -> void:
	while not _to_server.is_empty() or _any_waiting():
		while not _to_server.is_empty():
			var item: Array = _to_server.pop_front()
			server.receive(item[0], item[1])
		for id: int in _to_client:
			var queue: Array = _to_client[id]
			while not queue.is_empty():
				(clients[id] as LookRegistry).receive(queue.pop_front())


func _any_waiting() -> bool:
	for id: int in _to_client:
		if not (_to_client[id] as Array).is_empty():
			return true
	return false


func _send_down(id: int, packet: PackedByteArray) -> void:
	if _to_client.has(id):
		downlink.append(packet)
		(_to_client[id] as Array).append(packet)
