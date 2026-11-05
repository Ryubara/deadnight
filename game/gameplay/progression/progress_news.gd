class_name ProgressNews
extends RefCounted
## Progress the menu learns of while no night is up, turned into the events the night tells
## (`level_up`, `tier_up`, `unlock_earned`, a finished `challenge_advanced`), so the popup lane
## shows the same cards (`MenuPopups.announce`). Two things are read, both when the account's data
## is read at sign-in and replaces the cache:
##
## - **A profile at a higher level than the cache** (`levels_after_read`): the cache is what this
##   machine knew, and the nights it played told their levels live. The levels between are told,
##   one `XpAward.crossing` each.
## - **A challenge board with finishes the cache lacks** (`challenges_after_read`): a night the
##   game server played, or another machine.
##
## Never twice: a card the night showed live is in the ledger (`ProgressSeen`), and a solo night's
## XP and finishes are in the cache already. A cache that is not this account's (a new machine, a
## player who changed account) is no baseline: nothing was earned here, so nothing is told, and
## the ledger starts from what the account holds.


## The events of every level from `from_level` (exclusive) to `to_level`, in order.
static func level_events(from_level: int, to_level: int, unlocks: LadderUnlocks = null) -> Array:
	var table := unlocks if unlocks != null else LadderUnlocks.shipped()
	var out: Array = []
	for level in range(from_level + 1, mini(to_level, LevelCurve.MAX_LEVEL) + 1):
		out.append_array(XpAward.crossing(0, level, LevelCurve.xp_for(level), table))
	return out


## The events for the levels an account now holds beyond what was told. `cached_level` is the
## level the cache held for this account before the read (0 when the cache was not this
## account's). Updates the ledger to the level now held.
static func levels_after_read(account_id: String, cached_level: int, new_level: int) -> Array:
	var seen := ProgressSeen.open()
	var kept := seen.bind(account_id)
	var told := maxi(cached_level, seen.level_for(account_id))
	var events := level_events(told, new_level) if told > 0 else []
	if kept and new_level > seen.level:
		seen.level = new_level
		seen.save()
	return events


## The `challenge_advanced` events for challenges finished in `after` and not in `before` (the
## board the cache held; null when it was not this account's: nothing is told), less those a night
## showed live. The ledger is emptied: the cache is the account's board from now on.
static func challenges_after_read(
	account_id: String,
	before: ChallengeProfile,
	after: ChallengeProfile,
	catalog: ChallengeCatalog,
	day: int
) -> Array:
	var seen := ProgressSeen.open()
	var kept := seen.bind(account_id)
	var events: Array = []
	if before != null and before.account == account_id:
		var held := finished_keys(before, catalog, day)
		var now := finished_keys(after, catalog, day)
		for key: String in now:
			if not held.has(key) and not seen.was_told(account_id, key):
				events.append(now[key])
	if kept and not seen.told.is_empty():
		seen.told = {}
		seen.save()
	return events


## Every challenge `profile` shows as finished, `{key: event}`: today's dailies, the orders done
## (open, or settled into the recent list) and the ladders whose last step is reached.
static func finished_keys(
	profile: ChallengeProfile, catalog: ChallengeCatalog, day: int
) -> Dictionary:
	var out := {}
	for entry in profile.dailies:
		var def := catalog.get_def(StringName(entry["id"]))
		if def != null and int(entry["day"]) == day and int(entry["progress"]) >= def.target:
			out[ProgressSeen.challenge_key(def.family, def.id, day)] = _event(def, def.words())
	for entry in profile.orders:
		var def := catalog.get_def(StringName(entry["id"]))
		if def != null and int(entry["progress"]) >= def.target:
			out[ProgressSeen.challenge_key(def.family, def.id, day)] = _event(def, def.words())
	for id in profile.recent_orders:
		var def := catalog.get_def(id)
		if def != null:
			out[ProgressSeen.challenge_key(def.family, def.id, day)] = _event(def, def.words())
	for def in catalog.of_family(ChallengeDef.Family.MILESTONE):
		var steps := def.steps.size()
		if (
			steps > 0
			and ChallengeProfile.rung_of(def, int(profile.lifetime.get(def.stat, 0))) >= steps
		):
			out[ProgressSeen.challenge_key(def.family, def.id, day)] = _event(
				def, def.words(def.steps[steps - 1])
			)
	return out


static func _event(def: ChallengeDef, text: String) -> Dictionary:
	return {
		"type": &"challenge_advanced",
		"id": def.id,
		"family": def.family,
		"text": text,
		"completed": true,
	}
