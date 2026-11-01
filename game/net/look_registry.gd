class_name LookRegistry
extends RefCounted
## A client's table of every player's look and seat, built from the server's PLAYER_LOOK packets.
##
## `resolved()` is what to draw: the same table with identical looks told apart (`LookResolver`).
## The arrival order of packets does not matter to it, so every client draws the same lot.

## Emitted when a player's look arrives or changes (and when one leaves).
signal changed(player_id: int)

## Raw looks as sent, by player id.
var looks: Dictionary = {}
var seats: Dictionary = {}


## Feeds one packet from the server; anything that is not a PLAYER_LOOK is ignored. Returns true
## when it was one. A look this build cannot read is shown as the default look.
func receive(packet: PackedByteArray) -> bool:
	var message := LookWire.decode(packet)
	if message.get("type", 0) != LookWire.Type.PLAYER_LOOK:
		return false
	var id: int = message["player_id"]
	var look: CharacterLook = message["look"]
	looks[id] = look if look != null else CharacterLook.new()
	seats[id] = message["seat"]
	changed.emit(id)
	return true


func remove(player_id: int) -> void:
	if looks.erase(player_id):
		seats.erase(player_id)
		changed.emit(player_id)


## The looks to draw, by player id.
func resolved() -> Dictionary:
	return LookResolver.resolve(looks)


## Builds the model of one player, tinted and with its seat's armband.
func assemble(player_id: int) -> Node3D:
	return CharacterAssembler.assemble(resolved()[player_id], seats[player_id])
