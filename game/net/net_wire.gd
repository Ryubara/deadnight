class_name NetWire
extends RefCounted
## The bytes of a night's connection (protocol version 1), one message to a WebSocket frame: a type
## byte, then the fields. `LookWire` continues the numbering with types 8 and 9.
##
## HELLO    C->S  u8 type=1, u8 version                    the first message of a client
## WELCOME  S->C  u8 type=2, u8 version, u8 player_id, u8 tick_rate, then a packed variable: the
##                rules' snapshot (`GameRules.to_dict()`), for a HUD that joins in the middle
## COMMAND  C->S  u8 type=3, u32 seq, f32 move x/y, f32 yaw, f32 pitch, u16 flags, f32 origin x/y/z,
##                f32 dir x/y/z (fixed, `COMMAND_SIZE` = 47 bytes in all)
## TICK     S->C  u8 type=4, u32 server step, then a packed variable: the array of events since the
##                last TICK, the frame last; a frame after the first only carries what changed
##                (`FrameDelta`)
## PING     C->S  u8 type=6, u32 client milliseconds
## PONG     S->C  u8 type=7, u32 the same, u32 server step
## REFUSED  S->C  u8 type=10, u8 reason (`Refusal`); the server closes the connection after it
##
## A packed variable is a flag byte (0 plain, 1 compressed with Zstandard), when compressed the u32
## size it has once unpacked, and the `var_to_bytes` of the value. The server decodes nothing but
## the fixed layouts above from a client; only the clients decode variables, and without objects.
##
## Everything a decoder reads is length-checked first, and a short, long or unknown packet is
## dropped (an empty Dictionary, or null).

enum Type { HELLO = 1, WELCOME = 2, COMMAND = 3, TICK = 4, PING = 6, PONG = 7, REFUSED = 10 }
enum Refusal { VERSION = 1, FULL = 2 }

const VERSION := 1
## Port of a game server unless told otherwise. (Not 9080: the Godot editor's MCP bridge listens
## there on the maintainer's machine and Windows lets a second listener bind it silently.)
const DEFAULT_PORT := 8910
const COMMAND_SIZE := 47
const WELCOME_HEADER := 4
const TICK_HEADER := 5
## What a packed variable may be once unpacked, so a hostile length cannot ask for gigabytes.
const MAX_UNPACKED := 4 * 1024 * 1024
## Packed variables under this many bytes are left as they are.
const COMPRESS_FROM := 256

# The bits of a command's flags.
const F_SPRINT := 1 << 0
const F_CROUCH := 1 << 1
const F_JUMP := 1 << 2
const F_AIM := 1 << 3
const F_SWAP_SHOULDER := 1 << 4
const F_THROW_OVER := 1 << 5
const F_THROW_UNDER := 1 << 6
const F_FIRE := 1 << 7
const F_RELOAD := 1 << 8
const F_USE := 1 << 9
const F_SWAP := 1 << 10
const F_USE_HELD := 1 << 11


static func hello() -> PackedByteArray:
	return PackedByteArray([Type.HELLO, VERSION])


static func refused(reason: Refusal) -> PackedByteArray:
	return PackedByteArray([Type.REFUSED, reason])


static func welcome(player_id: int, tick_rate: int, snapshot: Dictionary) -> PackedByteArray:
	var out := PackedByteArray([Type.WELCOME, VERSION, player_id, tick_rate])
	out.append_array(pack_var(snapshot))
	return out


## `{"version", "player_id", "tick_rate", "snapshot"}`, or `{}`.
static func read_welcome(data: PackedByteArray) -> Dictionary:
	if data.size() < WELCOME_HEADER + 1 or data[0] != Type.WELCOME:
		return {}
	var snapshot: Variant = unpack_var(data, WELCOME_HEADER)
	if typeof(snapshot) != TYPE_DICTIONARY:
		return {}
	return {
		"version": data[1],
		"player_id": data[2],
		"tick_rate": data[3],
		"snapshot": snapshot,
	}


static func tick(step: int, events: Array) -> PackedByteArray:
	var out := PackedByteArray([Type.TICK, 0, 0, 0, 0])
	out.encode_u32(1, step)
	out.append_array(pack_var(events))
	return out


## `{"step", "events"}`, or `{}`.
static func read_tick(data: PackedByteArray) -> Dictionary:
	if data.size() < TICK_HEADER + 1 or data[0] != Type.TICK:
		return {}
	var events: Variant = unpack_var(data, TICK_HEADER)
	if typeof(events) != TYPE_ARRAY:
		return {}
	return {"step": data.decode_u32(1), "events": events}


static func ping(client_ms: int) -> PackedByteArray:
	var out := PackedByteArray([Type.PING, 0, 0, 0, 0])
	out.encode_u32(1, client_ms & 0xFFFFFFFF)
	return out


