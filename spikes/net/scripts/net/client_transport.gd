class_name ClientTransport
extends RefCounted
## The client's end of a connection: send and receive whole packets, nothing else.
## Implementations: WebSocketClientTransport (real), LoopbackClientTransport (in-process),
## ConditionedTransport (wraps any of them with artificial delay, jitter and loss).

signal connected
signal disconnected
signal packet_received(data: PackedByteArray)


func connect_to(_url: String) -> Error:
	return ERR_UNAVAILABLE


## Call once per tick: moves bytes and emits the signals above.
func poll() -> void:
	pass


func send(_data: PackedByteArray) -> void:
	pass


func close() -> void:
	pass


func is_open() -> bool:
	return false
