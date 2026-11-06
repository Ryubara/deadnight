class_name WsListener
extends RefCounted
## A WebSocket server built from `TCPServer` + `WebSocketPeer.accept_stream` (the spike's, proven on
## Railway): each accepted connection becomes a peer, and gets an id once its handshake completes.
## Call `poll` once per tick; it emits the signals below. Binary frames only.

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal packet_received(peer_id: int, data: PackedByteArray)

## What a peer may have waiting to be read: bytes, and packets. The longest message is a hello
## (`NetWire.MAX_HELLO`), so a frame bigger than the buffer is a hostile one the engine refuses.
const INBOUND_BUFFER := 1 << 16
## The engine's count limit holds for both directions: what comes in is held by the buffer above
## and what goes out to `OUTBOUND_BUFFER`.
const MAX_QUEUED := 8192
## What may be waiting to be sent to a peer that is not reading (a client whose game loop froze):
## ticks of a second or two are some 15 to 35 KB each second, and the engine's default of 64 KB
## began to drop them after a few seconds, which broke the chain of frame deltas (#483).
const OUTBOUND_BUFFER := 1 << 20
## Seconds a client has to answer the closing handshake before the server lets go of it.
const CLOSE_GRACE := 1.0

## Bytes in and out, all peers, for the numbers a run prints.
var bytes_in := 0
var bytes_out := 0
var packets_out := 0

## Bytes that may wait to be sent to a peer (`OUTBOUND_BUFFER`; a test sets it before peers come).
var outbound_buffer := OUTBOUND_BUFFER

var _tcp := TCPServer.new()
var _handshaking: Array[WebSocketPeer] = []
var _peers: Dictionary[int, WebSocketPeer] = {}
var _next_id := 1
## Peers being hung up on, and when we began (seconds): a client that does not answer the closing
## handshake is let go after `CLOSE_GRACE`.
var _closing: Dictionary[int, float] = {}
var _close_codes: Dictionary[int, int] = {}


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
		ws.inbound_buffer_size = INBOUND_BUFFER
		ws.max_queued_packets = MAX_QUEUED
		ws.outbound_buffer_size = outbound_buffer
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
		var now := Time.get_ticks_msec() / 1000.0
		var gone := ws.get_ready_state() == WebSocketPeer.STATE_CLOSED
		if _closing.has(id) and now - _closing[id] > CLOSE_GRACE:
			gone = true
		if gone:
			# Remembered for the signal's handlers: a clean goodbye (1000, or 1001 when a page is
			# closed) against a socket that went away (no close frame, or any other code).
			_close_codes[id] = ws.get_close_code()
			_peers.erase(id)
			_closing.erase(id)
			peer_disconnected.emit(id)


## The close code the peer's socket ended with (-1 when no close frame came), kept after
## `peer_disconnected`.
func close_code_of(peer_id: int) -> int:
	return _close_codes.get(peer_id, -1)


## Whether the peer said goodbye on purpose (a normal closure, or a page going away).
func left_on_purpose(peer_id: int) -> bool:
	var code := close_code_of(peer_id)
	return code == 1000 or code == 1001


## Sends a packet to a peer; false when it was not sent (no such peer, not open, or its buffer
## is full because it has stopped reading).
func send(peer_id: int, data: PackedByteArray) -> bool:
	var ws: WebSocketPeer = _peers.get(peer_id)
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	if ws.get_current_outbound_buffered_amount() + data.size() > outbound_buffer:
		return false
	if ws.send(data, WebSocketPeer.WRITE_MODE_BINARY) != OK:
		return false
	bytes_out += data.size()
	packets_out += 1
	return true


func disconnect_peer(peer_id: int) -> void:
	var ws: WebSocketPeer = _peers.get(peer_id)
	if ws != null:
		ws.close()
		_closing[peer_id] = Time.get_ticks_msec() / 1000.0


func close() -> void:
	for ws in _peers.values():
		ws.close()
	for ws in _handshaking:
		ws.close()
	_tcp.stop()