static func pong(client_ms: int, step: int) -> PackedByteArray:
	var out := PackedByteArray([Type.PONG, 0, 0, 0, 0, 0, 0, 0, 0])
	out.encode_u32(1, client_ms)
	out.encode_u32(5, step)
	return out


# --- Commands ---


static func command(value: NightCommand) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(COMMAND_SIZE)
	out[0] = Type.COMMAND
	out.encode_u32(1, value.seq & 0xFFFFFFFF)
	var motion := value.motion
	out.encode_float(5, motion.move.x)
	out.encode_float(9, motion.move.y)
	out.encode_float(13, motion.yaw)
	out.encode_float(17, motion.pitch)
	var flags := 0
	flags |= F_SPRINT if motion.sprint else 0
	flags |= F_CROUCH if motion.crouch else 0
	flags |= F_JUMP if motion.jump else 0
	flags |= F_AIM if motion.aim else 0
	flags |= F_SWAP_SHOULDER if motion.swap_shoulder else 0
	flags |= F_THROW_OVER if motion.throw_over else 0
	flags |= F_THROW_UNDER if motion.throw_under else 0
	flags |= F_FIRE if value.fire else 0
	flags |= F_RELOAD if value.reload else 0
	flags |= F_USE if value.use else 0
	flags |= F_SWAP if value.swap else 0
	flags |= F_USE_HELD if value.use_held else 0
	out.encode_u16(21, flags)
	_put_vector(out, 23, value.origin)
	_put_vector(out, 35, value.dir)
	return out


## The command in a packet from a client, or null when the packet is not exactly one. Numbers a
## client could poison the simulation with (not-a-number, infinity, a move longer than 1, a
## direction of no length) are made harmless here.
static func read_command(data: PackedByteArray) -> NightCommand:
	if data.size() != COMMAND_SIZE or data[0] != Type.COMMAND:
		return null
	var result := NightCommand.new()
	result.seq = data.decode_u32(1)
	var motion := result.motion
	motion.move = Vector2(data.decode_float(5), data.decode_float(9))
	if not motion.move.is_finite():
		motion.move = Vector2.ZERO
	motion.move = motion.move.limit_length(1.0)
	motion.yaw = _finite(data.decode_float(13))
	motion.pitch = _finite(data.decode_float(17))
	var flags := data.decode_u16(21)
	motion.sprint = flags & F_SPRINT != 0
	motion.crouch = flags & F_CROUCH != 0
	motion.jump = flags & F_JUMP != 0
	motion.aim = flags & F_AIM != 0
	motion.swap_shoulder = flags & F_SWAP_SHOULDER != 0
	motion.throw_over = flags & F_THROW_OVER != 0
	motion.throw_under = flags & F_THROW_UNDER != 0
	result.fire = flags & F_FIRE != 0
	result.reload = flags & F_RELOAD != 0
	result.use = flags & F_USE != 0
	result.swap = flags & F_SWAP != 0
	result.use_held = flags & F_USE_HELD != 0
	result.origin = _get_vector(data, 23)
	result.dir = _get_vector(data, 35)
	if result.dir.length() < 0.001:
		result.dir = Vector3.FORWARD
	result.dir = result.dir.normalized()
	return result


# --- Packed variables ---


static func pack_var(value: Variant) -> PackedByteArray:
	var raw := var_to_bytes(value)
	var out := PackedByteArray([0])
	if raw.size() < COMPRESS_FROM:
		out.append_array(raw)
		return out
	out[0] = 1
	out.resize(5)
	out.encode_u32(1, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


## The value of the packed variable that starts at `offset`; null when it is not one.
static func unpack_var(data: PackedByteArray, offset: int) -> Variant:
	if data.size() <= offset:
		return null
	var raw: PackedByteArray
	if data[offset] == 0:
		raw = data.slice(offset + 1)
	elif data[offset] == 1 and data.size() > offset + 5:
		var size := data.decode_u32(offset + 1)
		if size == 0 or size > MAX_UNPACKED:
			return null
		raw = data.slice(offset + 5).decompress(size, FileAccess.COMPRESSION_ZSTD)
	else:
		return null
	if raw.is_empty():
		return null
	return bytes_to_var(raw)


static func _put_vector(out: PackedByteArray, at: int, value: Vector3) -> void:
	out.encode_float(at, value.x)
	out.encode_float(at + 4, value.y)
	out.encode_float(at + 8, value.z)


static func _get_vector(data: PackedByteArray, at: int) -> Vector3:
	var value := Vector3(
		data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8)
	)
	return value if value.is_finite() else Vector3.ZERO


static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0
