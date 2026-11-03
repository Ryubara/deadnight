# gdlint:disable=max-public-methods
class_name HudState
extends RefCounted
## Everything the HUD shows, as plain data. Network-first: it is fed rules events (plain
## dictionaries), a snapshot for a late joiner, and the local player's own readings (health, ammo,
## the prompt); it never touches a game object, a node or the rules engine itself, so a client
## builds it from what the server replicates.
##
## `changed` fires once per change (or once per batch: see `hold`), and only when something a part
## shows has changed; `is_dirty(topic)` says which part of the state did, so a part rebuilds only
## on the topics it reads. `event_applied` carries each event after the state has settled, for the
## one-shot treatments (a point popup, a banner, a hit marker).

signal changed
signal event_applied(event: Dictionary)

## The rules' event for a blow on a player (`health` left, `max_health`, `bearing` radians
## clockwise from -z where it came from); the arc turns the bearing toward where the local player
## faces (`facing`).
const PLAYER_HURT := &"player_hurt"

## The parts of the state a HUD part can depend on (see `HudPart.topics`).
const ROUND := &"round"
const OBJECTIVE := &"objective"
const TEAM := &"team"
const FUEL := &"fuel"
const HEALTH := &"health"
const AMMO := &"ammo"
## The weapon slots: what sits in each and which one is in hand (`HudSlots`).
const SLOTS := &"slots"
const POINTS := &"points"
const PROMPT := &"prompt"
const MARKERS := &"markers"
const BOSS := &"boss"
const SPECIAL := &"special"
## Each player's kills, downs and ping, and the night's clock: what the scoreboard shows beyond the
## party's points.
const STATS := &"stats"
## Each player's bleed-out clock and the progress of the hold on them, which change every tick while
## someone is down: apart from `TEAM` so a part that only draws the ring is not rebuilt for a name.
const REVIVE := &"revive"
## The perks the local player has (`HudPerks`).
const PERKS := &"perks"

## A ping the server has not reported: a night alone, or before the first answer.
const NO_PING := -1

## The tank counts as low at or under this fraction (the fuel tuning's `low_fraction`).
const LOW_FRACTION := 0.25
const PHASE_IDLE := 0
const PHASE_BREAK := 1
const PHASE_ACTIVE := 2
const PHASE_OVER := 3

