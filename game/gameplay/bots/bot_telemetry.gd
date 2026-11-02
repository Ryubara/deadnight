class_name BotTelemetry
extends RefCounted
## What a bot reports about itself: counters, the time its thinking takes, a short list of named
## events (a brain switched off, ...), the hash of every command it sent, and a ring buffer of its
## last decisions with the beliefs that produced them, to be dumped when a bot gets stuck, dies or
## a test fails. Nothing here decides anything.

## Decisions the ring buffer keeps.
const RING_SIZE := 300
## Think times kept for the percentiles.
const SAMPLE_LIMIT := 4096
## The width, in degrees, of the buckets the view goes into the command hash in.
const SIGNATURE_DEGREES := 5.0

var counters: Dictionary = {}
var events: Array[Dictionary] = []
## The running hash of every command sent (see `note_command`) and how many there were.
var command_hash := 0
var commands := 0
## Whether commands are hashed (a replay or golden test turns it on; a running night does not pay
## for it).
var hashing := false

var _ring: Array[Dictionary] = []
var _next := 0
var _think_us := PackedInt32Array()


func count(name: StringName, by: int = 1) -> void:
	counters[name] = counters.get(name, 0) + by


## A named thing that happened, kept in order: `{name, tick, ...detail}`.
func event(name: StringName, tick: int, detail: Dictionary = {}) -> void:
	var entry := {"name": name, "tick": tick}
	entry.merge(detail)
	events.append(entry)
	count(name)


func has_event(name: StringName) -> bool:
	for entry in events:
		if entry["name"] == name:
			return true
	return false


## The decision of one think, with what the bot believed.
func decide(entry: Dictionary) -> void:
	if _ring.size() < RING_SIZE:
		_ring.append(entry)
	else:
		_ring[_next] = entry
	_next = (_next + 1) % RING_SIZE


## The last decisions, oldest first.
func recent() -> Array[Dictionary]:
	if _ring.size() < RING_SIZE:
		return _ring.duplicate()
	var ordered: Array[Dictionary] = []
	for i in RING_SIZE:
		ordered.append(_ring[(_next + i) % RING_SIZE])
	return ordered


func record_think(microseconds: int) -> void:
	count(&"thinks")
	if _think_us.size() < SAMPLE_LIMIT:
		_think_us.append(microseconds)
	else:
		_think_us[counters[&"thinks"] % SAMPLE_LIMIT] = microseconds


## The `fraction` (0 to 1) quantile of the think times, microseconds; 0 when there are none.
func think_us(fraction: float) -> int:
	if _think_us.is_empty():
		return 0
	var sorted := _think_us.duplicate()
	sorted.sort()
	return sorted[mini(int(floorf(fraction * float(sorted.size()))), sorted.size() - 1)]


## Folds one command, as it is sent, into the hash (when `hashing`).
func note_command(action: Dictionary) -> void:
	commands += 1
	if hashing:
		command_hash = hash([command_hash, signature(action)])


## What of a command goes into the hash: the buttons, the walking direction in eighths of a turn,
## and where the view points in buckets of `SIGNATURE_DEGREES`. Nothing finer: the last bits of a
## float differ between machines (and a body moved by the physics engine differs between runs), and
## a hash that moves with them would say the bots changed when they did not.
static func signature(action: Dictionary) -> String:
	var motion: Dictionary = action["motion"]
	var move: Vector2 = motion["move"]
	var heading := 0
	if move.length() > 0.1:
		heading = posmod(roundi(atan2(move.x, move.y) / (PI / 4.0)), 8) + 1
	return (
		"%d%d%d%d%d%d.%d.%d.%d"
		% [
			int(action["fire"]),
			int(action["reload"]),
			int(action["swap"]),
			int(action["use"]),
			int(motion["sprint"]),
			int(motion["jump"]),
			heading,
			roundi(rad_to_deg(motion["yaw"]) / SIGNATURE_DEGREES),
			roundi(rad_to_deg(motion["pitch"]) / SIGNATURE_DEGREES),
		]
	)


## One line of JSON for the night's report.
func report(extra: Dictionary = {}) -> String:
	var line := {
		"counters": counters,
		"think_us_p50": think_us(0.5),
		"think_us_p99": think_us(0.99),
		"commands": commands,
		"command_hash": command_hash,
		"events": events.map(func(entry: Dictionary) -> String: return String(entry["name"])),
	}
	line.merge(extra)
	return JSON.stringify(line)
