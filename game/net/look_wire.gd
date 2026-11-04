class_name LookWire
extends RefCounted
## The look messages of the game protocol (the spike's protocol v1 uses types 1 to 7; these two
## continue the numbering). Every message is one packet: a type byte, then fixed fields.
##
## LOOK         C->S  u8 type=8, then the look (`CharacterLook.to_bytes`): sent once, on join
## PLAYER_LOOK  S->C  u8 type=9, u8 player_id, u8 seat, then the look: to everyone when a player's
##                    look is accepted, and to a new player for each player already in the lot
##
## A look is 17 bytes (version 3: eleven part slots, the mouth's last, and five colours), so a join
## costs 18 bytes up and 20 bytes per player down. A look of version 2 (16 bytes, no mouth) still
## decodes: `CharacterLook.from_bytes` gives it the first mouth.

enum Type { LOOK = 8, PLAYER_LOOK = 9 }


static func look(value: CharacterLook) -> PackedByteArray:
	var out := PackedByteArray([Type.LOOK])
	out.append_array(value.to_bytes())
	return out


static func player_look(player_id: int, seat: int, value: CharacterLook) -> PackedByteArray:
	var out := PackedByteArray([Type.PLAYER_LOOK, player_id, seat])
	out.append_array(value.to_bytes())
	return out


## Decodes either message to a Dictionary with a "type" key and the fields above ("look" is a
## `CharacterLook`, or null when the look bytes are not a look this build understands). An empty
## Dictionary means the packet is not one of these messages or is malformed.
static func decode(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {}
	match data[0]:
		Type.LOOK:
			if not CharacterLook.fits_wire(data.size() - 1):
				return {}
			return {"type": Type.LOOK, "look": CharacterLook.from_bytes(data.slice(1))}
		Type.PLAYER_LOOK:
			if not CharacterLook.fits_wire(data.size() - 3):
				return {}
			return {
				"type": Type.PLAYER_LOOK,
				"player_id": data[1],
				"seat": data[2],
				"look": CharacterLook.from_bytes(data.slice(3)),
			}
	return {}