var local_player_id := 1
## The seconds a revive's hold takes and a downed player has before they are dead, from the shared
## tuning (the binding sets them): the rings are drawn against them.
var revive_seconds := 3.5
var bleed_total := 45.0
## The seconds the revive perk takes to get its holder up alone (the shared tuning's, set by the
## binding): the DOWN card and the ring count them down from it.
var self_revive_total := 4.0
## Which way the local player faces, radians (their yaw): the frame sets it, a blow's bearing is
## turned by it. Not a topic: nothing redraws for it.
var facing := 0.0
var health := 100.0
var max_health := 100.0
var weapon_name := ""
var ammo_magazine := 0
var ammo_reserve := 0
## The held weapon is being reloaded; false for a weapon that uses no ammunition.
var ammo_reloading := false
var ammo_used := true
## The weapon in hand and the one put away last, with the rounds of each weapon heard of (id ->
## {"ammo", "reserve"}), from the weapons' events (see `HudLoadout`). The names and the ids of the
## weapons that use no ammunition are known from the shared definitions: the client sets them.
var weapon_id: StringName = &""
var holstered_id: StringName = &""
var rounds: Dictionary[StringName, Dictionary] = {}
var weapon_names: Dictionary[StringName, String] = {}
## The map's own names for its paid links (link id -> name), for the feed's line; empty on the lot.
var link_names: Dictionary[StringName, String] = {}
var ammo_free: Array[StringName] = []
## The weapons carried by slot, slot 1 first, `&""` for an empty place (`WeaponSlots`), and the
## slot (1-based) the weapon in hand is in, 0 for none. How many places the player has: the carry
## limit, raised by the perk that carries one more (#687).
var slot_ids: Array[StringName] = []
var slot_held := 0
var slot_count := WeaponSlots.count()
## The perks the local player has: the ids of the shop's tonics, in the shop's order. The frame says
## them as bits (`PerkEffects.mask_of`); the binding turns the bits into these. A down that takes
## the perks empties it.
var perks: Array[StringName] = []
var points := 0
## The local player's grenades.
var grenades := 0
var round_number := 0
var phase := PHASE_IDLE
## Seconds left of the break (counted down by `tick`; parts hear of it once a second, when the
## whole second they show changes).
var break_left := 0.0
## The zombies the round began with, and those still to be killed.
var zombies_total := 0
var zombies_left := 0
var fuel := 100.0
var fuel_capacity := 100.0
var fuel_low := false
var fuel_empty := false
## Circuit id -> lit, in the order the generator lists them.
var circuits: Dictionary[StringName, bool] = {}
## Player id -> {"name": String, "downed": bool, "points": int, "grenades": int, "seat": int,
## "look": Dictionary}, the local player included. The seat (0 to 7) picks the player's colour (the
## armband's); the server gives the lowest free one, so the state does too until it is told
## (a `player_look` event). The look is a `CharacterLook.to_dict` ({} for the seat's own preset).
## "bot" (true when a bot plays the seat: the roster shows BOT after the name, `name_of`) is the
## server's too. "kills", "downs", "revives" and "ping" (milliseconds, `NO_PING` when the night has
## no link to measure) are the server's counts, set from its frames and snapshot
## (`set_player_stats`), never counted here. "dead" (bled out), "bleed" (seconds a downed player has
## left), "revive" (the hold's progress, 0 to 1), "reviver" (who holds it, 0 for nobody) and
## "self_revive" (seconds left of the revive perk's own, 0 for none) are the server's too
## (`set_player_revive`).
var team: Dictionary[int, Dictionary] = {}
## Whole seconds the night has run, as the server counts them (a break and a round both count).
var night_clock := 0
## The interaction in reach: {} for none, else {"kind", "label", "cost"} (see `set_prompt`).
var prompt: Dictionary = {}
var game_over_reason := &""
## The name of the player who left last (their entry is gone from `team` by the time you hear).
var left_name := ""
## A small piece of equipment (a flare, a trap) and how many are left; "" for none. A negative
## count (`HudLoadout.NO_COUNT`) is a piece with nothing to count.
var equipment_name := ""
var equipment_count := 0
## Where the player is, and what to do next, as two lines under the round.
var area_name := ""
var objective := ""
## Markers in the world, projected by the client: each {"id", "kind" (objective or ally), "x", "y"
## (0..1 of the screen, outside that range when off-screen), "distance" in metres, "label",
## "important" (pinned to the screen edge with an arrow when off-screen)}.
var markers: Array[Dictionary] = []
## The bosses on the lot, each {"id", "type", "health", "max_health"}, in the order they came
## (from `zombie_spawn_requested` with `boss`, `zombie_damaged`, `zombie_removed`).
var bosses: Array[Dictionary] = []
## The special round running now (a kind's id), or `&""` in a normal round.
var special_id := &""
## The special round announced for the next round, as `special_round_announced` sent it (round,
## special_id, title, kind, boss_type, boss_count, seconds), or {} for none. Set by the event, or
## from the schedule for a HUD that joined in the break; gone once the round starts.
var announced: Dictionary = {}
## What the last special round paid when it was cleared: {"special_id", "reward"}; {} until then,
## and again from the next round's start.
var special_cleared: Dictionary = {}
## Counts every snapshot that restored a special round in progress, so a part that shows it (the
## banner) shows it once per restore.
var special_restored := 0
## The special rounds and when they come, as plain data from the shared tuning (`HudSpecials`).
var special_schedule: Dictionary = {}:
	set(value):
		special_schedule = value
		_mark(SPECIAL)
		_flush()

## What changed since the parts last heard, and what they are being told about right now.
var _dirty: Dictionary[StringName, bool] = {}
var _current: Dictionary[StringName, bool] = {}
var _held := 0


