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
## The zombies every screen outlines through the walls (`BotHunt.marked`), as the frame's entries:
## empty until the round is down to its last few. The one place the bot is told where the dead are
## out of sight, because a person is (`ZombieMarks`).
var last_dead: Array[Dictionary] = []
## The standing order of the team's bots for this one (`BotOrders.current`): `{order, issuer_id,
## at}`. Roam until a person says otherwise.
var order: Dictionary = {"order": BotOrders.DEFAULT, "issuer_id": 0, "at": Vector3.INF}
## The bot's own full health: what the rules said last (`player_added`, `player_hurt`,
## `player_healed` carry it; the frame does not), 100 until then. A health tonic raises it.
var max_health := 100.0
## Grenades the bot carries: the count a player starts with until the rules say otherwise
## (`grenade_count_changed`: a throw, a refill at a round's start, a purchase).
var grenades := START_GRENADES
## The special round in play (`round_started`'s `special_id`), or empty in an ordinary round.
var special: StringName = &""
## Whether the break the bot is in announced a special round (`special_round_announced`): the
## marquee every player reads, which the profile may shop for (`BotProfile.prepared_mags`).
var special_coming := false
## The purchases the server refused since the brain last looked: `{item, result}`.
var denials: Array[Dictionary] = []
## Things that happened to the bot or the night since the brain last looked, for the callouts:
## `{kind}` (`revived`, `door_bought`, `fuel_low`, `breach_open`, `trapped`, `need_held_back`).
var moments: Array[Dictionary] = []
## The clock when the bot last bought something.
var purchased_at := -INF
## The round in which the crane's prize was last left on the glass (`crane_prize_lost`, expired)
## and the weapons carried then: the bot plays no more in that round with those weapons (#1322).
var crane_pass := CranePass.new()
## Rays the last look cast: how busy this think already was.
var rays := 0
var now := 0.0


## Notes that the prize of the crane was left on the glass in `round_number` by a bot carrying
## `arms`.
func pass_crane(round_number: int, arms: Dictionary) -> void:
	crane_pass.note(round_number, arms)


## Whether the bot passed the crane's prize in `round_number` carrying `arms` (nothing has changed).
func passed_crane(round_number: int, arms: Dictionary) -> bool:
	return crane_pass.holds(round_number, arms)


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


## Metres to the nearest headliner the bot believes in, or INF.
func boss_distance(here: Vector3) -> float:
	var best := INF
	for id in contacts:
		var contact_of: Dictionary = contacts[id]
		if ZombieModels.is_boss(contact_of.get("look", ZombieModels.DEFAULT)):
			if is_believed(contact_of):
				best = minf(best, _flat(here, contact_of["position"]))
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
