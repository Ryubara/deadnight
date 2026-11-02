class_name BotClaims
extends RefCounted
## Who of the bots raises whom: one claim per downed player, with a lease, so two bots never walk to
## the same body and the others cover (`docs/research/bots.md#revives`). Plain data and the clock
## it is given (the callers' own `now`, all the same step); nothing here reads a frame.
##
## The nearest bot claims. Each bot that wants a body bids its distance every think (a bid lives
## `BID_SECONDS`); the claim goes to the lowest distance, ties to the lowest player id, and lasts
## `LEASE` seconds unless its holder renews it (every think while it goes on). A bot may take a
## claim from another only by being `STEAL_MARGIN` metres nearer and only while the holder has not
## begun the hold (a bot that holds the revive is never displaced). A bot that leaves releases what
## it held, so its body is open to the next bot at once.

## Seconds a claim stands without being renewed, and a bid.
const LEASE := 3.0
const BID_SECONDS := 1.0
## Metres by which a challenger must be nearer than the holder to take a claim that is not yet in
## its hold.
const STEAL_MARGIN := 2.0


class Claim:
	extends RefCounted
	var holder := 0
	var distance := INF
	var until := 0.0
	var committed := false


## Victim id to its claim, and victim id to `{bot id: Vector2(distance, expiry)}`.
var _claims: Dictionary[int, Claim] = {}
var _bids: Dictionary[int, Dictionary] = {}


## Asks for the claim on `victim` for `bot`, `distance` metres from it. True when the bot holds it
## after the call (and the lease is renewed). `committed` marks a bot that is holding the revive.
func request(victim: int, bot: int, distance: float, now: float, committed := false) -> bool:
	_purge(victim, now)
	var bids: Dictionary = _bids.get(victim, {})
	bids[bot] = Vector2(distance, now + BID_SECONDS)
	_bids[victim] = bids
	var claim: Claim = _claims.get(victim)
	if claim != null:
		if claim.holder == bot:
			_renew(claim, distance, now, committed)
			return true
		if claim.committed or distance + STEAL_MARGIN >= claim.distance:
			return false
		_claims[victim] = _make(bot, distance, now, committed)
		return true
	if _best_bidder(bids) != bot:
		return false
	_claims[victim] = _make(bot, distance, now, committed)
	return true


## The bot that holds the claim on `victim` now, or 0.
func holder_of(victim: int, now: float) -> int:
	var claim: Claim = _claims.get(victim)
	return claim.holder if claim != null and claim.until > now else 0


## The victim `bot` holds the claim on now, or 0.
func held_by(bot: int, now: float) -> int:
	for victim: int in _claims:
		var claim := _claims[victim]
		if claim.holder == bot and claim.until > now:
			return victim
	return 0


## Whether the claimant of `victim` has begun the hold.
func is_committed(victim: int, now: float) -> bool:
	var claim: Claim = _claims.get(victim)
	return claim != null and claim.until > now and claim.committed


## Gives up what `bot` holds or bid for (it left, or its slot went to a person).
func release(bot: int) -> void:
	for victim: int in _claims.keys():
		if _claims[victim].holder == bot:
			_claims.erase(victim)
	for victim: int in _bids.keys():
		_bids[victim].erase(bot)


## Gives up the claim on `victim` (it is up, dead or gone).
func release_victim(victim: int) -> void:
	_claims.erase(victim)
	_bids.erase(victim)


## How many claims stand now.
func count(now: float) -> int:
	var live := 0
	for claim: Claim in _claims.values():
		if claim.until > now:
			live += 1
	return live


func _make(bot: int, distance: float, now: float, committed: bool) -> Claim:
	var claim := Claim.new()
	claim.holder = bot
	_renew(claim, distance, now, committed)
	return claim


func _renew(claim: Claim, distance: float, now: float, committed: bool) -> void:
	claim.distance = distance
	claim.until = now + LEASE
	claim.committed = committed


## Drops the claim and the bids on `victim` that ran out.
func _purge(victim: int, now: float) -> void:
	var claim: Claim = _claims.get(victim)
	if claim != null and claim.until <= now:
		_claims.erase(victim)
	var bids: Dictionary = _bids.get(victim, {})
	for bot: int in bids.keys():
		if (bids[bot] as Vector2).y <= now:
			bids.erase(bot)


## The bidder with the lowest distance, ties to the lowest id.
static func _best_bidder(bids: Dictionary) -> int:
	var best := 0
	var best_distance := INF
	for bot: int in bids:
		var distance := (bids[bot] as Vector2).x
		if distance < best_distance or (distance == best_distance and bot < best):
			best = bot
			best_distance = distance
	return best
