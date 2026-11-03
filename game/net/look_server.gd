class_name LookServer
extends RefCounted
## The server's side of looks: keeps each player's accepted look and seat, and tells everyone.
##
## It only moves data: the game server calls `join`, `receive` and `leave` from its own connection
## handling and passes `send`, a Callable taking (player_id: int, packet: PackedByteArray), the
## way to reach one client. Nothing here knows the transport.
##
## A look from a client is never trusted: a look of another version or length is replaced by the
## default look, and an option the player has not unlocked is put back to the slot's first
## option. `unlocks_for` is a Callable (player_id) -> LookUnlocks that the platform backend will
## answer; without one every player has the starting unlocks.

## Seats in the lot: `NightHost.MAX_PLAYERS` (a test holds them equal).
const SEATS := 8

var looks: Dictionary = {}
var seats: Dictionary = {}

var _send: Callable
var _unlocks_for: Callable


func _init(send: Callable, unlocks_for: Callable = Callable()) -> void:
	_send = send
	_unlocks_for = unlocks_for


## A player has connected: gives them the lowest free seat and sends them everyone's look so far.
## Returns the seat, or -1 when the lot is full.
func join(player_id: int) -> int:
	var seat := 0
	while seats.values().has(seat):
		seat += 1
	if seat >= SEATS:
		return -1
	seats[player_id] = seat
	# Until their own look arrives, a player wears the preset of their seat, so a lot starts out
	# with everyone different.
	looks[player_id] = CharacterLook.from_preset(seat)
	# Everyone, the new player included, learns the new seat at once (with that look); the new
	# player also learns who is already here.
	for id: int in seats:
		_send.call(id, LookWire.player_look(player_id, seat, looks[player_id]))
	for other: int in looks:
		if other != player_id:
			_send.call(player_id, LookWire.player_look(other, seats[other], looks[other]))
	return seat


## A player has come back on a new connection: sends them everyone's seat and look again (their
## own included), which the new connection has not heard.
func sync(player_id: int) -> void:
	for id: int in looks:
		_send.call(player_id, LookWire.player_look(id, seats[id], looks[id]))


func leave(player_id: int) -> void:
	looks.erase(player_id)
	seats.erase(player_id)


## A packet from a client. Anything but a LOOK is ignored here. Returns true when it was one.
func receive(player_id: int, packet: PackedByteArray) -> bool:
	if not seats.has(player_id):
		return false
	var message := LookWire.decode(packet)
	if message.get("type", 0) != LookWire.Type.LOOK:
		return false
	var look: CharacterLook = message["look"]
	if look == null:
		look = CharacterLook.new()
	var unlocks := LookUnlocks.new()
	if _unlocks_for.is_valid():
		unlocks = _unlocks_for.call(player_id)
	look = look.without_locked(unlocks)
	looks[player_id] = look
	var out := LookWire.player_look(player_id, seats[player_id], look)
	for id: int in seats:
		_send.call(id, out)
	return true
