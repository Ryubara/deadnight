class_name BotBeliefs
extends RefCounted
## What a bot believes about the night right now: the zombies it has made out, the ones it heard,
## the blows it felt. The brain reads this and never the frame, so what is not in here, the bot
## does not know. A plain dictionary per contact:
##
##   id, position (where it was last seen), velocity (m/s, from the last two sightings), look,
##   mode, first_seen / last_seen / believed_at (seconds on the bot's clock), visible (clear ray
##   at the last look), tracked_at (the clock of the last position update)
##
## A contact is *pending* until `believed_at` (the reaction delay), *believed* after, and a
## believed contact that is no longer seen is *remembered* until the memory runs out. Only a
## believed contact that is visible may be shot at.

## Range classes of a zombie heard but not seen.
const NEAR := &"near"
const VERY_NEAR := &"very_near"

var contacts: Dictionary[int, Dictionary] = {}
## `{yaw, range_class, at}` per zombie heard out of sight at the last look: a direction, never a
## position.
var heard: Array[Dictionary] = []
## `{yaw, at}`: where a blow that landed came from (the rules' bearing, as a view yaw).
var blows: Array[Dictionary] = []
## The players of the frame by id, as a person sees them: `{pos, facing, health, downed, dead, bot
## (the roster labels bots), velocity (from the last two frames)}`. The bot itself is in it, under
## its own id in `me`.
var teammates: Dictionary = {}
var me := -1
var now := 0.0


## Believed and in sight, nearest first (ties by id): the zombies the bot may shoot at.
func targets(from: Vector3) -> Array[Dictionary]:
	var pairs: Array[Vector2] = []
	for id in contacts:
		var contact := contacts[id]
		if is_believed(contact) and contact["visible"]:
			pairs.append(Vector2(_flat(from, contact["position"]), float(id)))
	pairs.sort()
	var found: Array[Dictionary] = []
	for pair in pairs:
		found.append(contacts[int(pair.y)])
	return found


## Believed but out of sight: avoided and looked toward, never shot at.
func remembered() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for id in contacts:
		var contact := contacts[id]
		if is_believed(contact) and not contact["visible"]:
			found.append(contact)
	return found


func is_believed(contact: Dictionary) -> bool:
	return contact["believed_at"] <= now


func contact(id: int) -> Dictionary:
	return contacts.get(id, {})


## Where a remembered contact probably is now: its last position carried on at its last speed, for
## no longer than the memory lasts.
func guess(contact_of: Dictionary, memory_seconds: float) -> Vector3:
	var gone := minf(now - contact_of["last_seen"], memory_seconds)
	return contact_of["position"] + contact_of["velocity"] * gone


## The nearest distance to anything the bot believes in or hears, or INF.
func nearest_threat(from: Vector3, memory_seconds: float) -> float:
	var best := INF
	for id in contacts:
		var contact_of := contacts[id]
		if is_believed(contact_of):
			best = minf(best, _flat(from, guess(contact_of, memory_seconds)))
	for sound in heard:
		best = minf(best, 2.0 if sound["range_class"] == VERY_NEAR else 4.0)
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
