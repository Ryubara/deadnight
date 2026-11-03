class_name BotRoles
extends RefCounted
## Roles as stances, not classes (bots plan, phase 5, `docs/research/bots.md#team-roles-and-
## communication`): what each bot of the team is for right now, reassigned every few seconds and
## sticky for at least ten.
##
## - `ANCHOR` (the default): stays within the follow band of the nearest people; there is at least
##   one anchor for each person, so nobody is left alone;
## - `FLANK`: with a person and enough bots to spare, one bot holds a choke 8 to 14 m to the side of
##   the group's heading (`flank_centre`), where it covers a way the others do not face;
## - `MAINTAINER`: the bot whose turn it is to go on an errand (`BotTurn`); it comes back.
##
## One table is shared by the team (`BotTeam.roles`). Any bot may ask for the roles of this moment
## (`update`), and the first to ask after the interval has run out makes them; the others read the
## same answer. Plain data and the clock it is given.

enum Role { ANCHOR, FLANK, MAINTAINER }

## Seconds between two assignments, and the least a bot keeps a role it was given.
const REASSIGN_EVERY := 3.0
const STICKY := 10.0
## Metres of the flank's choke from the group: nearest, farthest and the one aimed at.
const FLANK_NEAR := 8.0
const FLANK_FAR := 14.0
const FLANK_AT := 11.0
## Metres a second under which a group counts as standing (its heading is then where it faces).
const STANDING := 0.5
## The flank holds only while the people stand or nearly (they are at a door, a shop or a fight);
## while they walk it follows with the rest, and it never holds farther than this from them.
const FLANK_STILL := 1.0
const FLANK_LIMIT := 11.5

var _roles: Dictionary[int, Role] = {}
var _since: Dictionary[int, float] = {}
var _updated_at := -INF


## The role of `bot` as of the last assignment (`ANCHOR` before the first).
func role_of(bot: int) -> Role:
	return _roles.get(bot, Role.ANCHOR)


## Makes the roles of this moment if `REASSIGN_EVERY` has passed. `bots` are the bots up
## (`{id, pos}`), `people` the persons up (`{pos, velocity, facing}`), `maintainer` the bot whose
## turn it is to go on an errand (0 for none).
func update(
	now: float, bots: Array[Dictionary], people: Array[Dictionary], maintainer: int
) -> void:
	if now - _updated_at < REASSIGN_EVERY:
		return
	_updated_at = now
	var ids: Array[int] = []
	for bot in bots:
		ids.append(int(bot["id"]))
	for id: int in _roles.keys():
		if not ids.has(id):
			_roles.erase(id)
			_since.erase(id)
	var free: Array[Dictionary] = []
	for bot in bots:
		if int(bot["id"]) == maintainer:
			_give(maintainer, Role.MAINTAINER, now, true)
		else:
			free.append(bot)
	var flank := _flank_bot(free, people, now)
	for bot in free:
		var id := int(bot["id"])
		_give(id, Role.FLANK if id == flank else Role.ANCHOR, now, false)


## The bot that flanks, or 0: one when there is a person and at least one more free bot than people
## (so every person keeps an anchor); the one that already does while it is allowed to, else the one
## nearest the flank's place.
func _flank_bot(free: Array[Dictionary], people: Array[Dictionary], now: float) -> int:
	if people.is_empty() or free.size() < people.size() + 1:
		return 0
	for bot in free:
		var id := int(bot["id"])
		if _roles.get(id, Role.ANCHOR) == Role.FLANK:
			return id
	var place := flank_centre(people)
	var best := 0
	var best_apart := INF
	for bot in free:
		var id := int(bot["id"])
		if now - float(_since.get(id, -INF)) < STICKY and _roles.has(id):
			continue
		var apart := _flat(bot["pos"], place)
		if apart < best_apart or (is_equal_approx(apart, best_apart) and id < best):
			best = id
			best_apart = apart
	return best


## Sets a role; a bot keeps the one it has until `STICKY` seconds have passed, unless `force`.
func _give(id: int, role: Role, now: float, force: bool) -> void:
	if _roles.has(id) and _roles[id] == role:
		return
	if not force and _roles.has(id) and now - float(_since.get(id, -INF)) < STICKY:
		# A maintainer that finished goes back to the band at once; any other change waits.
		if _roles[id] != Role.MAINTAINER:
			return
	_roles[id] = role
	_since[id] = now


## Where the flank holds: `FLANK_AT` metres from the centre of `people`, to the side of the way they
## are heading (or facing, when they stand), on the side of the first person's left.
static func flank_centre(people: Array[Dictionary]) -> Vector3:
	var centre := Vector3.ZERO
	var velocity := Vector3.ZERO
	for person in people:
		centre += person["pos"]
		velocity += person.get("velocity", Vector3.ZERO)
	centre /= float(people.size())
	velocity /= float(people.size())
	var heading := Vector3(velocity.x, 0.0, velocity.z)
	if heading.length() < STANDING:
		var yaw := float(people[0].get("facing", 0.0))
		heading = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var side := heading.normalized().cross(Vector3.UP)
	return centre + side * FLANK_AT


## The centre of `people` and the speed of the group (metres a second, the mean).
static func centre_of(people: Array[Dictionary]) -> Vector3:
	var centre := Vector3.ZERO
	for person in people:
		centre += person["pos"]
	return centre / float(maxi(people.size(), 1))


static func speed_of(people: Array[Dictionary]) -> float:
	var total := 0.0
	for person in people:
		var velocity: Vector3 = person.get("velocity", Vector3.ZERO)
		total += Vector2(velocity.x, velocity.z).length()
	return total / float(maxi(people.size(), 1))


## `place`, brought in to at most `FLANK_LIMIT` metres from the people.
static func within_limit(place: Vector3, people: Array[Dictionary]) -> Vector3:
	var centre := centre_of(people)
	var offset := Vector3(place.x - centre.x, 0.0, place.z - centre.z)
	if offset.length() <= FLANK_LIMIT:
		return place
	var kept := centre + offset.normalized() * FLANK_LIMIT
	kept.y = place.y
	return kept


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
