class_name BotHunt
extends RefCounted
## The last zombies of a round, as a person finds them. When a round is down to its last few dead
## (`ZombieTuning.mark_last`, three) every player's screen outlines them through the walls
## (`ZombieMarks`), so a person walks to the one that is still out there. A bot sees only what is in
## front of it, in the light, and roamed away from a boss that chased a person for eight minutes
## (the soak, #770: "the headliner alive and not found"); it reads the same rule off the frame
## (`phase` and `remaining`) and the same zombies (`marked`, told to it as `BotBeliefs.last_dead`),
## and goes to look.
##
## - Only when the round has been down to its marked zombies for `AFTER` seconds: the dead that are
##   coming come, and the bots fight them where they stand.
## - Only a bot that is free (the brain says): nothing in sight, rounds in a gun, not hurt, not
##   holding a spot. Under Follow only a zombie that is `LEASH` metres or more from the person: the
##   nearer ones come to the people.
## - One bot to a zombie: the nearest free one (`BotClaims`, the same claim by distance the bodies
##   and the links use), the others cover.
## - It walks to within `STOP` metres of the zombie, where the bot's sight finds it, and the fight
##   takes over. A bot that stands there and cannot see it for `PATIENCE` seconds leaves that zombie
##   alone for `BAN` seconds (a zombie behind a wall), and so does one the walking mesh has no way
##   to.
##
## One of these belongs to each bot (it keeps the time the last dead were marked, and the zombies it
## gave up on); the pure rules are static.

## Seconds the round must have been down to its marked zombies before the bots go and look.
const AFTER := 15.0
## Metres from the zombie at which the bot counts itself there.
const STOP := 6.0
## Metres from the person under Follow beyond which a marked zombie is looked for.
const LEASH := 30.0
## Seconds a bot stands within `STOP` of a zombie it cannot see before it gives that zombie up, and
## the seconds it then leaves it alone.
const PATIENCE := 6.0
const BAN := 30.0
## Metres within which a zombie the bot believes in is a fight, not a hunt.
const CLEAR_FROM := 12.0

## The time the zombies became the last few, or `INF` when they are not.
var _marked_since := INF
## The zombie this bot is looking for (0 for none), and when it got to where it stood.
var _looking_for := 0
var _arrived_at := INF
## By zombie id: the time until which it is left alone.
var _banned: Dictionary = {}


## The zombies of `zombies` (the frame's, decoded) that are marked: the round is active and
## `remaining` (the dead alive and still to spawn) is from one to `last`; the ones that are not
## dying.
static func marked(
	zombies: Array[Dictionary], phase: int, remaining: int, last: int
) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if phase != BotErrands.ACTIVE_PHASE or remaining < 1 or remaining > last:
		return found
	for zombie in zombies:
		if zombie["mode"] != ZombieBody.Mode.DYING:
			found.append(zombie)
	return found


## Whether a marked zombie at `at` is one to go and look for: always under Roam, and under Follow
## only when it is `LEASH` metres or more from the person (`anchor`, `Vector3.INF` for none).
static func worth_the_walk(at: Vector3, following: bool, anchor: Vector3) -> bool:
	if not following or anchor == Vector3.INF:
		return true
	return Vector2(at.x - anchor.x, at.z - anchor.z).length() >= LEASH


## Whether the bot believes in a zombie within `metres` (seen or remembered, not merely heard).
static func believes_within(
	beliefs: BotBeliefs, here: Vector3, metres: float, memory_seconds: float
) -> bool:
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if beliefs.is_believed(contact):
			var at := beliefs.guess(contact, memory_seconds)
			if Vector2(at.x - here.x, at.z - here.z).length() <= metres:
				return true
	return false


## Notes whether the round is down to its last few dead (every think, whatever else the bot does).
func watch(beliefs: BotBeliefs) -> void:
	if beliefs.last_dead.is_empty():
		_marked_since = INF
	elif _marked_since == INF:
		_marked_since = beliefs.now


## Sets the intent's goal to the nearest marked zombie this bot holds the claim on, when `free` and
## the round has been down to them long enough. `following` is the order Follow and `anchor` the
## person's place (`Vector3.INF` for none); `legs` and `team` may be null. True when it set the
## goal.
func run(
	intent: BotIntent,
	beliefs: BotBeliefs,
	here: Vector3,
	free: bool,
	following: bool,
	anchor: Vector3,
	legs: BotLegs,
	team: BotTeam,
	level: BotLevel,
	memory_seconds: float
) -> bool:
	var now := beliefs.now
	if (
		beliefs.last_dead.is_empty()
		or now - _marked_since < AFTER
		or not free
		or believes_within(beliefs, here, CLEAR_FROM, memory_seconds)
	):
		_forget()
		return false
	var pick := {}
	var pick_apart := INF
	for zombie in beliefs.last_dead:
		var id: int = zombie["id"]
		if float(_banned.get(id, -INF)) > now:
			continue
		var at: Vector3 = zombie["position"]
		if not worth_the_walk(at, following, anchor):
			continue
		# One the walking mesh has no way to (in a pocket of it, behind a shut door) is left alone.
		if legs != null and legs.path.is_blocked(level.project(at), now):
			_banned[id] = now + BAN
			continue
		var apart := Vector2(at.x - here.x, at.z - here.z).length()
		# The nearest free bot to a zombie holds it, the others cover (`BotClaims`).
		if team != null and not team.hunts.request(id, beliefs.me, apart, now):
			continue
		if apart < pick_apart:
			pick = zombie
			pick_apart = apart
	if pick.is_empty():
		_forget()
		return false
	var id: int = pick["id"]
	var at: Vector3 = pick["position"]
	if id != _looking_for:
		_looking_for = id
		_arrived_at = INF
	if pick_apart <= STOP + 1.0:
		# There, and the zombie is not in sight (a bot that sees it has a target and fights): a zombie
		# behind a wall is given up after a while.
		if _arrived_at == INF:
			_arrived_at = now
		elif now - _arrived_at >= PATIENCE:
			_banned[id] = now + BAN
			if team != null:
				team.hunts.release_victim(id)
			_forget()
			return false
		intent.look_yaw = atan2(-(at.x - here.x), -(at.z - here.z))
	else:
		_arrived_at = INF
	intent.goal = level.project(at)
	intent.goal_radius = STOP
	intent.run = false
	intent.note = "hunt"
	return true


func _forget() -> void:
	_looking_for = 0
	_arrived_at = INF