## Circuit ids and the tank size, which both sides know from the shared tuning.
func configure(capacity: float, circuit_ids: Array[StringName], lit: Array[StringName]) -> void:
	fuel_capacity = capacity
	fuel = capacity
	circuits.clear()
	for circuit_id in circuit_ids:
		circuits[circuit_id] = lit.has(circuit_id)
	_mark(FUEL)
	_flush()


func is_local_downed() -> bool:
	return bool(team.get(local_player_id, {}).get("downed", false))


## Whether the local player bled out (down until the round ends).
func is_local_dead() -> bool:
	return bool(team.get(local_player_id, {}).get("dead", false))


## The share of the bleed-out clock a downed player has left, 0 to 1.
func bleed_share(member: Dictionary) -> float:
	return clampf(float(member["bleed"]) / bleed_total, 0.0, 1.0) if bleed_total > 0.0 else 0.0


func fuel_fraction() -> float:
	return clampf(fuel / fuel_capacity, 0.0, 1.0) if fuel_capacity > 0.0 else 0.0


func can_afford(cost: int) -> bool:
	return points >= cost


## Whether `topic` is among what changed, for a part reacting to `changed`.
func is_dirty(topic: StringName) -> bool:
	return _current.has(topic)


## Holds `changed` back until the matching `release`: everything set in between reaches the parts as
## one change. Calls nest. `apply_events` does this for its batch; a network layer can hold a
## whole frame's events and readings.
func hold() -> void:
	_held += 1


func release() -> void:
	_held = maxi(_held - 1, 0)
	_flush()


# --- The local player's own readings ---


## Health is the rules' (`player_added`, `player_hurt`, `player_healed`, a snapshot); this sets it
## by hand for a tool or a capture.
func set_health(value: float, maximum: float = -1.0) -> void:
	if maximum > 0.0:
		_assign(&"max_health", maximum, HEALTH)
	_assign(&"health", clampf(value, 0.0, max_health), HEALTH)
	_flush()


func set_ammo(magazine: int, reserve: int, weapon := "", reloading := false, used := true) -> void:
	_assign(&"ammo_magazine", magazine, AMMO)
	_assign(&"ammo_reserve", reserve, AMMO)
	_assign(&"ammo_reloading", reloading, AMMO)
	_assign(&"ammo_used", used, AMMO)
	if weapon != "":
		_assign(&"weapon_name", weapon, AMMO)
	_flush()


## The weapons by slot and the slot in hand. The HUD draws the places up to `slot_count` (or as
## many as there are weapons).
func set_slots(ids: Array[StringName], held: int) -> void:
	_assign(&"slot_ids", ids, SLOTS)
	_assign(&"slot_held", held, SLOTS)
	_flush()


## How many places the player carries weapons in (the carry limit, a perk adds one).
func set_slot_count(count: int) -> void:
	_assign(&"slot_count", clampi(count, 1, WeaponSlots.MAX), SLOTS)
	_flush()


func set_equipment(equipment: String, count: int) -> void:
	_assign(&"equipment_name", equipment, HEALTH)
	_assign(&"equipment_count", count, HEALTH)
	_flush()


## Entering a new area names it (the HUD announces a change); the objective line stays put.
func set_area(area: String, next_objective := "") -> void:
	var entered := area != area_name
	_assign(&"area_name", area, OBJECTIVE)
	_assign(&"objective", next_objective, OBJECTIVE)
	_flush()
	if entered:
		event_applied.emit({"type": &"area_entered", "area": area})


func set_markers(list: Array[Dictionary]) -> void:
	markers = list
	_mark(MARKERS)
	_flush()


## The server's counts for one player: the zombies they killed, the times they went down, and the
## round trip it last heard from them (`NO_PING` for none). Whole counts, not changes, so a frame
## said twice changes nothing.
func set_player_stats(
	player_id: int, kills: int, downs: int, ping := NO_PING, revives := 0
) -> void:
	var member := _member(player_id)
	if (
		member["kills"] != kills
		or member["downs"] != downs
		or member["ping"] != ping
		or member["revives"] != revives
	):
		member["kills"] = kills
		member["downs"] = downs
		member["ping"] = ping
		member["revives"] = revives
		_mark(STATS)
	_flush()


## The server's word on one player's revive: whether they bled out, the seconds a downed player has
## left, how far the hold on them has got (0 to 1), who holds it (0 for nobody) and the seconds left
## of the revive perk getting them up alone (0 for none; the bleed-out clock stands still).
## Whole values, not changes, so a frame said twice changes nothing.
func set_player_revive(
	player_id: int, dead: bool, bleed: float, progress: float, reviver: int, self_revive := 0.0
) -> void:
	var member := _member(player_id)
	if (
		member["dead"] != dead
		or member["reviver"] != reviver
		or (float(member["self_revive"]) > 0.0) != (self_revive > 0.0)
	):
		_mark(TEAM)
	if (
		member["dead"] != dead
		or not is_equal_approx(member["bleed"], bleed)
		or not is_equal_approx(member["revive"], progress)
		or member["reviver"] != reviver
		or not is_equal_approx(member["self_revive"], self_revive)
	):
		member["dead"] = dead
		member["bleed"] = bleed
		member["revive"] = progress
		member["reviver"] = reviver
		member["self_revive"] = self_revive
		_mark(REVIVE)
	_flush()


## The perks the local player has now (shop tonic ids in the shop's order); the parts hear of a
## change only.
func set_perks(ids: Array[StringName]) -> void:
	if perks != ids:
		perks = ids.duplicate()
		_mark(PERKS)
	_flush()


## Whether the revive perk is getting the local player up alone now.
func is_local_self_reviving() -> bool:
	var me: Dictionary = team.get(local_player_id, {})
	return bool(me.get("downed", false)) and float(me.get("self_revive", 0.0)) > 0.0


## The night's clock in whole seconds, from the server.
func set_night_clock(seconds: int) -> void:
	_assign(&"night_clock", maxi(seconds, 0), STATS)
	_flush()


func local_name() -> String:
	return str(team.get(local_player_id, {}).get("name", ""))


## A name is kept to `HudStyle.NAME_LIMIT` characters: what a part shows is a short name.
func set_player_name(player_id: int, display_name: String) -> void:
	var member := _member(player_id)
	var shown := display_name.strip_edges().left(HudStyle.NAME_LIMIT)
	if member["name"] != shown:
		member["name"] = shown
		_mark(TEAM)
		if player_id == local_player_id:
			_mark(POINTS)
	_flush()


## An interaction the player stands at. `kind` is `buy_door`, `buy_weapon`, `buy_ammo`,
## `buy_grenades`, `buy_crane`, `fill_fuel`, `repair`, `circuit` or `revive`; `cost` is points (0
## for free); `label` names the thing and `detail` is the one line on what it does (a default per
## kind when empty).
func set_prompt(kind: StringName, label: String, cost := 0, detail := "") -> void:
	var next := {"kind": kind, "label": label, "cost": cost, "detail": detail}
	if prompt != next:
		prompt = next
		_mark(PROMPT)
	_flush()


func clear_prompt() -> void:
	if not prompt.is_empty():
		prompt = {}
		_mark(PROMPT)
		_flush()


## Counts the break down; the server's `break_started` sets it, this keeps it moving. The round
## part shows whole seconds, so it hears of the break only when the second it shows changes.
func tick(delta: float) -> void:
	if phase == PHASE_BREAK and break_left > 0.0:
		var shown := ceili(break_left)
		break_left = maxf(break_left - delta, 0.0)
		if ceili(break_left) != shown:
			_mark(ROUND)
			_flush()


# --- Rules events ---


## Mirrors one event. Unknown types are ignored: the rules grow events the HUD need not know.
func apply_event(event: Dictionary) -> void:
	var handler := _handler(StringName(event.get("type", &"")))
	if handler.is_valid():
		handler.call(event)
	_flush()
	event_applied.emit(event)


## Mirrors a batch of events, announcing one change for all of them (`event_applied` still comes
## once per event, with the state as that event left it).
func apply_events(events: Array) -> void:
	hold()
	for event in events:
		apply_event(event)
	release()


## Restores everything from `GameRules.to_dict()` (a late joiner, a reconnect); emits no events.
## Names are not in the rules: the ones already set stay with their players, and the server's
## (`names` in a WELCOME's snapshot) take their place.
func load_snapshot(data: Dictionary) -> void:
	hold()
	round_number = int(data.get("round", 0))
	phase = int(data.get("phase", PHASE_IDLE))
	break_left = float(data.get("break_left", 0.0))
	zombies_total = int(data.get("round_total", 0))
	var alive: Dictionary = data.get("zombies", {})
	zombies_left = alive.size() + int(data.get("spawn_left", 0))
	_restore_special(data, alive)
	var kept := {}
	for player_id in team:
		kept[player_id] = team[player_id]
	team.clear()
	var players: Dictionary = data.get("players", {})
	for player_id in players:
		var saved: Dictionary = players[player_id]
		var member := _member(int(player_id))
		if kept.has(int(player_id)):
			for field in ["name", "seat", "look", "ping"]:
				member[field] = kept[int(player_id)][field]
		member["downed"] = bool(saved.get("downed", false))
		member["dead"] = bool(saved.get("dead", false))
		member["bleed"] = float(saved.get("bleed_left", 0.0))
		member["self_revive"] = float(saved.get("self_revive_left", 0.0))
		member["revives"] = int(saved.get("revives", 0))
		member["points"] = int(saved.get("points", 0))
		member["grenades"] = int(saved.get("grenades", 0))
		member["kills"] = int(saved.get("kills", 0))
		member["downs"] = int(saved.get("downs", 0))
		member["bot"] = bool(saved.get("bot", false))
	night_clock = floori(float(data.get("night_time", 0.0)))
	# The server's names (a WELCOME's `names`): every client shows the same ones.
	var named: Variant = data.get("names", {})
	if typeof(named) == TYPE_DICTIONARY:
		for player_id in named:
			if team.has(int(player_id)):
				team[int(player_id)]["name"] = str(named[player_id]).strip_edges().left(
					HudStyle.NAME_LIMIT
				)
	var local: Dictionary = team.get(local_player_id, {})
	points = int(local.get("points", 0))
	grenades = int(local.get("grenades", 0))
	var mine: Dictionary = players.get(local_player_id, {})
	if mine.has("max_health"):
		_assign(&"max_health", float(mine["max_health"]), HEALTH)
		_assign(&"health", float(mine.get("health", max_health)), HEALTH)
	var generator: Dictionary = data.get("generator", {})
	_set_fuel(float(generator.get("fuel", fuel)))
	for circuit_id in generator.get("circuits", {}):
		circuits[StringName(circuit_id)] = bool(generator["circuits"][circuit_id])
	for topic in [ROUND, TEAM, FUEL, HEALTH, POINTS, PROMPT, STATS, REVIVE]:
		_mark(topic)
	release()


## The special round running and the bosses on the lot, from a snapshot. The announcement is not in
## it: a HUD that joins in the break gets the marquee from the schedule (`HudSpecials.coming`).
func _restore_special(data: Dictionary, alive: Dictionary) -> void:
	special_id = StringName(data.get("special_id", ""))
	announced = {}
	special_cleared = {}
	if special_id != &"":
		special_restored += 1
	bosses.clear()
	var boss_types := HudSpecials.boss_types(self)
	for zombie_id in alive:
		var zombie: Dictionary = alive[zombie_id]
		if boss_types.has(StringName(zombie.get("type", ""))):
			(
				bosses
				. append(
					{
						"id": int(zombie_id),
						"type": StringName(zombie["type"]),
						"health": float(zombie.get("health", 0.0)),
						"max_health": float(zombie.get("max_health", zombie.get("health", 0.0))),
					}
				)
			)
	bosses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	_mark(BOSS)
	_mark(SPECIAL)


func _handler(type: StringName) -> Callable:
	var handler := Callable()
	match type:
		&"phase_changed":
			handler = _on_phase_changed
		&"break_started":
			handler = _on_break_started
		&"round_started":
			handler = _on_round_started
		&"round_ended":
			handler = _on_round_ended
		&"special_round_announced":
			handler = _on_special_announced
		&"special_round_cleared":
			handler = _on_special_cleared
		&"zombie_spawn_requested":
			handler = _on_zombie_spawn_requested
		&"zombie_damaged":
			handler = _on_zombie_damaged
		&"zombie_removed":
			handler = _on_zombie_removed
		&"player_added":
			handler = _on_player_added
		&"bot_replaced":
			handler = _on_bot_replaced
		&"bot_seated":
			handler = _on_bot_seated
		&"grenade_count_changed":
			handler = _on_grenade_count_changed
		&"player_removed":
			handler = _on_player_removed
		&"player_downed":
			handler = _on_player_downed
		&"player_healed":
			handler = _on_player_healed
		&"player_revived":
			handler = _on_player_revived
		&"player_died":
			handler = _on_player_died
		&"self_revive_started":
			handler = _on_self_revive_started
		&"points_changed":
			handler = _on_points_changed
		&"fuel_changed":
			handler = func(e: Dictionary) -> void: _set_fuel(float(e["fuel"]))
		&"fuel_low":
			handler = func(_e: Dictionary) -> void: _assign(&"fuel_low", true, FUEL)
		&"fuel_empty":
			handler = func(_e: Dictionary) -> void: _set_fuel(0.0)
		&"circuit_changed":
			handler = func(e: Dictionary) -> void:
				_set_circuit(StringName(e["circuit_id"]), bool(e["on"]))
		&"game_over":
			handler = func(e: Dictionary) -> void:
				game_over_reason = StringName(e.get("reason", ""))
		&"purchase_made":
			handler = _on_purchase_made
		&"player_look":
			handler = _on_player_look
		&"player_named":
			handler = func(e: Dictionary) -> void:
				set_player_name(int(e["player_id"]), str(e["name"]))
		&"player_hurt":
			handler = _on_player_hurt
		&"weapon_replaced":
			handler = func(e: Dictionary) -> void: HudLoadout.apply(e, self)
		&"weapon_equipped", &"shot_fired", &"reload_started", &"reload_finished", &"ammo_added":
			handler = func(e: Dictionary) -> void: HudLoadout.apply(e, self)
	return handler


func _on_phase_changed(event: Dictionary) -> void:
	_assign(&"phase", int(event["phase"]), ROUND)


func _on_break_started(event: Dictionary) -> void:
	_assign(&"phase", PHASE_BREAK, ROUND)
	_assign(&"break_left", float(event["seconds"]), ROUND)


func _on_special_announced(event: Dictionary) -> void:
	announced = event.duplicate()
	_mark(SPECIAL)


func _on_special_cleared(event: Dictionary) -> void:
	special_cleared = {
		"special_id": StringName(event.get("special_id", &"")),
		"reward": int(event.get("reward", 0)),
	}
	_mark(SPECIAL)


func _on_round_started(event: Dictionary) -> void:
	_assign(&"special_id", StringName(event.get("special_id", &"")), SPECIAL)
	if not announced.is_empty() or not special_cleared.is_empty():
		announced = {}
		special_cleared = {}
		_mark(SPECIAL)
	_assign(&"phase", PHASE_ACTIVE, ROUND)
	_assign(&"round_number", int(event["round"]), ROUND)
	_assign(&"zombies_total", int(event["zombie_count"]), ROUND)
	_assign(&"zombies_left", zombies_total, ROUND)


func _on_round_ended(_event: Dictionary) -> void:
	_assign(&"zombies_left", 0, ROUND)
	_assign(&"special_id", &"", SPECIAL)
	if not bosses.is_empty():
		bosses.clear()
		_mark(BOSS)


func _on_zombie_removed(event: Dictionary) -> void:
	_assign(&"zombies_left", maxi(zombies_left - 1, 0), ROUND)
	var index := _boss_index(int(event.get("zombie_id", -1)))
	if index != -1:
		bosses.remove_at(index)
		_mark(BOSS)


func _on_zombie_spawn_requested(event: Dictionary) -> void:
	# A boss a snapshot already restored is not added twice when its spawn event was in flight.
	if bool(event.get("boss", false)) and _boss_index(int(event.get("zombie_id", -1))) == -1:
		(
			bosses
			. append(
				{
					"id": int(event.get("zombie_id", -1)),
					"type": StringName(event.get("zombie_type", &"")),
					"health": float(event["health"]),
					"max_health": float(event["health"]),
				}
			)
		)
		_mark(BOSS)


func _on_zombie_damaged(event: Dictionary) -> void:
	var index := _boss_index(int(event.get("zombie_id", -1)))
	if index != -1:
		bosses[index]["health"] = float(event["health"])
		if event.has("max_health"):
			bosses[index]["max_health"] = float(event["max_health"])
		_mark(BOSS)


func _boss_index(zombie_id: int) -> int:
	for index in bosses.size():
		if bosses[index]["id"] == zombie_id:
			return index
	return -1


func _on_player_added(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	var member := _member(player_id)
	member["bot"] = bool(event.get("bot", false))
	if player_id == local_player_id:
		_set_local_health(event)
	if event.has("grenades"):
		member["grenades"] = int(event["grenades"])
		if player_id == local_player_id:
			_assign(&"grenades", int(event["grenades"]), HEALTH)


## The server's word on where a player sits and what they wear: `player_id`, `seat`, `look` (a
## `CharacterLook.to_dict`). Not a rules event: the look is the lot's, sent once on join.
func _on_player_look(event: Dictionary) -> void:
	var member := _member(int(event["player_id"]))
	var look: Dictionary = event.get("look", {})
	if member["seat"] != int(event["seat"]) or member["look"] != look:
		member["seat"] = int(event["seat"])
		member["look"] = look
		_mark(TEAM)


func _on_grenade_count_changed(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	_member(player_id)["grenades"] = int(event["count"])
	if player_id == local_player_id:
		_assign(&"grenades", int(event["count"]), HEALTH)


func _on_points_changed(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	_member(player_id)["points"] = int(event["total"])
	if player_id == local_player_id:
		_assign(&"points", int(event["total"]), POINTS)
	else:
		_mark(TEAM)


func _on_purchase_made(event: Dictionary) -> void:
	if int(event.get("player_id", -1)) == local_player_id:
		clear_prompt()


func _on_player_hurt(event: Dictionary) -> void:
	if int(event.get("player_id", -1)) == local_player_id:
		_set_local_health(event)


func _on_player_healed(event: Dictionary) -> void:
	if int(event.get("player_id", -1)) == local_player_id:
		_set_local_health(event)


func _on_player_downed(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	_set_downed(player_id, true)
	var member := _member(player_id)
	member["dead"] = false
	member["bleed"] = float(event.get("bleed_seconds", bleed_total))
	member["revive"] = 0.0
	member["reviver"] = 0
	member["self_revive"] = 0.0
	_mark(REVIVE)
	if player_id == local_player_id:
		_assign(&"health", 0.0, HEALTH)


func _on_player_revived(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	_set_downed(player_id, false)
	var member := _member(player_id)
	member["dead"] = false
	member["bleed"] = 0.0
	member["revive"] = 0.0
	member["reviver"] = 0
	member["self_revive"] = 0.0
	_mark(REVIVE)


## The revive perk began to count: the DOWN card says so at once, the frame keeps the count.
func _on_self_revive_started(event: Dictionary) -> void:
	var member := _member(int(event["player_id"]))
	member["self_revive"] = float(event.get("seconds", self_revive_total))
	_mark(TEAM)
	_mark(REVIVE)


func _on_player_died(event: Dictionary) -> void:
	var member := _member(int(event["player_id"]))
	member["dead"] = true
	member["bleed"] = 0.0
	member["revive"] = 0.0
	member["reviver"] = 0
	member["self_revive"] = 0.0
	_mark(TEAM)
	_mark(REVIVE)


## Takes the local player's `health` (and `max_health`, when the event has it) off an event.
func _set_local_health(event: Dictionary) -> void:
	if event.has("max_health"):
		_assign(&"max_health", float(event["max_health"]), HEALTH)
	if event.has("health"):
		_assign(&"health", clampf(float(event["health"]), 0.0, max_health), HEALTH)


func _on_player_removed(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	left_name = str(team.get(player_id, {}).get("name", "PLAYER %d" % player_id))
	if team.erase(player_id):
		_mark(TEAM)


func _set_downed(player_id: int, downed: bool) -> void:
	var member := _member(player_id)
	if member["downed"] != downed:
		member["downed"] = downed
		_mark(TEAM)


func _set_fuel(value: float) -> void:
	var was := [fuel, fuel_empty, fuel_low]
	fuel = value
	fuel_empty = fuel <= 0.0
	fuel_low = fuel > 0.0 and fuel_fraction() <= LOW_FRACTION
	if was != [fuel, fuel_empty, fuel_low]:
		_mark(FUEL)


func _set_circuit(circuit_id: StringName, on: bool) -> void:
	if not circuits.has(circuit_id) or circuits[circuit_id] != on:
		circuits[circuit_id] = on
		_mark(FUEL)


## A player's entry, made (and the party told) when there is none.
func _member(player_id: int) -> Dictionary:
	if not team.has(player_id):
		team[player_id] = {
			"name": "PLAYER %d" % player_id,
			"downed": false,
			"points": 0,
			"grenades": 0,
			"seat": _free_seat(),
			"look": {},
			"kills": 0,
			"downs": 0,
			"revives": 0,
			"ping": NO_PING,
			"dead": false,
			"bleed": 0.0,
			"revive": 0.0,
			"reviver": 0,
			"self_revive": 0.0,
			"bot": false,
		}
		_mark(TEAM)
	return team[player_id]


## A person took the seat of a bot.
func _on_bot_replaced(event: Dictionary) -> void:
	var member := _member(int(event["player_id"]))
	if member["bot"]:
		member["bot"] = false
		_mark(TEAM)


## A bot took the seat of a person who left: the person is gone from the roster (their name is kept
## for the notice) and the seat is a bot's; the bot's own name arrives as a `player_named`.
func _on_bot_seated(event: Dictionary) -> void:
	var member := _member(int(event["player_id"]))
	left_name = str(member.get("name", "PLAYER %d" % int(event["player_id"])))
	member["bot"] = true
	_mark(TEAM)


## The name a roster shows for a team member (an entry of `team`): the name, then BOT for a bot, so
## a bot is never taken for a person. Every part of the HUD that writes a name calls this.
static func name_of(member: Dictionary) -> String:
	var shown := str(member.get("name", "SOMEONE")).to_upper()
	return shown + " BOT" if member.get("bot", false) else shown


## The lowest seat no one in the party has, as the server gives it (0 when all are taken).
func _free_seat() -> int:
	var taken: Array = []
	for member: Dictionary in team.values():
		taken.append(member["seat"])
	for seat in NightHost.MAX_PLAYERS:
		if not taken.has(seat):
			return seat
	return 0


## Sets a field and marks `topic`, only when the value is not the one already held.
func _assign(property: StringName, value: Variant, topic: StringName) -> void:
	if get(property) != value:
		set(property, value)
		_mark(topic)


func _mark(topic: StringName) -> void:
	_dirty[topic] = true


## Tells the parts what changed, once, unless a batch is held.
func _flush() -> void:
	if _held > 0 or _dirty.is_empty():
		return
	var outer := _current
	_current = _dirty
	_dirty = {}
	changed.emit()
	_current = outer
