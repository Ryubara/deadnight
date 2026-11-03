class_name BotCombat
extends RefCounted
## The bot's judgement in a fight, as small pure rules a test can pin one by one: which zombie to
## shoot (a utility over what is near, hurting a teammate, going for a downed one), whether a
## person is working on a zombie, when a melee swing is a good idea, how far a chase may go.
## Everything reads beliefs and positions; nothing here sends a command or reads the rules.
##
## The target utility, in points (the higher wins), for a believed zombie in sight:
## - how near it is (`W_NEAR`, falling to nothing at `NEAR_RANGE`);
## - a swing under way (`W_SWING`), a runner (`W_FAST`), the headliner once it is close (`W_BOSS`);
## - how fast it comes at the bot (`W_CLOSING`, capped);
## - it is on a teammate who was hit a moment ago (`W_MATE_HIT`), on a downed one (`W_DOWNED`), or
##   on the bot itself after a blow (`W_SELF_HIT`);
## - the weapon in hand does much less at that range (`W_RANGE`, as the share of the damage lost);
## - how hurt the bot is, for the zombies near it (`W_LOW_HEALTH`);
## - the target the bot already has (`W_COMMIT`), so it does not dither between two of a kind.
## A zombie a person is working on from afar is left to them (`courtesy_holds`).

## Metres a zombie counts for its nearness, and how many points a zombie at the bot's feet scores.
const NEAR_RANGE := 25.0
const W_NEAR := 6.0
const W_SWING := 3.0
const W_FAST := 1.2
const W_BOSS := 1.5
const W_CLOSING := 0.8
const W_MATE_HIT := 2.5
const W_DOWNED := 3.5
const W_SELF_HIT := 2.0
const W_RANGE := 3.0
const W_COMMIT := 1.0
## A hurt bot minds the zombies at its feet more: up to this many points, for a zombie within
## `HURT_REACH` metres, as its health runs down.
const W_LOW_HEALTH := 3.0
const HURT_REACH := 8.0
## Metres from a teammate within which a zombie counts as on them.
const ON_MATE := 3.0
## Metres from the bot within which a zombie counts as on it, and the seconds a blow keeps counting.
const ON_SELF := 2.5
const BLOW_SECONDS := 1.5
## Seconds a teammate's loss of health keeps counting as "being hit".
const HURT_SECONDS := 2.0
## A closing speed (m/s) that earns the whole of `W_CLOSING`.
const CLOSING_FULL := 3.0
## Kill courtesy: a person aims within this many degrees of a zombie, from no farther than
## `COURTESY_RANGE`, and the zombie is at least `COURTESY_NEAR` metres from the bot: it is theirs.
const COURTESY_DEGREES := 7.0
const COURTESY_RANGE := 25.0
const COURTESY_NEAR := 6.0
## Zombies within `PACK_RADIUS` metres of the bot that make a pack, and the size of one.
const PACK_RADIUS := 4.0
const PACK_SIZE := 3
## The leash: farthest a chase may take the bot from the nearest person (metres), and how near a
## downed teammate a target must be for the leash to be waived.
const LEASH := 12.0
const RESCUE_REACH := 3.5

var _profile: BotProfile
var _committed := -1


func _init(profile: BotProfile) -> void:
	_profile = profile


## The id of the zombie to shoot among `candidates` (believed, in sight; see `BotBeliefs.targets`),
## or -1. `held` is the weapon in hand (null for none), `mates` the other players as the beliefs
## keep them, `blow_age` seconds since the bot last took a blow, `health` the bot's own (0 to 1).
func choose(
	candidates: Array[Dictionary],
	here: Vector3,
	held: WeaponDef,
	mates: Array[Dictionary],
	now: float,
	blow_age: float = INF,
	health := 1.0
) -> int:
	var best := -1
	var best_score := -INF
	for contact in candidates:
		if courtesy_holds(contact, here, mates):
			continue
		var score := utility(contact, here, held, mates, now, blow_age, health)
		if contact["id"] == _committed:
			score += W_COMMIT
		if score > best_score:
			best_score = score
			best = contact["id"]
	_committed = best
	return best


