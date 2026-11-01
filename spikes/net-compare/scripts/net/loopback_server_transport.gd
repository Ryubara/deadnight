class_name LoopbackServerTransport
extends ServerTransport
## The server end of an in-process link: single-player runs the same server code inside the client's
## process, and its LoopbackClientTransports talk to it through plain arrays (no sockets).

var _clients: Dictionary[int, LoopbackClientTransport] = {}
var _inbox: Array[Array] = []
var _joined: Array[int] = []
var _left: Array[int] = []
var _next_id := 1


func listen(_port: int) -> Error:
	return OK


## Called by LoopbackClientTransport.connect_to.
func accept(client: LoopbackClientTransport) -> void:
	var id := _next_id
	_next_id += 1
	_clients[id] = client
	client.peer_id = id
	_joined.append(id)


func receive_from_client(peer_id: int, data: PackedByteArray) -> void:
	_inbox.append([peer_id, data])


func client_closed(peer_id: int) -> void:
	_clients.erase(peer_id)
	_left.append(peer_id)


func poll() -> void:
	for id in _joined:
		peer_connected.emit(id)
	_joined.clear()
	var batch := _inbox.duplicate()
	_inbox.clear()
	for item in batch:
		packet_received.emit(item[0], item[1])
	for id in _left:
		peer_disconnected.emit(id)
	_left.clear()


func send(peer_id: int, data: PackedByteArray) -> void:
	var client: LoopbackClientTransport = _clients.get(peer_id)
	if client:
		client.receive_from_server(data)


func close() -> void:
	_clients.clear()  # the two ends reference each other: let go so both can be freed


func disconnect_peer(peer_id: int) -> void:
	var client: LoopbackClientTransport = _clients.get(peer_id)
	if client:
		client.close()
