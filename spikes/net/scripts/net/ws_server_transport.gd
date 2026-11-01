class_name WebSocketServerTransport
extends ServerTransport
## A WebSocket server built from TCPServer + WebSocketPeer.accept_stream: each accepted TCP
## connection becomes a WebSocketPeer, and gets a peer id once its handshake completes.

var _tcp := TCPServer.new()
var _handshaking: Array[WebSocketPeer] = []
var _peers: Dictionary[int, WebSocketPeer] = {}
var _next_id := 1


func listen(port: int) -> Error:
	return _tcp.listen(port)


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
			packet_received.emit(id, ws.get_packet())
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_peers.erase(id)
			peer_disconnected.emit(id)


func send(peer_id: int, data: PackedByteArray) -> void:
	var ws: WebSocketPeer = _peers.get(peer_id)
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send(data, WebSocketPeer.WRITE_MODE_BINARY)


func disconnect_peer(peer_id: int) -> void:
	var ws: WebSocketPeer = _peers.get(peer_id)
	if ws:
		ws.close()


func close() -> void:
	for ws in _peers.values():
		ws.close()
	_tcp.stop()
