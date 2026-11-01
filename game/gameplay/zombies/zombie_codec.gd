class_name ZombieCodec
extends RefCounted
## The zombies as bytes, for a snapshot: everything a client needs to draw and animate them and
## nothing it could compute. Little-endian, nothing floating-point: positions in whole
## centimetres, yaw in 256 steps, speed in 0.05 m/s steps (the walk-to-run blend needs no more).
##
##   u16 count, then per zombie:
##   u16 id, i16 x_cm, i16 y_cm, i16 z_cm, u8 yaw, u8 mode, u8 episode, u8 speed
##
## 12 bytes a zombie, so 40 zombies are 482 bytes before the transport's framing. Not yet wired to
## `spikes/net`'s protocol: the netcode owner picks the message type and rate.

const HEADER_BYTES := 2
const ENTRY_BYTES := 12
const SPEED_STEP := 0.05


static func encode(zombies: Dictionary[int, ZombieState]) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(HEADER_BYTES + ENTRY_BYTES * zombies.size())
	bytes.encode_u16(0, zombies.size())
	var at := HEADER_BYTES
	for zombie: ZombieState in zombies.values():
		bytes.encode_u16(at, zombie.id)
		bytes.encode_s16(at + 2, roundi(zombie.position.x * 100.0))
		bytes.encode_s16(at + 4, roundi(zombie.position.y * 100.0))
		bytes.encode_s16(at + 6, roundi(zombie.position.z * 100.0))
		bytes.encode_u8(at + 8, roundi(wrapf(zombie.yaw, 0.0, TAU) / TAU * 256.0) & 0xFF)
		bytes.encode_u8(at + 9, zombie.mode)
		bytes.encode_u8(at + 10, zombie.episode)
		bytes.encode_u8(at + 11, mini(roundi(zombie.move_speed / SPEED_STEP), 255))
		at += ENTRY_BYTES
	return bytes


## The entries, in the form of `ZombieState.view_entry()`. A packet that is too short for what
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
			"mode": bytes.decode_u8(at + 9),
			"episode": bytes.decode_u8(at + 10),
			"speed": bytes.decode_u8(at + 11) * SPEED_STEP,
		}
		entry["position"] = Vector3(
			bytes.decode_s16(at + 2) / 100.0,
			bytes.decode_s16(at + 4) / 100.0,
			bytes.decode_s16(at + 6) / 100.0
		)
		entries.append(entry)
		at += ENTRY_BYTES
	return entries
