class_name Protocol
extends RefCounted
## The wire format. Every packet is one WebSocket message: a type byte, then fixed
## little-endian fields.
## Version 1. The version is only carried in HELLO/WELCOME (the handshake), not in every packet.
##
## HELLO     C->S  u8 type=1, u8 version
## WELCOME   S->C  u8 type=2, u8 version, u8 player_id, u8 tick_rate, u32 server_tick
## INPUT     C->S  u8 type=3, u32 ack_tick, u32 first_seq, u8 count, count x (i8 x, i8 y)
##                 (the newest `count` inputs, oldest first; seq = first_seq + index)
## SNAPSHOT  S->C  u8 type=4, u32 tick, u32 ack_seq, u32 baseline_tick, u8 count, then per player:
##                 baseline_tick == 0 (full):  u8 id, i16 x_cm, i16 y_cm
##                 baseline_tick != 0 (delta): u8 id, i8 dx_cm, i8 dy_cm  (only players that moved)
## EVENT     S->C  u8 type=5, u8 kind (1 joined, 2 left), u8 player_id
## PING      C->S  u8 type=6, u32 client_tick
## PONG      S->C  u8 type=7, u32 client_tick (echoed), u32 server_tick

enum Type { HELLO = 1, WELCOME = 2, INPUT = 3, SNAPSHOT = 4, EVENT = 5, PING = 6, PONG = 7 }
enum EventKind { JOINED = 1, LEFT = 2 }

const VERSION := 1
const DELTA_LIMIT_CM := 127


static func hello() -> PackedByteArray:
	var b := _buffer(Type.HELLO)
	b.put_u8(VERSION)
	return b.data_array


static func welcome(player_id: int, tick_rate: int, server_tick: int) -> PackedByteArray:
	var b := _buffer(Type.WELCOME)
	b.put_u8(VERSION)
	b.put_u8(player_id)
	b.put_u8(tick_rate)
	b.put_u32(server_tick)
	return b.data_array


static func input(ack_tick: int, first_seq: int, dirs: Array[Vector2i]) -> PackedByteArray:
	var b := _buffer(Type.INPUT)
	b.put_u32(ack_tick)
	b.put_u32(first_seq)
	b.put_u8(dirs.size())
	for dir in dirs:
		b.put_8(dir.x)
		b.put_8(dir.y)
	return b.data_array


## `entries` holds absolute centimetres for a full snapshot (baseline_tick 0), or deltas otherwise.
static func snapshot(
	tick: int, ack_seq: int, baseline_tick: int, entries: Dictionary[int, Vector2i]
) -> PackedByteArray:
	var b := _buffer(Type.SNAPSHOT)
	b.put_u32(tick)
	b.put_u32(ack_seq)
	b.put_u32(baseline_tick)
	b.put_u8(entries.size())
	for id in entries:
		b.put_u8(id)
		if baseline_tick == 0:
			b.put_16(entries[id].x)
			b.put_16(entries[id].y)
		else:
			b.put_8(entries[id].x)
			b.put_8(entries[id].y)
	return b.data_array


static func event(kind: EventKind, player_id: int) -> PackedByteArray:
	var b := _buffer(Type.EVENT)
	b.put_u8(kind)
	b.put_u8(player_id)
	return b.data_array


static func ping(client_tick: int) -> PackedByteArray:
	var b := _buffer(Type.PING)
	b.put_u32(client_tick)
	return b.data_array


static func pong(client_tick: int, server_tick: int) -> PackedByteArray:
	var b := _buffer(Type.PONG)
	b.put_u32(client_tick)
	b.put_u32(server_tick)
	return b.data_array


## Decodes any packet to a Dictionary with a "type" key; an empty Dictionary means malformed.
static func decode(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {}
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var type := b.get_u8()
	match type:
		Type.HELLO:
			return {"type": type, "version": b.get_u8()} if data.size() >= 2 else {}
		Type.WELCOME:
			if data.size() < 8:
				return {}
			return {
				"type": type,
				"version": b.get_u8(),
				"player_id": b.get_u8(),
				"tick_rate": b.get_u8(),
				"server_tick": b.get_u32(),
			}
		Type.INPUT:
			return _decode_input(b, data.size())
		Type.SNAPSHOT:
			return _decode_snapshot(b, data.size())
		Type.EVENT:
			if data.size() < 3:
				return {}
			return {"type": type, "kind": b.get_u8(), "player_id": b.get_u8()}
		Type.PING:
			return {"type": type, "client_tick": b.get_u32()} if data.size() >= 5 else {}
		Type.PONG:
			if data.size() < 9:
				return {}
			return {"type": type, "client_tick": b.get_u32(), "server_tick": b.get_u32()}
	return {}


static func _decode_input(b: StreamPeerBuffer, size: int) -> Dictionary:
	if size < 10:
		return {}
	var result := {"type": Type.INPUT, "ack_tick": b.get_u32(), "first_seq": b.get_u32()}
	var count := b.get_u8()
	if size < 10 + count * 2:
		return {}
	var dirs: Array[Vector2i] = []
	for i in count:
		dirs.append(Vector2i(b.get_8(), b.get_8()))
	result["dirs"] = dirs
	return result


static func _decode_snapshot(b: StreamPeerBuffer, size: int) -> Dictionary:
	if size < 14:
		return {}
	var result := {
		"type": Type.SNAPSHOT,
		"tick": b.get_u32(),
		"ack_seq": b.get_u32(),
		"baseline_tick": b.get_u32(),
	}
	var count := b.get_u8()
	var per_entry := 5 if result["baseline_tick"] == 0 else 3
	if size < 14 + count * per_entry:
		return {}
	var entries: Dictionary[int, Vector2i] = {}
	for i in count:
		var id := b.get_u8()
		if per_entry == 5:
			entries[id] = Vector2i(b.get_16(), b.get_16())
		else:
			entries[id] = Vector2i(b.get_8(), b.get_8())
	result["entries"] = entries
	return result


static func _buffer(type: Type) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.put_u8(type)
	return b
