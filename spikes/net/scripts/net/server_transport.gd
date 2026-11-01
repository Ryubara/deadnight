class_name ServerTransport
extends RefCounted
## The server's end: many peers, each addressed by an integer id the transport hands out.
## Implementations: WebSocketServerTransport (real), LoopbackServerTransport (in-process).

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal packet_received(peer_id: int, data: PackedByteArray)


func listen(_port: int) -> Error:
	return ERR_UNAVAILABLE


## Call once per tick: accepts peers, moves bytes and emits the signals above.
func poll() -> void:
	pass


func send(_peer_id: int, _data: PackedByteArray) -> void:
	pass


func disconnect_peer(_peer_id: int) -> void:
	pass


func close() -> void:
	pass
