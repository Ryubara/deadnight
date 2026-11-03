class_name ZombieCodec
extends RefCounted
## The zombies as bytes, for a snapshot: everything a client needs to draw and animate them and
## nothing it could compute. Little-endian, nothing floating-point: positions in whole
## centimetres, yaw in 256 steps, speed in 0.05 m/s steps (the walk-to-run blend needs no more).
##
##   u16 count, then per zombie:
##   u16 id, i16 x_cm, i16 y_cm, i16 z_cm, u8 yaw, u8 mode, u8 episode, u8 speed, u8 look
##
## The mode byte holds three things: the mode in its low three bits (`MODE_MASK`, the modes fit),
## the status effect the zombie is under in the three above them (`STATUS_SHIFT`, `STATUS_MASK`: the
## wire id of a `StatusDef`, 0 for none, so a client draws it frozen) and, in its top bit
## (`TEARING_BIT`), that the zombie is at its boards pulling one off, so a client plays the tear
## clip and not the attack. Bit 6 is free. (Protocol 14: before it the mode had the seven low bits.)
##
## `look` is the index in `ZombieModels.looks()`, so a client that joins late draws every zombie in
## its type's body from the next frame, and a crippled one changes body when its look changes.
##
## Limits (more in docs/research/zombies.md): ids 0 to 65535, after which an id aliases (a match
## would need 65 536 zombies); each position axis -327.68 to 327.67 m from the world origin, beyond
## which it wraps; yaw to 1.4 degrees; speed to 12.75 m/s (capped). Only the speed is
## clamped.
##
## 13 bytes a zombie, so 40 zombies are 522 bytes before the transport's framing. Not yet wired to
## `spikes/net`'s protocol: the netcode owner picks the message type and rate.

const HEADER_BYTES := 2
const ENTRY_BYTES := 13
const SPEED_STEP := 0.05
const TEARING_BIT := 0x80
const MODE_MASK := 0x07
const STATUS_SHIFT := 3
const STATUS_MASK := 0x07


static func encode(zombies: Dictionary[int, ZombieBody]) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(HEADER_BYTES + ENTRY_BYTES * zombies.size())
	bytes.encode_u16(0, zombies.size())
	var at := HEADER_BYTES
	for zombie: ZombieBody in zombies.values():
		bytes.encode_u16(at, zombie.id)
		bytes.encode_s16(at + 2, roundi(zombie.position.x * 100.0))
		bytes.encode_s16(at + 4, roundi(zombie.position.y * 100.0))
		bytes.encode_s16(at + 6, roundi(zombie.position.z * 100.0))
		bytes.encode_u8(at + 8, roundi(wrapf(zombie.yaw, 0.0, TAU) / TAU * 256.0) & 0xFF)
		bytes.encode_u8(
			at + 9,
			(
				zombie.mode
				| ((zombie.status & STATUS_MASK) << STATUS_SHIFT)
				| (TEARING_BIT if zombie.tearing else 0)
			)
		)
		bytes.encode_u8(at + 10, zombie.episode)
		bytes.encode_u8(at + 11, mini(roundi(zombie.move_speed / SPEED_STEP), 255))
		bytes.encode_u8(at + 12, ZombieModels.look_index(zombie.look()))
		at += ENTRY_BYTES
	return bytes


## The entries, in the form of `ZombieBody.view_entry()`. A packet that is too short for what
## it says gives an empty list: it is dropped, not guessed at.
static func decode(bytes: PackedByteArray) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if bytes.size() < HEADER_BYTES:
		return entries
	var count := bytes.decode_u16(0)
	if bytes.size() < HEADER_BYTES + ENTRY_BYTES * count:
		return entries
	var at := HEADER_BYTES
	for _i in count:
		var entry := {
			"id": bytes.decode_u16(at),
			"yaw": bytes.decode_u8(at + 8) / 256.0 * TAU,
			"mode": bytes.decode_u8(at + 9) & MODE_MASK,
			"status": (bytes.decode_u8(at + 9) >> STATUS_SHIFT) & STATUS_MASK,
			"tearing": (bytes.decode_u8(at + 9) & TEARING_BIT) != 0,
			"episode": bytes.decode_u8(at + 10),
			"speed": bytes.decode_u8(at + 11) * SPEED_STEP,
			"look": ZombieModels.look_at(bytes.decode_u8(at + 12)),
		}
		entry["position"] = Vector3(
			bytes.decode_s16(at + 2) / 100.0,
			bytes.decode_s16(at + 4) / 100.0,
			bytes.decode_s16(at + 6) / 100.0
		)
		entries.append(entry)
		at += ENTRY_BYTES
	return entries
