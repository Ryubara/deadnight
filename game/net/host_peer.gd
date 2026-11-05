class_name HostPeer
extends RefCounted
## One connection to the server.
var transport_id: int
## 0 until the client has said hello and been given a seat.
var player_id := 0
## The frame this client last had, the baseline of the next delta.
var last_frame: Dictionary = {}
## Ticks in a row the socket would not take (the client stopped reading).
var missed_ticks := 0
## The step at which a refused client is hung up on, or -1.
var close_at := -1
var refused := false
var kicked := false
## When the connection opened (seconds), for the time it has to say hello.
var connected_at := 0.0
var limits := PeerLimits.new()
## The zombies this client has (`ZombieDelta`), and the number of the next delta to it.
var zombie_base: Dictionary[int, PackedByteArray] = {}
var zombie_sequence := 0
## What the client was given at WELCOME to take its seat back with.
var token := PackedByteArray()
## Who the backend's ticket says this is (`""` when the server has no backend), and their name.
var user := ""
var user_name := ""
## The progression the ticket carries (`TicketVerifier.account_of`).
var account: Dictionary = {}


func _init(p_transport_id: int, now: float = 0.0) -> void:
	transport_id = p_transport_id
	connected_at = now
