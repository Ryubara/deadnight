class_name HudSpecials
extends RefCounted
## What the HUD knows of the special rounds and the words it puts to them. The schedule is plain
## data copied once from the shared tuning (`schedule_of`) into `HudState.special_schedule`;
## everything else reads the state and nothing more, so a client builds it from what the server
## replicates.


## The schedule as plain values: a special round every `every` rounds from `first`, the kinds in
## `order` in turn, each described in `kinds`.
static func schedule_of(tuning: SpecialTuning) -> Dictionary:
	var order: Array[StringName] = []
	var kinds := {}
	for kind in tuning.rounds:
		var is_boss := kind.kind == SpecialRound.Kind.BOSS
		order.append(kind.id)
		kinds[kind.id] = {
			"special_id": kind.id,
			"title": kind.title,
			"kind": &"boss" if is_boss else &"only",
			"boss_type": kind.boss_type if is_boss else &"",
			"only_type": &"" if is_boss else kind.only_type,
			"boss_count": kind.boss_count,
			"players_per_extra_boss": kind.players_per_extra_boss,
		}
	return {"every": tuning.every, "first": tuning.first_round, "order": order, "kinds": kinds}


## The name on the marquee for a special round's id; the id itself in words when unknown.
static func title(state: HudState, id: StringName) -> String:
	var kinds: Dictionary = state.special_schedule.get("kinds", {})
	if kinds.has(id):
		return kinds[id]["title"]
	if state.announced.get("special_id", &"") == id:
		return str(state.announced["title"])
	return String(id).replace("_", " ").capitalize()


## The special round coming after this break ({} for none): the announcement, else the one the
## schedule says follows the round just played, for a HUD that joined during the break.
static func coming(state: HudState) -> Dictionary:
	if not state.announced.is_empty():
		return _announced(state)
	if state.phase != HudState.PHASE_BREAK:
		return {}
	return _describe(state, _kind_for(state, state.round_number + 1), state.round_number + 1)


## The announcement with what the event leaves out (the type a round of one type is made of)
## filled in from the schedule.
static func _announced(state: HudState) -> Dictionary:
	var described := state.announced.duplicate()
	var kinds: Dictionary = state.special_schedule.get("kinds", {})
	var kind: Dictionary = kinds.get(described.get("special_id", &""), {})
	for key in ["only_type", "players_per_extra_boss"]:
		if not described.has(key) and kind.has(key):
			described[key] = kind[key]
	return described


## The running special round as the marquee describes it ({} in a normal round).
static func running(state: HudState) -> Dictionary:
	var kinds: Dictionary = state.special_schedule.get("kinds", {})
	if state.special_id == &"" or not kinds.has(state.special_id):
		return {}
	return _describe(state, kinds[state.special_id], state.round_number)


## The zombie types a special round names as its bosses.
static func boss_types(state: HudState) -> Array[StringName]:
	var types: Array[StringName] = []
	for kind: Dictionary in state.special_schedule.get("kinds", {}).values():
		if kind["kind"] == &"boss":
			types.append(kind["boss_type"])
	return types


## What a special round brings, as the line under its name: "THE HEADLINER ARRIVES", "2 HEADLINERS
## ARRIVE" or "ONLY RUNNERS". `info` is `coming` or `running`.
static func brings(info: Dictionary) -> String:
	if info.get("kind", &"") == &"boss":
		var count := int(info.get("boss_count", 1))
		var word := String(info.get("boss_type", &"headliner")).to_upper()
		return "THE %s ARRIVES" % word if count == 1 else "%d %sS ARRIVE" % [count, word]
	return "ONLY %sS" % String(info.get("only_type", &"")).to_upper()


## The kind that `round_of` is, by the schedule ({} for an ordinary round): the rules' own
## `SpecialTuning.special_for`.
static func _kind_for(state: HudState, round_of: int) -> Dictionary:
	var schedule := state.special_schedule
	var every: int = schedule.get("every", 0)
	var first: int = schedule.get("first", 0)
	var order: Array = schedule.get("order", [])
	if every <= 0 or order.is_empty() or round_of < first or (round_of - first) % every != 0:
		return {}
	return schedule["kinds"][order[((round_of - first) / every) % order.size()]]


## A kind as the marquee shows it for a round and the party as it stands (a boss round brings one
## more boss for every `players_per_extra_boss` players beyond the first).
static func _describe(state: HudState, kind: Dictionary, round_of: int) -> Dictionary:
	if kind.is_empty():
		return {}
	var described := kind.duplicate()
	described["round"] = round_of
	if kind["kind"] == &"boss":
		var extra := maxi(state.team.size() - 1, 0) / maxi(int(kind["players_per_extra_boss"]), 1)
		described["boss_count"] = int(kind["boss_count"]) + extra
	return described
