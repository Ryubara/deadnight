class_name LoopbackClientTransport
extends ClientTransport
## The client end of an in-process link to a LoopbackServerTransport.

var peer_id := 0

var _server: LoopbackServerTransport
var _inbox: Array[PackedByteArray] = []
var _open := false
var _announce := false


func _init(server: LoopbackServerTransport) -> void:
	_server = server


func connect_to(_url: String) -> Error:
	_server.accept(self)
	_open = true
	_announce = true
	return OK


func receive_from_server(data: PackedByteArray) -> void:
	_inbox.append(data)


func poll() -> void:
	if _announce:
		_announce = false
		connected.emit()
	var batch := _inbox.duplicate()
	_inbox.clear()
	for data in batch:
		packet_received.emit(data)


func send(data: PackedByteArray) -> void:
	if _open:
		_server.receive_from_client(peer_id, data)


func close() -> void:
	if _open:
		_open = false
		_server.client_closed(peer_id)
		disconnected.emit()
	_server = null


func is_open() -> bool:
	return _open
