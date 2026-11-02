class_name ZombieDelta
extends RefCounted
## The zombies of a frame as a difference against the ones a client already has (#57), over the
## connection that never reorders or loses: only the zombies that changed are sent, and of those
## only what changed. `ZombieCodec` is still the picture (13 bytes a zombie, whole); this is what
## goes between two of them.
##
## An entry here is the 13 bytes of a `ZombieCodec` zombie: u16 id, s16 x, y, z (cm), u8 yaw, u8
## mode, u8 episode, u8 speed, u8 look. A delta is
##
##   u8 sequence, u16 changed, u16 gone, then each changed zombie: u16 id, u8 flags and what the
##   flags name, then each gone id as a u16.
##
##   POSITION  3 x s8 centimetres moved (a zombie that moved further is `FAR`)
##   FAR       with POSITION: 3 x s16, the position whole
##   YAW       u8
##   SPEED     u8
##   MODE      u8 mode, u8 episode
##   LOOK      u8
##   NEW       the zombie is not in the base: every field follows, as in the entry
##
## `sequence` makes two deltas never the same bytes, so the frame difference (`FrameDelta`) that
## carries them cannot drop one that repeats the one before.

const ENTRY := ZombieCodec.ENTRY_BYTES
const HEADER := 5

const POSITION := 1 << 0
const FAR := 1 << 1
const YAW := 1 << 2
const SPEED := 1 << 3
const MODE := 1 << 4
const LOOK := 1 << 5
const NEW := 1 << 6
const STEP_LIMIT := 127


## The entries of `ZombieCodec` bytes by zombie id.
static func entries_of(codec_bytes: PackedByteArray) -> Dictionary[int, PackedByteArray]:
	var entries: Dictionary[int, PackedByteArray] = {}
	if codec_bytes.size() < ZombieCodec.HEADER_BYTES:
		return entries
	var count := codec_bytes.decode_u16(0)
	if codec_bytes.size() < ZombieCodec.HEADER_BYTES + ENTRY * count:
		return entries
	for i in count:
		var at := ZombieCodec.HEADER_BYTES + ENTRY * i
		entries[codec_bytes.decode_u16(at)] = codec_bytes.slice(at, at + ENTRY)
	return entries


## `ZombieCodec` bytes of entries (in the order of their ids).
static func whole(entries: Dictionary[int, PackedByteArray]) -> PackedByteArray:
	var ids: Array = entries.keys()
	ids.sort()
	var out := PackedByteArray()
	out.resize(ZombieCodec.HEADER_BYTES)
	out.encode_u16(0, ids.size())
	for id: int in ids:
		out.append_array(entries[id])
	return out


## What changed from `base` to `next` (both entries by id), as bytes; `sequence` is the number of
## this delta (it wraps at 256).
static func diff(
	base: Dictionary[int, PackedByteArray], next: Dictionary[int, PackedByteArray], sequence: int
) -> PackedByteArray:
	var body := PackedByteArray()
	var changed := 0
	var ids: Array = next.keys()
	ids.sort()
	for id: int in ids:
		var was: PackedByteArray = base.get(id, PackedByteArray())
		if was == next[id]:
			continue
		changed += 1
		_put_entry(body, id, was, next[id])
	var gone := 0
	var gone_ids: Array = base.keys()
	gone_ids.sort()
	for id: int in gone_ids:
		if not next.has(id):
			gone += 1
			body.resize(body.size() + 2)
			body.encode_u16(body.size() - 2, id)
	var out := PackedByteArray([sequence & 0xFF, 0, 0, 0, 0])
	out.encode_u16(1, changed)
	out.encode_u16(3, gone)
	out.append_array(body)
	return out


## The entries `delta` makes of `base`, or `{}` with `ok` false when the bytes are not a delta of it
## (a hostile or broken server cannot make a client read past the end or invent a zombie from a
## base it does not have).
static func apply(base: Dictionary[int, PackedByteArray], delta: PackedByteArray) -> Dictionary:
	var next: Dictionary[int, PackedByteArray] = base.duplicate()
	if delta.size() < HEADER:
		return {"ok": false, "entries": base}
	var changed := delta.decode_u16(1)
	var gone := delta.decode_u16(3)
	var at := HEADER
	for _i in changed:
		if at + 3 > delta.size():
			return {"ok": false, "entries": base}
		var id := delta.decode_u16(at)
		var flags := delta.decode_u8(at + 2)
		at += 3
		var entry: PackedByteArray = next.get(id, PackedByteArray())
		if flags & NEW != 0:
			entry = PackedByteArray()
			entry.resize(ENTRY)
			entry.encode_u16(0, id)
		elif entry.size() != ENTRY:
			return {"ok": false, "entries": base}
		else:
			entry = entry.duplicate()
		var read := _read_fields(entry, delta, at, flags)
		if read < 0:
			return {"ok": false, "entries": base}
		at = read
		next[id] = entry
	for _i in gone:
		if at + 2 > delta.size():
			return {"ok": false, "entries": base}
		next.erase(delta.decode_u16(at))
		at += 2
	return {"ok": at == delta.size(), "entries": next if at == delta.size() else base}


static func _put_entry(
	out: PackedByteArray, id: int, was: PackedByteArray, now: PackedByteArray
) -> void:
	var fresh := was.is_empty()
	var flags := NEW if fresh else 0
	var fields := PackedByteArray()
	var moved := Vector3i(
		now.decode_s16(2) - (0 if fresh else was.decode_s16(2)),
		now.decode_s16(4) - (0 if fresh else was.decode_s16(4)),
		now.decode_s16(6) - (0 if fresh else was.decode_s16(6))
	)
	if fresh:
		flags |= POSITION | FAR | YAW | SPEED | MODE | LOOK
	else:
		if moved != Vector3i.ZERO:
			flags |= POSITION
			if (
				absi(moved.x) > STEP_LIMIT
				or absi(moved.y) > STEP_LIMIT
				or absi(moved.z) > STEP_LIMIT
			):
				flags |= FAR
		if now[8] != was[8]:
			flags |= YAW
		if now[11] != was[11]:
			flags |= SPEED
		if now[9] != was[9] or now[10] != was[10]:
			flags |= MODE
		if now[12] != was[12]:
			flags |= LOOK
	if flags & POSITION != 0:
		if flags & FAR != 0:
			for axis in 3:
				fields.resize(fields.size() + 2)
				fields.encode_s16(fields.size() - 2, now.decode_s16(2 + 2 * axis))
		else:
			for delta in [moved.x, moved.y, moved.z]:
				fields.append(delta & 0xFF)
	if flags & YAW != 0:
		fields.append(now[8])
	if flags & SPEED != 0:
		fields.append(now[11])
	if flags & MODE != 0:
		fields.append(now[9])
		fields.append(now[10])
	if flags & LOOK != 0:
		fields.append(now[12])
	out.resize(out.size() + 3)
	out.encode_u16(out.size() - 3, id)
	out.encode_u8(out.size() - 1, flags)
	out.append_array(fields)


## Reads the fields `flags` name from `delta` at `at` into `entry`; the position after them, or -1.
static func _read_fields(
	entry: PackedByteArray, delta: PackedByteArray, at: int, flags: int
) -> int:
	var need := 0
	if flags & POSITION != 0:
		need += 6 if flags & FAR != 0 else 3
	need += (1 if flags & YAW != 0 else 0) + (1 if flags & SPEED != 0 else 0)
	need += (2 if flags & MODE != 0 else 0) + (1 if flags & LOOK != 0 else 0)
	if at + need > delta.size():
		return -1
	if flags & POSITION != 0:
		for axis in 3:
			var place := 2 + 2 * axis
			if flags & FAR != 0:
				entry.encode_s16(place, delta.decode_s16(at))
				at += 2
			else:
				entry.encode_s16(
					place, clampi(entry.decode_s16(place) + delta.decode_s8(at), -32768, 32767)
				)
				at += 1
	if flags & YAW != 0:
		entry[8] = delta[at]
		at += 1
	if flags & SPEED != 0:
		entry[11] = delta[at]
		at += 1
	if flags & MODE != 0:
		entry[9] = delta[at]
		entry[10] = delta[at + 1]
		at += 2
	if flags & LOOK != 0:
		entry[12] = delta[at]
		at += 1
	return at
