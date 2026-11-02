class_name PeerLimits
extends RefCounted
## What one connection may send a game server, and what happens when it sends more: the packet
## size, how often each kind of message may come, and a strike count that hangs up on a peer that
## keeps breaking either (`judge`). An honest client is nowhere near these numbers: it sends a
## command 60 times a second (and up to four seconds of them may arrive together after a stall), a
## ping twice, a look once.
##
## A packet over its rate is dropped and costs a strike; one the server cannot make sense of (empty,
## too long, an unknown type, the wrong size for its type) costs more. Strikes wear off, so a
## client that bunches after a stall is forgiven, and a flood is cut off within a fraction of a
## second. Time is the caller's.

enum Verdict { ACCEPT, DROP, KICK }

## No message a client sends is longer; anything beyond is a hostile or broken client.
const MAX_PACKET := 64
## Strikes at which the peer is hung up on, how many wear off a second, and what each fault costs.
const KICK_AT := 100.0
const FORGIVE_PER_SECOND := 5.0
const STRIKE_RATE := 0.5
const STRIKE_BAD := 5.0

## Per message type: the sustained messages a second, and the burst that may come at once (a stall
## of a second or so, then everything late together).
const RATES := {
	NetWire.Type.HELLO: Vector2(1.0, 2.0),
	NetWire.Type.COMMAND: Vector2(90.0, 240.0),
	NetWire.Type.PING: Vector2(4.0, 6.0),
	LookWire.Type.LOOK: Vector2(1.0, 3.0),
}

## Counts, for the log and the tests.
var dropped := 0
var malformed := 0
var strikes := 0.0

var _buckets: Dictionary[int, TokenBucket] = {}
var _at := -1.0


func _init() -> void:
	for type: int in RATES:
		_buckets[type] = TokenBucket.new(RATES[type].x, RATES[type].y)


## The exact size of a message of this type, or -1 when the server takes no such message.
static func size_of(type: int) -> int:
	match type:
		NetWire.Type.HELLO:
			return NetWire.HELLO_HEADER
		NetWire.Type.COMMAND:
			return NetWire.COMMAND_SIZE
		NetWire.Type.PING:
			return 5
		LookWire.Type.LOOK:
			return 1 + CharacterLook.wire_size()
	return -1


## Whether a message of this type may be this long: a hello is the version, the resume token when
## the client is coming back and the backend's ticket, so its length varies.
static func fits(type: int, size: int) -> bool:
	if type == NetWire.Type.HELLO:
		return size >= NetWire.HELLO_MIN and size <= NetWire.MAX_HELLO
	return size_of(type) == size


## What to do with a packet that came at time `now`.
func judge(data: PackedByteArray, now: float) -> Verdict:
	_forgive(now)
	var most := (
		NetWire.MAX_HELLO if not data.is_empty() and data[0] == NetWire.Type.HELLO else MAX_PACKET
	)
	if data.is_empty() or data.size() > most:
		return _strike(STRIKE_BAD, true)
	var type := data[0]
	if not fits(type, data.size()):
		return _strike(STRIKE_BAD, true)
	if not _buckets[type].take(now):
		return _strike(STRIKE_RATE, false)
	return Verdict.ACCEPT


## A packet that passed `judge` but whose content the server then refused (a command out of
## order, a look that is not one).
func fault(now: float) -> Verdict:
	_forgive(now)
	return _strike(STRIKE_BAD, true)


func _forgive(now: float) -> void:
	if _at >= 0.0:
		strikes = maxf(0.0, strikes - (now - _at) * FORGIVE_PER_SECOND)
	_at = now


func _strike(cost: float, is_malformed: bool) -> Verdict:
	strikes += cost
	if is_malformed:
		malformed += 1
	else:
		dropped += 1
	return Verdict.KICK if strikes >= KICK_AT else Verdict.DROP
