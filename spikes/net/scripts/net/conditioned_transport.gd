class_name ConditionedTransport
extends ClientTransport
## Wraps any ClientTransport and makes the link worse on purpose, in both directions: a fixed
## one-way delay, random jitter, and random loss. Seeded and clocked by `advance()` (the
## caller's tick), so a run is repeatable and never reads the real clock. Jitter may reorder
## packets, like UDP would.

var delay_ms := 0.0
var jitter_ms := 0.0
var loss := 0.0

var _inner: ClientTransport
var _rng := RandomNumberGenerator.new()
var _now_ms := 0.0
var _outgoing: Array[Array] = []
var _incoming: Array[Array] = []


func _init(inner: ClientTransport, seed_value: int = 1) -> void:
	_inner = inner
	_rng.seed = seed_value
	_inner.connected.connect(_on_inner_connected)
	_inner.disconnected.connect(_on_inner_disconnected)
	_inner.packet_received.connect(_on_inner_packet)


func advance(dt_seconds: float) -> void:
	_now_ms += dt_seconds * 1000.0


func connect_to(url: String) -> Error:
	return _inner.connect_to(url)


func send(data: PackedByteArray) -> void:
	if not _dropped():
		_outgoing.append([_release_time(), data])


func poll() -> void:
	_inner.poll()
	_release(_outgoing, func(data: PackedByteArray) -> void: _inner.send(data))
	_release(_incoming, func(data: PackedByteArray) -> void: packet_received.emit(data))


func close() -> void:
	_inner.close()
	_inner.connected.disconnect(_on_inner_connected)
	_inner.disconnected.disconnect(_on_inner_disconnected)
	_inner.packet_received.disconnect(_on_inner_packet)


func is_open() -> bool:
	return _inner.is_open()


func _on_inner_connected() -> void:
	connected.emit()


func _on_inner_disconnected() -> void:
	disconnected.emit()


func _on_inner_packet(data: PackedByteArray) -> void:
	if not _dropped():
		_incoming.append([_release_time(), data])


func _dropped() -> bool:
	return loss > 0.0 and _rng.randf() < loss


func _release_time() -> float:
	return _now_ms + delay_ms + _rng.randf() * jitter_ms


func _release(queue: Array[Array], deliver: Callable) -> void:
	var due: Array[Array] = []
	for item in queue:
		if item[0] <= _now_ms:
			due.append(item)
	for item in due:
		queue.erase(item)
		deliver.call(item[1])
