class_name NetWire
extends RefCounted
## The bytes of a night's connection (protocol version 5; version 4 had a ping of 5 bytes with no
## round trip in it, version 3 had no ticket in the hello,
## version 2 no resume token, version 1 sent a command as 47 bytes of floats), one message to a
## WebSocket frame: a type byte, then the fields. `LookWire` continues the numbering with types 8
## and 9.
##
## HELLO    C->S  u8 type=1, u8 version, u8 token length (0 or 8), the resume token the last WELCOME
##                gave (a client that lost its socket asks for its seat back), then the rest is the
##                ticket of the platform backend as text (empty when the server has no backend)
## WELCOME  S->C  u8 type=2, u8 version, u8 player_id, u8 tick_rate, 8 bytes of resume token, then a
##                packed variable: the rules' snapshot (`GameRules.to_dict()`), for a HUD that joins
##                in the middle (or comes back)
## COMMAND  C->S  u8 type=3, u32 seq, s8 move x/y, u16 yaw, s16 pitch, u16 flags, s16 origin x/y/z
##                (centimetres), u16 shot yaw, s16 shot pitch (fixed, `COMMAND_SIZE` = 23 bytes in
##                all; the steps are `CommandCodec`'s)
## TICK     S->C  u8 type=4, u32 server step, then a packed variable: the array of events since the
##                last TICK, the frame last; a frame after the first only carries what changed
##                (`FrameDelta`)
## PING     C->S  u8 type=6, u32 client milliseconds, u16 the round trip the last PONG measured, in
##                milliseconds (`NO_RTT` before the first), for the scoreboard (7 bytes in all)
## PONG     S->C  u8 type=7, u32 the same, u32 server step
## REFUSED  S->C  u8 type=10, u8 reason (`Refusal`), u8 the server's protocol version; the server
##                closes the connection after it
##
## A packed variable is a flag byte (0 plain, 1 compressed with Zstandard), when compressed the u32
## size it has once unpacked, and the `var_to_bytes` of the value. The server decodes nothing but
## the fixed layouts above from a client; only the clients decode variables, and without objects.
##
## Everything a decoder reads is length-checked first, and a short, long or unknown packet is
## dropped (an empty Dictionary, or null).

enum Type { HELLO = 1, WELCOME = 2, COMMAND = 3, TICK = 4, PING = 6, PONG = 7, REFUSED = 10 }
enum Refusal { VERSION = 1, FULL = 2, DENIED = 3 }

## The protocol version of this build. Raise it whenever a layout above changes (a field added,
## resized or reordered, a type renumbered). New keys in the events and the frame do not need it:
## clients ignore keys they do not know. The policy is in docs/research/multiplayer.md.
const VERSION := 5
## The oldest client version a server of this build still takes. Equal to `VERSION` while the web
## client and the server ship from one commit; lower it only for a layout both versions can read.
const MIN_VERSION := 5
## Port of a game server unless told otherwise. (Not 9080: the Godot editor's MCP bridge listens
## there on the maintainer's machine and Windows lets a second listener bind it silently.)
const DEFAULT_PORT := 8910
const COMMAND_SIZE := 23
const PING_SIZE := 7
## What a ping says when the client has not measured a round trip yet, and the most it can say.
const NO_RTT := 0xFFFF
## The resume token a WELCOME gives: random, one for each connection, good for taking back the seat.
const TOKEN_SIZE := 8
const WELCOME_HEADER := 4 + TOKEN_SIZE
## Type, version and the length of the resume token; a ticket makes a hello the longest message.
const HELLO_HEADER := 3
## The shortest hello there has been (version 3 and before had no token length): enough to read the
## version of an old client.
const HELLO_MIN := 2
const MAX_HELLO := 1024
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


static func hello(
	token: PackedByteArray = PackedByteArray(), ticket: String = ""
) -> PackedByteArray:
	var kept := token.size() == TOKEN_SIZE
	var out := PackedByteArray([Type.HELLO, VERSION, TOKEN_SIZE if kept else 0])
	if kept:
		out.append_array(token)
	out.append_array(ticket.to_utf8_buffer())
	return out


## The protocol version a hello says (its second byte, whatever follows), or -1 when the packet is
## not a hello: a server can turn an old client away by it though it cannot read the rest.
static func hello_version(data: PackedByteArray) -> int:
	return data[1] if data.size() >= 2 and data[0] == Type.HELLO else -1


## `{"version", "token", "ticket"}` (the token empty when the client is new, the ticket empty when
## it has none), or `{}` when the packet is not a hello.
static func read_hello(data: PackedByteArray) -> Dictionary:
	if data.size() < HELLO_HEADER or data[0] != Type.HELLO:
		return {}
	var token_size := data[2]
	if (token_size != 0 and token_size != TOKEN_SIZE) or data.size() < HELLO_HEADER + token_size:
		return {}
	var ticket_at := HELLO_HEADER + token_size
	return {
		"version": data[1],
		"token": data.slice(HELLO_HEADER, ticket_at),
		"ticket": data.slice(ticket_at).get_string_from_utf8(),
	}


