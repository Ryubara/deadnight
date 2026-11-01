class_name WebSocketClientTransport
extends ClientTransport
## Godot's raw WebSocketPeer as a client. Works on desktop and in the single-threaded web build.

var _ws := WebSocketPeer.new()
var _was_open := false
var _active := false


func connect_to(url: String) -> Error:
	_active = true
	return _ws.connect_to_url(url)


func poll() -> void:
	if not _active:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				connected.emit()
			while _ws.get_available_packet_count() > 0:
				packet_received.emit(_ws.get_packet())
		WebSocketPeer.STATE_CLOSED:
			_active = false
			disconnected.emit()


func send(data: PackedByteArray) -> void:
	if is_open():
		_ws.send(data, WebSocketPeer.WRITE_MODE_BINARY)


func close() -> void:
	_ws.close()


func is_open() -> bool:
	return _active and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN
