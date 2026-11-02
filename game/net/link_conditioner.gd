class_name LinkConditioner
extends RefCounted
## A bad network between two ends of a WebSocket, for tests and bots: every packet is held back
## `delay` seconds (plus a random `jitter` either way) before it is let through, in the order it
## came, as TCP would deliver it: a packet never overtakes the one before it, and a `stall` (a
## retransmission) holds everything behind it too. Nothing is lost, because a WebSocket cannot
## lose; what the spike's UDP link called loss is a stall here.
##
## The caller gives the time (seconds), so a test can use real time or its own clock.

var delay := 0.05
var jitter := 0.0
## The chance that a packet needs a retransmission, and how long that costs.
var stall_chance := 0.0
var stall := 0.2

## How many packets went through and how many were stalled, for the numbers of a run.
var passed := 0
var stalled := 0

var _rng := RandomNumberGenerator.new()
var _queue: Array[Dictionary] = []
var _last_at := 0.0


func _init(p_delay := 0.05, p_jitter := 0.0, seed_value := 1) -> void:
	delay = p_delay
	jitter = p_jitter
	_rng.seed = seed_value


## Holds `data`, which arrived at `now`.
func push(data: PackedByteArray, now: float) -> void:
	var at := now + delay + _rng.randf_range(-jitter, jitter)
	if stall_chance > 0.0 and _rng.randf() < stall_chance:
		at += stall
		stalled += 1
	# In order: nothing arrives before what was sent ahead of it.
	at = maxf(at, _last_at)
	_last_at = at
	_queue.append({"at": at, "data": data})


## The packets that are due at `now`, oldest first.
func due(now: float) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	while not _queue.is_empty() and _queue[0]["at"] <= now:
		out.append(_queue.pop_front()["data"])
		passed += 1
	return out


## Packets still held.
func waiting() -> int:
	return _queue.size()
