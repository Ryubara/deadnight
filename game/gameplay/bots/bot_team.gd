class_name BotTeam
extends RefCounted
## What the bots of one night share and no single bot owns: the claims on downed players
## (`BotClaims`), the errand turn (`BotTurn`) and the roles (`BotRoles`). The host makes one and
## hands the same to every bot it seats (like `BotHost.bot_ids`), so a lone `BotClient` in a test
## has a team of its own. Plain data: nothing here reads a frame or the rules.

## Seconds past the fuse a thrown grenade is still counted live (it lies where it landed a moment
## after the throw leaves the hand).
const BLAST_SLACK := 0.6

var claims := BotClaims.new()
## The place each roaming bot is walking to (`BotRoam`), by player id, so two do not pick one.
var roam: Dictionary = {}
## The flares burning now, as `{point, radius, until, shooter}` (the clock of the bots, all the same
## step): the dead within a flare's radius walk to it, so a bot judging a revive counts them as far.
var lures: Array[Dictionary] = []
## The grenades a bot has thrown that have not gone off, as `{point, until, owner}` (where it was
## aimed to land, the bot clock at which it goes off, and the thrower): the thrower keeps out of its
## own blast (`BotFightBrain`); only the thrower takes a grenade's damage (#856).
var blasts: Array[Dictionary] = []
## The claims on the links to buy (`BotErrands._link`): the nearest free bot to a link holds it.
## Keyed by the link id's hash, with the same lease and steal margin as a body's claim.
var links := BotClaims.new()
## The claims on the last zombies of a round that are hunted (`BotHunt`): the nearest free bot to a
## zombie holds it, keyed by the zombie's id.
var hunts := BotClaims.new()
## Whose turn it is to go on an errand (one bot at a time).
var turn := BotTurn.new()
## Whether the errands go one bot at a time (off only to measure what the turn costs).
var one_errand_at_a_time := true
## What each bot is for now: anchor, flank or maintainer.
var roles := BotRoles.new()
## Whether a claimant that carries a flare gun may fire it to draw the dead off a body (off only to
## measure what the flare rule is worth, #646).
var flares := true


## A flare began to burn (a bot fired it and heard it burst).
func add_lure(point: Vector3, radius: float, until: float, shooter: int) -> void:
	lures.append({"point": point, "radius": radius, "until": until, "shooter": shooter})


## The flares still burning at `now`; the ones that went out are forgotten.
func active_lures(now: float) -> Array[Dictionary]:
	lures = lures.filter(func(lure: Dictionary) -> bool: return float(lure["until"]) > now)
	return lures


## A grenade `owner` threw to land at `point` goes off at `until`.
func add_blast(point: Vector3, until: float, owner: int) -> void:
	blasts.append({"point": point, "until": until, "owner": owner, "grenade": -1})


## The grenade `grenade_id` has left `owner`'s hand: it is the one the owner's latest order
## planned (`grenade_thrown`).
func grenade_flying(owner: int, grenade_id: int) -> void:
	for i in range(blasts.size() - 1, -1, -1):
		if int(blasts[i]["owner"]) == owner and int(blasts[i]["grenade"]) < 0:
			blasts[i]["grenade"] = grenade_id
			return


## The grenade `grenade_id` struck a wall, a zombie or the ground at `point` (`grenade_bounced`,
## which every screen shows): that, not where it was aimed, is where it goes off, for the heavy
## grenade hardly rolls. A bounce that was a thrower's own is the one that moves its blast.
func grenade_lies(grenade_id: int, point: Vector3) -> void:
	for blast in blasts:
		if int(blast["grenade"]) == grenade_id:
			blast["point"] = point


## Where the grenades `owner` threw that are still to go off at `now` are, within `reach` metres
## (flat) of `here`; the ones that went off are forgotten.
func blasts_near(here: Vector3, reach: float, now: float, owner: int) -> Array[Vector3]:
	blasts = blasts.filter(func(blast: Dictionary) -> bool: return float(blast["until"]) > now)
	var near: Array[Vector3] = []
	for blast: Dictionary in blasts:
		if int(blast["owner"]) != owner:
			continue
		var point: Vector3 = blast["point"]
		if Vector2(here.x - point.x, here.z - point.z).length() < reach:
			near.append(point)
	return near


## A bot left the team (its seat was taken by a person, or it was removed): what it held is open.
func release(bot: int) -> void:
	claims.release(bot)
	links.release(bot)
	hunts.release(bot)
	roam.erase(bot)
	turn.release(bot)