static func refused(reason: Refusal) -> PackedByteArray:
	return PackedByteArray([Type.REFUSED, reason, VERSION])


## Whether a server of this build takes a client of that version.
static func accepts(version: int) -> bool:
	return version >= MIN_VERSION and version <= VERSION


static func welcome(
	player_id: int, tick_rate: int, token: PackedByteArray, snapshot: Dictionary
) -> PackedByteArray:
	var out := PackedByteArray([Type.WELCOME, VERSION, player_id, tick_rate])
	out.append_array(token)
	out.append_array(pack_var(snapshot))
	return out


## `{"version", "player_id", "tick_rate", "token", "snapshot"}`, or `{}`.
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
		"token": data.slice(4, WELCOME_HEADER),
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


## `rtt_ms` is the client's last measured round trip (negative for none yet).
static func ping(client_ms: int, rtt_ms := -1.0) -> PackedByteArray:
	var out := PackedByteArray([Type.PING, 0, 0, 0, 0, 0, 0])
	out.encode_u32(1, client_ms & 0xFFFFFFFF)
	out.encode_u16(5, NO_RTT if rtt_ms < 0.0 else mini(roundi(rtt_ms), NO_RTT - 1))
	return out


## The round trip a client reported in its ping, in milliseconds, or -1 for none (or a ping of the
## wrong size).
static func read_ping_rtt(data: PackedByteArray) -> int:
	if data.size() != PING_SIZE or data[0] != Type.PING:
		return -1
	var rtt := data.decode_u16(5)
	return -1 if rtt == NO_RTT else rtt


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
	var push := CommandCodec.move_bytes(motion.move)
	out.encode_s8(5, push.x)
	out.encode_s8(6, push.y)
	out.encode_u16(7, CommandCodec.yaw_step(motion.yaw))
	out.encode_s16(9, CommandCodec.look_step(motion.pitch))
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
	out.encode_u16(11, flags)
	out.encode_s16(13, CommandCodec.point_step(value.origin.x))
	out.encode_s16(15, CommandCodec.point_step(value.origin.y))
	out.encode_s16(17, CommandCodec.point_step(value.origin.z))
	var aim := CommandCodec.direction_angles(value.dir)
	out.encode_u16(19, CommandCodec.yaw_step(aim.x))
	out.encode_s16(21, CommandCodec.look_step(aim.y))
	return out


## The command in a packet from a client, or null when the packet is not exactly one. Every field
## is an integer step, so nothing a client sends is not-a-number or infinite; a move longer than 1
## is shortened, and a direction is always a unit vector.
static func read_command(data: PackedByteArray) -> NightCommand:
	if data.size() != COMMAND_SIZE or data[0] != Type.COMMAND:
		return null
	var result := NightCommand.new()
	result.seq = data.decode_u32(1)
	var motion := result.motion
	motion.move = CommandCodec.move_from_bytes(data.decode_s8(5), data.decode_s8(6))
	motion.yaw = CommandCodec.yaw_from_step(data.decode_u16(7))
	motion.pitch = CommandCodec.look_from_step(data.decode_s16(9))
	var flags := data.decode_u16(11)
	motion.sprint = flags & F_SPRINT != 0
	motion.crouch = flags & F_CROUCH != 0
	motion.jump = flags & F_JUMP != 0
	motion.aim = flags & F_AIM != 0
	motion.swap_shoulder = flags & F_SWAP_SHOULDER != 0
	motion.throw_over = flags & F_THROW_OVER != 0
	motion.throw_under = flags & F_THROW_UNDER != 0
	result.fire = flags & F_FIRE != 0
	motion.fire = result.fire
	result.reload = flags & F_RELOAD != 0
	result.use = flags & F_USE != 0
	result.swap = flags & F_SWAP != 0
	result.use_held = flags & F_USE_HELD != 0
	result.origin = Vector3(
		CommandCodec.point_from_step(data.decode_s16(13)),
		CommandCodec.point_from_step(data.decode_s16(15)),
		CommandCodec.point_from_step(data.decode_s16(17))
	)
	result.dir = CommandCodec.direction_from_angles(
		CommandCodec.yaw_from_step(data.decode_u16(19)),
		CommandCodec.look_from_step(data.decode_s16(21))
	)
	return result


## The command as the server will read it: what a predicting client moves its own body with, so its
## prediction and the server's run use the same numbers. Only what travels is kept (the player id
## the server takes from the connection and the muzzle are carried over untouched).
static func quantize(value: NightCommand) -> NightCommand:
	var result := read_command(command(value))
	result.player_id = value.player_id
	result.muzzle = value.muzzle
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
