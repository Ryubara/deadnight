class_name WsListener
extends RefCounted
## A WebSocket server built from `TCPServer` + `WebSocketPeer.accept_stream` (the spike's, proven on
## Railway): each accepted connection becomes a peer, and gets an id once its handshake completes.
## Call `poll` once per tick; it emits the signals below. Binary frames only.

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal packet_received(peer_id: int, data: PackedByteArray)

## Bytes in and out, all peers, for the numbers a run prints.
var bytes_in := 0
var bytes_out := 0
var packets_out := 0

var _tcp := TCPServer.new()
var _handshaking: Array[WebSocketPeer] = []
var _peers: Dictionary[int, WebSocketPeer] = {}
var _next_id := 1


func listen(port: int) -> Error:
	return _tcp.listen(port)


func is_listening() -> bool:
	return _tcp.is_listening()


## The port actually bound (useful after `listen(0)`).
func port() -> int:
	return _tcp.get_local_port()


func peer_count() -> int:
	return _peers.size()


func poll() -> void:
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.accept_stream(_tcp.take_connection())
		_handshaking.append(ws)
	for ws in _handshaking.duplicate():
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				_handshaking.erase(ws)
				var id := _next_id
				_next_id += 1
				_peers[id] = ws
				peer_connected.emit(id)
			WebSocketPeer.STATE_CLOSED:
				_handshaking.erase(ws)
	for id in _peers.keys():
		var ws := _peers[id]
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var packet := ws.get_packet()
			bytes_in += packet.size()
			packet_received.emit(id, packet)
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_peers.erase(id)
			peer_disconnected.emit(id)


func send(peer_id: int, data: PackedByteArray) -> void:
	var ws: WebSocketPeer = _peers.get(peer_id)
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send(data, WebSocketPeer.WRITE_MODE_BINARY)
		bytes_out += data.size()
		packets_out += 1


func disconnect_peer(peer_id: int) -> void:
	var ws: WebSocketPeer = _peers.get(peer_id)
	if ws != null:
		ws.close()


func close() -> void:
	for ws in _peers.values():
		ws.close()
	for ws in _handshaking:
		ws.close()
	_tcp.stop()