## What one zombie is worth shooting now.
func utility(
	contact: Dictionary,
	here: Vector3,
	held: WeaponDef,
	mates: Array[Dictionary],
	now: float,
	blow_age: float = INF,
	health := 1.0
) -> float:
	var at: Vector3 = contact["position"]
	var apart := _flat(here, at)
	var score := W_NEAR * clampf(1.0 - apart / NEAR_RANGE, 0.0, 1.0)
	if contact["mode"] == ZombieBody.Mode.ATTACK:
		score += W_SWING
	var look: StringName = contact.get("look", ZombieModels.DEFAULT)
	if look == &"runner":
		score += W_FAST
	if ZombieModels.is_boss(look) and apart < NEAR_RANGE * 0.5:
		score += W_BOSS
	score += W_CLOSING * clampf(closing_speed(contact, here) / CLOSING_FULL, 0.0, 1.0)
	score += (
		W_LOW_HEALTH * (1.0 - clampf(health, 0.0, 1.0)) * clampf(1.0 - apart / HURT_REACH, 0.0, 1.0)
	)
	if blow_age <= BLOW_SECONDS and apart <= ON_SELF:
		score += W_SELF_HIT
	for mate in mates:
		if mate.get("dead", false) or _flat(mate["pos"], at) > ON_MATE:
			continue
		if mate.get("downed", false):
			score += W_DOWNED
		elif now - float(mate.get("hurt_at", -INF)) <= HURT_SECONDS:
			score += W_MATE_HIT
	if held != null and not held.is_melee():
		var here_damage := DamageModel.damage(held, 0.0, &"body")
		var lost := 1.0 - DamageModel.damage(held, apart, &"body") / maxf(here_damage, 0.001)
		score -= W_RANGE * clampf(lost, 0.0, 1.0)
	return score


## How fast (m/s) the contact comes toward `here`; negative when it goes away.
static func closing_speed(contact: Dictionary, here: Vector3) -> float:
	var to_bot: Vector3 = here - contact["position"]
	to_bot.y = 0.0
	if to_bot.length() < 0.01:
		return 0.0
	var velocity: Vector3 = contact["velocity"]
	return velocity.dot(to_bot.normalized())


## Whether the zombie is a person's to shoot: a person (not a bot) aims at it from no farther than
## `COURTESY_RANGE`, and it is still `COURTESY_NEAR` metres or more from the bot and not swinging.
## A person who works on a zombie is earning their points on it; the bot takes what is near. A boss
## is never theirs alone: it takes the whole team's rounds, and a bot that waited for the person to
## finish it stood idle for seconds at 6 to 8 metres from it (#769).
static func courtesy_holds(contact: Dictionary, here: Vector3, mates: Array[Dictionary]) -> bool:
	var at: Vector3 = contact["position"]
	if _flat(here, at) < COURTESY_NEAR or contact["mode"] == ZombieBody.Mode.ATTACK:
		return false
	if ZombieModels.is_boss(contact.get("look", ZombieModels.DEFAULT)):
		return false
	for mate in mates:
		if mate.get("bot", false) or mate.get("dead", false) or mate.get("downed", false):
			continue
		var apart := _flat(mate["pos"], at)
		if apart > COURTESY_RANGE or apart < 0.5:
			continue
		var bearing := atan2(-(at.x - mate["pos"].x), -(at.z - mate["pos"].z))
		var off := absf(angle_difference(float(mate.get("facing", 0.0)), bearing))
		if rad_to_deg(off) <= COURTESY_DEGREES:
			return true
	return false


# --- Melee ---


## The believed zombies within `PACK_RADIUS` metres of `here`.
static func near_count(beliefs: BotBeliefs, here: Vector3, memory_seconds: float) -> int:
	var count := 0
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if beliefs.is_believed(contact):
			if _flat(here, beliefs.guess(contact, memory_seconds)) <= PACK_RADIUS:
				count += 1
	return count


## A swing is a good idea unless it goes into a pack (three or more near), and then only when the
## bot has nothing else to shoot with (`dry`): the crowbar never runs out, a crowd is no place
## for it.
static func may_melee(near: int, dry: bool) -> bool:
	return dry or near < PACK_SIZE


# --- The leash ---


## Whether a chase to `point` is allowed: no farther than `LEASH` metres from the nearest of
## `humans` (positions of the people on their feet; with none there is nothing to stay near and the
## leash is `LEASH` from where the bot is), unless the target stands within `RESCUE_REACH` of a
## downed teammate (`downed`, positions).
static func leash_allows(
	point: Vector3, here: Vector3, humans: Array[Vector3], downed: Array[Vector3]
) -> bool:
	for body in downed:
		if _flat(point, body) <= RESCUE_REACH:
			return true
	if humans.is_empty():
		return _flat(point, here) <= LEASH
	var nearest := INF
	for person in humans:
		nearest = minf(nearest, _flat(point, person))
	return nearest <= LEASH


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
