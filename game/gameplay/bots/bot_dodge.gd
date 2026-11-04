class_name BotDodge
extends RefCounted
## Stepping out of a blow that has been telegraphed. A zombie that starts a swing stands still and
## lands the blow when the windup is over, on whoever is then within its reach (`REACH` and the
## `SLACK` past it): nothing is aimed, only the distance counts, so the answer is to be farther than
## that by then. A bot sees the swing begin on the frame (the zombie's mode), notices it after its
## reaction time, and runs if the blow would still reach it and there is time to be out of reach.
##
## The headliner winds up for 1.2 s (the telegraph the HUD shows), so every profile has time; a
## plain zombie takes 0.45 s, which only a quick bot can use. The numbers are the zombie
## tuning's and a test holds them to it.

## Metres from a zombie's feet at which it swings, and past which a landing blow still connects
## (`ZombieTuning.reach`, `strike_slack`).
const REACH := 1.4
const SLACK := 0.4
## Seconds from the start of a swing to the blow: a plain zombie, the headliner's telegraph and the
## crawler's (`ZombieTuning.windup_seconds`, the roster's `telegraph_seconds`): a grab from the
## floor is shown a little longer. Its reach is shorter than a plain zombie's, so the plain numbers
## above keep every bot out of it.
const WINDUP := 0.45
const CRAWLER_WINDUP := 0.65
const BOSS_WINDUP := 1.2
## Metres past the blow's reach within which a swinger is still a danger (the bot may drift in),
## and the seconds the last step out of reach takes at a sprint: a blow closer than that is lost.
const DRIFT := 0.3
const STEP_SECONDS := 0.3

var _profile: BotProfile
var _rng := RandomNumberGenerator.new()
## Per zombie: `{episode, noticed}`, whether the bot made out the swing it is in (the roll is made
## once per swing).
var _noticed: Dictionary = {}


func _init(profile: BotProfile, seed_value: int = 1) -> void:
	_profile = profile
	_rng.seed = seed_value


## The seconds from the start of a swing to its blow, for a zombie of `look`.
static func windup_of(look: StringName) -> float:
	if ZombieModels.is_boss(look):
		return BOSS_WINDUP
	return CRAWLER_WINDUP if ZombieModels.crawls(look) else WINDUP


## The believed contacts whose blow will reach the bot at `here` unless it moves, and that the bot
## has had time to notice (its reaction since the swing began) with time left to get out. Each is
## `{id, position, left}` with `left` the seconds to the blow.
func swings(beliefs: BotBeliefs, here: Vector3) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if contact["mode"] != ZombieBody.Mode.ATTACK or contact["attack_at"] < 0.0:
			continue
		if not beliefs.is_believed(contact):
			continue
		var apart := (
			Vector2(contact["position"].x - here.x, contact["position"].z - here.z).length()
		)
		if apart > REACH + SLACK + DRIFT:
			continue
		if not _makes_out(id, contact):
			continue
		var seen_for: float = beliefs.now - float(contact["attack_at"])
		var left := windup_of(contact.get("look", ZombieModels.DEFAULT)) - seen_for
		if seen_for < _profile.reaction_seconds or left < STEP_SECONDS * 0.5:
			continue
		found.append({"id": id, "position": contact["position"], "left": left})
	return found


## Whether the bot makes out this swing: a plain swing always, a telegraphed one (the boss's) with
## the profile's `telegraph_read`, rolled once for each swing.
func _makes_out(id: int, contact: Dictionary) -> bool:
	if not ZombieModels.is_boss(contact.get("look", ZombieModels.DEFAULT)):
		return true
	var episode: int = contact.get("episode", 0)
	var held: Dictionary = _noticed.get(id, {})
	if held.is_empty() or held["episode"] != episode:
		held = {"episode": episode, "noticed": _rng.randf() < _profile.telegraph_read}
		_noticed[id] = held
	return held["noticed"]
