class_name BotCallouts
extends RefCounted
## What a bot says (bots plan, phase 5, `docs/research/bots.md#team-roles-and-communication`): the
## lines of `BotSay`, each with its own cooldown (20 to 60 s) and one gap for the bot as a whole
## (`GAP` seconds, `GAP_URGENT` before an urgent line), because a repeated gesture stops meaning
## anything and Back 4 Blood's bots "ping" constantly. A bot calls out only what it perceived: a
## line about a zombie (`BotSay.ABOUT_A_ZOMBIE`) is refused unless the zombie is one the bot
## believes in, so no line ever names a zombie the bot has not made out.
##
## `plan` looks at what the bot knows and its own state once a think and answers the line to say,
## or nothing; `say` is the gate every line passes through. Plain data and the bot's own clock.

## Seconds between two lines of this bot, and before an urgent one.
const GAP := 12.0
const GAP_URGENT := 5.0
## No more than `WINDOW_LINES` lines in any `WINDOW` seconds, whatever the trouble: under one line
## in ten seconds on average, and the first of a burst is never held back.
const WINDOW := 25.0
const WINDOW_LINES := 2
## Runners that make a pack worth a call, and the metres inside which a boss is "coming".
const RUNNERS_MIN := 3
const BOSS_NEAR := 30.0
## Share of full health under which a bot in trouble asks for cover, and the zombies on it.
const COVER_HEALTH := 0.6
const COVER_ATTACKERS := 2
const ON_SELF := 2.5
## Rounds (magazine and reserve, all guns) under which the bot says it is running low, in a lull.
const LOW_ROUNDS := 24

## How many lines were said, and how many were refused for naming a zombie not perceived.
var said := 0
var refused_unseen := 0

var _last := {}
var _last_any := -INF
var _times: Array[float] = []
var _was_holding := false
var _was_down := false


## The gate: the line to send as an action, or an empty dictionary when the cooldown, the gap or
## the rule about zombies says no. `believed` is the ids of the zombies the bot believes in.
func say(
	line: StringName, now: float, believed: Array, subject := -1, at := Vector3.ZERO
) -> Dictionary:
	if not BotSay.is_line(line):
		return {}
	if BotSay.ABOUT_A_ZOMBIE.has(line) and not believed.has(subject):
		refused_unseen += 1
		return {}
	if now - float(_last.get(line, -INF)) < BotSay.cooldown_of(line):
		return {}
	var gap := GAP_URGENT if BotSay.is_urgent(line) else GAP
	if now - _last_any < gap:
		return {}
	while not _times.is_empty() and now - _times[0] >= WINDOW:
		_times.pop_front()
	if _times.size() >= WINDOW_LINES:
		return {}
	_times.append(now)
	_last[line] = now
	_last_any = now
	said += 1
	return {"type": &"say", "line": line, "subject": subject, "pos": at}


## The action to send this think, or an empty dictionary. `beliefs.moments` are the things that
## happened to the bot or the night, taken out as they are used. `holding` is whether the bot has
## begun a revive, `reloading` whether it is about to reload, `lowest_bot` whether it is the bot
## that speaks for the team about the generator.
func plan(
	beliefs: BotBeliefs,
	me: Dictionary,
	profile: BotProfile,
	holding: bool,
	reloading: bool,
	lowest_bot: bool
) -> Dictionary:
	var now := beliefs.now
	var here: Vector3 = me.get("pos", Vector3.ZERO)
	var believed := _believed(beliefs)
	var threat := beliefs.nearest_threat(here, profile.memory_seconds)
	var wanted: Array[Dictionary] = []
	if holding and not _was_holding:
		wanted.append({"line": BotSay.REVIVING})
	_was_holding = holding
	for contact_id: int in believed:
		var contact := beliefs.contact(contact_id)
		if (
			ZombieModels.is_boss(contact.get("look", ZombieModels.DEFAULT))
			and _flat(here, contact["position"]) <= BOSS_NEAR
		):
			wanted.append({"line": BotSay.BOSS_COMING, "subject": contact_id})
			break
	var runners := _nearest_runners(beliefs, here, believed)
	if runners.size() >= RUNNERS_MIN:
		wanted.append({"line": BotSay.RUNNERS, "subject": runners[0]})
	if _in_trouble(beliefs, me, here):
		wanted.append({"line": BotSay.COVER_ME})
	for moment in beliefs.moments:
		match moment["kind"]:
			&"trapped":
				wanted.append({"line": BotSay.TRAPPED})
			&"revived":
				wanted.append({"line": BotSay.THANKS})
			&"door_bought":
				wanted.append({"line": BotSay.DOOR_BOUGHT})
			&"fuel_low":
				if lowest_bot:
					wanted.append({"line": BotSay.LOW_FUEL})
			&"breach_open":
				wanted.append({"line": BotSay.BREACH_OPEN})
	beliefs.moments.clear()
	if reloading and threat < 12.0:
		wanted.append({"line": BotSay.RELOADING})
	if threat == INF and _low_on_rounds(me):
		wanted.append({"line": BotSay.NEED_AMMO})
	for want in wanted:
		var action := say(want["line"], now, believed, int(want.get("subject", -1)), here)
		if not action.is_empty():
			return action
	return {}


## The bot is on the ground: it calls for help once (the cooldown of the line keeps it to a call a
## minute) and does nothing else.
func downed(beliefs: BotBeliefs, me: Dictionary) -> Dictionary:
	beliefs.moments.clear()
	_was_holding = false
	if _was_down:
		return {}
	_was_down = true
	return say(BotSay.HELP, beliefs.now, [], -1, me.get("pos", Vector3.ZERO))


## The bot is on its feet again.
func up() -> void:
	_was_down = false


func _believed(beliefs: BotBeliefs) -> Array:
	var ids: Array = []
	for id in beliefs.contacts:
		if beliefs.is_believed(beliefs.contacts[id]):
			ids.append(id)
	return ids


## Ids of the believed runners, nearest first.
func _nearest_runners(beliefs: BotBeliefs, here: Vector3, believed: Array) -> Array:
	var pairs: Array[Vector2] = []
	for id: int in believed:
		var contact := beliefs.contact(id)
		if contact.get("look", &"") == &"runner":
			pairs.append(Vector2(_flat(here, contact["position"]), float(id)))
	pairs.sort()
	var ids: Array = []
	for pair in pairs:
		ids.append(int(pair.y))
	return ids


## Hurt, with zombies on it: the believed ones within `ON_SELF` metres, or the ones heard very near.
func _in_trouble(beliefs: BotBeliefs, me: Dictionary, here: Vector3) -> bool:
	if float(me.get("health", 100.0)) / 100.0 >= COVER_HEALTH:
		return false
	var on_me := 0
	for id in beliefs.contacts:
		var contact: Dictionary = beliefs.contacts[id]
		if beliefs.is_believed(contact) and _flat(here, contact["position"]) <= ON_SELF:
			on_me += 1
	for sound in beliefs.heard:
		if sound["range_class"] == BotBeliefs.VERY_NEAR:
			on_me += 1
	return on_me >= COVER_ATTACKERS


func _low_on_rounds(me: Dictionary) -> bool:
	var arms: Dictionary = me.get("arms", {})
	var rounds := 0
	var guns := 0
	for id: StringName in arms:
		if WeaponCatalog.get_def(id).is_melee():
			continue
		guns += 1
		rounds += int(arms[id][0]) + int(arms[id][1])
	return guns > 0 and rounds < LOW_ROUNDS


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
