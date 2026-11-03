class_name BotBeliefs
extends RefCounted
## What a bot believes about the night right now: the zombies it has made out, the ones it heard,
## the blows it felt. The brain reads this and never the frame, so what is not in here, the bot
## does not know. A plain dictionary per contact:
##
##   id, position (where it was last seen), velocity (m/s, from the last two sightings), look,
##   mode, first_seen / last_seen / believed_at (seconds on the bot's clock), visible (clear ray
##   at the last look), tracked_at (the clock of the last position update), yaw (where it faces),
##   episode (the swing counter) and attack_at (the clock when this swing was first seen, or -1
##   when it is not swinging)
##
## A contact is *pending* until `believed_at` (the reaction delay), *believed* after, and a
## believed contact that is no longer seen is *remembered* until the memory runs out. Only a
## believed contact that is visible may be shot at.

## Range classes of a zombie heard but not seen.
const NEAR := &"near"
const VERY_NEAR := &"very_near"
## Grenades a player starts the night with (`ExplosiveTuning.start_grenades`; a test holds the two
## together).
const START_GRENADES := 2

var contacts: Dictionary[int, Dictionary] = {}
## How many contacts have ever been made out (a counter that moves when a new one appears), so that
## what only matters at the first sight is looked at then and not every think.
var contact_seq := 0
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
## The standing order of the team's bots for this one (`BotOrders.current`): `{order, issuer_id,
## at}`. Roam until a person says otherwise.
var order: Dictionary = {"order": BotOrders.DEFAULT, "issuer_id": 0, "at": Vector3.INF}
## Grenades the bot carries: the count a player starts with until the rules say otherwise
## (`grenade_count_changed`: a throw, a refill at a round's start, a purchase).
var grenades := START_GRENADES
## The special round in play (`round_started`'s `special_id`), or empty in an ordinary round.
var special: StringName = &""
## The purchases the server refused since the brain last looked: `{item, result}`.
var denials: Array[Dictionary] = []
## Things that happened to the bot or the night since the brain last looked, for the callouts:
## `{kind}` (`revived`, `door_bought`, `fuel_low`, `breach_open`, `trapped`).
var moments: Array[Dictionary] = []
## The clock when the bot last bought something.
var purchased_at := -INF
## Rays the last look cast: how busy this think already was.
var rays := 0
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
