class_name NightMoments
extends RefCounted
## The odd and together stats of a night (`docs/design/progression.md#what-a-night-counts`): a round
## cleared without a shot, three boards in ten seconds, a round in the dark, a blast that killed
## three. A `NightTally` hands it the events it listens to (`LISTENS`) and it credits the tally,
## so a server, a client and a test count the same night the same way. It reads no game object:
## everything is in the events a client hears (a frame carries the tick, the circuits, the
## players' positions and ammunition).
##
## Time is the frame's `tick` at `TICK_SECONDS`: an event takes the time of the last frame, a
## sixtieth of a second behind. What each stat means is the constant of its window below and
## `ChallengeStats`' comment; the challenges' words name the same numbers.
##
## What it costs: a kill adds one lookup, one dictionary write and two compares (a crawler killed
## with the crowbar adds a list); a frame adds a few lookups a player; every other event it listens
## to is rare (a round, a board, a purchase, a blast, a circuit, a down).

## The events this listens to: the tally passes nothing else.
const LISTENS: Dictionary[StringName, bool] = {
	&"frame": true,
	&"player_added": true,
	&"settings_changed": true,
	&"shot_fired": true,
	&"zombie_removed": true,
	&"blast_resolved": true,
	&"board_repaired": true,
	&"purchase_made": true,
	&"player_downed": true,
	&"circuit_changed": true,
	&"round_started": true,
	&"round_ended": true,
	&"game_over": true,
	# The hidden challenges' (`HiddenMoments`, called from the arms below).
	&"door_opened": true,
	&"break_started": true,
	&"player_died": true,
}
## A server step (`Night.STEP`; a test keeps the two equal).
const TICK_SECONDS := 1.0 / 60.0
## Early bird: a door bought in the night's first seconds.
const EARLY_DOOR_SECONDS := 30.0
## Door to door: every way through open while fewer than this many rounds have started.
const ALL_DOORS_BEFORE_ROUND := 5
## Fell asleep in the car: downed in this many seconds of a round.
const QUICK_DOWN_SECONDS := 5.0
## Carpenter's rush: this many boards on one window by one player in these seconds.
const RUSH_BOARDS := 3
const RUSH_SECONDS := 10.0
## Pit crew: a board put up while a teammate put one up on the same window this lately.
const PIT_SECONDS := 6.0
## Whack-a-mole: this many of this kind of dead, with this weapon, in these seconds.
const RUN_KILLS := 5
const RUN_SECONDS := 30.0
const RUN_TYPE := &"crawler"
const RUN_WEAPON := &"crowbar"
## Two's company: people (not bots) in the lot at the end of the night.
const TOGETHER := 2
## Whole crew: players in the round, at least.
const CREW := 2

## The hidden challenges' stats: called from the arms for the rare events it needs, with no lookup
## of its own per event and nothing per frame outside a break (the late-round budget).
var _hidden := HiddenMoments.new()
var _now := 0.0
var _map := ""
var _door_ids: Array[StringName] = []
var _booth := PackedFloat32Array()
var _round := 0
var _round_began := 0.0
var _active := false
var _dark := false
var _lit: Dictionary[StringName, bool] = {}
var _bots: Dictionary[int, bool] = {}
## Players in the lot when the round began, who stay counted for it while they stay.
var _in_round: Dictionary[int, bool] = {}
var _from_start: Dictionary[int, bool] = {}
var _spent: Dictionary[int, bool] = {}
var _fired: Dictionary[int, bool] = {}
var _killed: Dictionary[int, bool] = {}
var _magazine: Dictionary[int, int] = {}
var _reserve: Dictionary[int, int] = {}
var _inside: Dictionary[int, bool] = {}
var _booth_whole: Dictionary[int, bool] = {}
var _melee: Dictionary[StringName, bool] = {}
var _doors_open: Dictionary[StringName, bool] = {}
var _doors_done := false
## Player id -> the times of the crawlers they put down with the crowbar.
var _runs: Dictionary[int, Array] = {}
## Barricade id -> player id -> the times of their boards; and the time of their last.
var _mends: Dictionary[StringName, Dictionary] = {}
var _last_mend: Dictionary[StringName, Dictionary] = {}


func _init() -> void:
	_hidden.bots = _bots
	_hidden.doors_open = _doors_open


## What the night is played on: the shop's doors (`ShopItem.Kind.DOOR`) of `tuning` and the map's
## id ("" is the default map). The tally calls it before the night's events.
func know(tuning: RulesTuning, map_id: String = "") -> void:
	_door_ids.clear()
	if tuning != null:
		for item in tuning.economy.items:
			if item.kind == ShopItem.Kind.DOOR:
				_door_ids.append(item.id)
	_set_map(map_id)


## Says whether a bot plays the seat.
func set_bot(player_id: int, bot: bool) -> void:
	_bots[player_id] = bot


## A new night: what was counted is forgotten, who is a bot and what is known of the map is kept.
func reset() -> void:
	_now = 0.0
	_round = 0
	_active = false
	_dark = false
	_doors_done = false
	_doors_open.clear()
	_hidden.reset()
	for each: Dictionary in [
		_in_round,
		_from_start,
		_spent,
		_fired,
		_killed,
		_magazine,
		_reserve,
		_inside,
		_booth_whole,
		_runs,
		_mends,
		_last_mend,
		_lit
	]:
		each.clear()


## A person takes a seat that was another's: what the earlier player did is not theirs.
func forget(player_id: int) -> void:
	_hidden.forget(player_id)
	for each: Dictionary in [
		_in_round,
		_from_start,
		_spent,
		_fired,
		_killed,
		_magazine,
		_reserve,
		_inside,
		_booth_whole,
		_runs
	]:
		each.erase(player_id)


func observe(event: Dictionary, tally: NightTally) -> void:
	match event["type"]:
		&"frame":
			_on_frame(event)
		&"player_added":
			_bots[int(event["player_id"])] = event.get("bot", false)
		&"settings_changed":
			var settings: Dictionary = event.get("settings", {})
			_set_map(String(settings.get("map", "")))
		&"shot_fired":
			_on_shot(event)
		&"zombie_removed":
			_on_removed(event, tally)
		&"blast_resolved":
			if int(event["kills"]) > 0:
				tally.reach(int(event["player_id"]), ChallengeStats.BLAST_BEST, int(event["kills"]))
		&"board_repaired":
			_on_board(event, tally)
		&"purchase_made":
			_on_purchase(event, tally)
		&"player_downed":
			_on_downed(int(event["player_id"]), tally)
		&"circuit_changed":
			_lit[event["circuit_id"]] = event["on"]
			if event["on"]:
				_dark = false
		&"round_started":
			_on_round_started(int(event["round"]), tally)
		&"round_ended":
			_on_round_ended(event, tally)
		&"game_over":
			_on_game_over(event, tally)
		&"door_opened":
			_hidden.door_opened(event["door_id"])
		&"break_started":
			_hidden.break_started(int(event["next_round"]))
		&"player_died":
			_hidden.died(int(event["player_id"]), tally)


func _set_map(map_id: String) -> void:
	if map_id == "" and _map != "":
		return
	_map = map_id if map_id != "" else MapRegistry.DEFAULT
	_booth = ChallengeAreas.rect(_map, ChallengeAreas.BOOTH)
	_hidden.set_map(_map)


func _on_frame(event: Dictionary) -> void:
	if _hidden.in_break:
		_hidden.on_break_frame(event)
	if event.has("tick"):
		_now = float(event["tick"]) * TICK_SECONDS
	if event.has("round"):
		_round = int(event["round"])
	if event.has("circuits"):
		_read_circuits(event["circuits"])
	if event.has("doors") and event["doors"].size() != _doors_open.size():
		for door: StringName in event["doors"]:
			_doors_open[door] = true
	var players: Dictionary = event.get("players", {})
	for id: int in players:
		var fields: Dictionary = players[id]
		if fields.has("ammo"):
			_magazine[id] = int(fields["ammo"])
		if fields.has("reserve"):
			_reserve[id] = int(fields["reserve"])
		if _booth.size() == 4 and fields.has("pos"):
			_read_position(id, fields["pos"])


func _read_circuits(circuits: Dictionary) -> void:
	_lit.clear()
	for circuit: StringName in circuits:
		_lit[circuit] = circuits[circuit]
		if circuits[circuit]:
			_dark = false


func _read_position(id: int, at: Vector3) -> void:
	var in_booth := ChallengeAreas.contains(_booth, at)
	_inside[id] = in_booth
	if not in_booth:
		_booth_whole.erase(id)


func _on_shot(event: Dictionary) -> void:
	var id := int(event["shooter_id"])
	var weapon := StringName(event["weapon_id"])
	_magazine[id] = int(event.get("ammo", 0))
	_reserve[id] = int(event.get("reserve", 0))
	if not _is_melee(weapon):
		_fired[id] = true


func _on_removed(event: Dictionary, tally: NightTally) -> void:
	var killer := int(event["killer_id"])
	if event["cause"] != &"killed" or killer < 0:
		return
	_killed[killer] = true
	if event["zombie_type"] == RUN_TYPE and event["melee"] and tally.held_by(killer) == RUN_WEAPON:
		_on_run_kill(killer, tally)


func _on_run_kill(killer: int, tally: NightTally) -> void:
	var times: Array = _runs.get(killer, [])
	times.append(_now)
	while times[0] < _now - RUN_SECONDS:
		times.pop_front()
	if times.size() >= RUN_KILLS:
		times.clear()
		tally.credit(killer, ChallengeStats.CRAWLER_RUNS)
	_runs[killer] = times


func _on_board(event: Dictionary, tally: NightTally) -> void:
	var id := int(event["player_id"])
	var window: StringName = event["barricade_id"]
	var mine: Dictionary = _mends.get(window, {})
	var times: Array = mine.get(id, [])
	times.append(_now)
	while times[0] < _now - RUSH_SECONDS:
		times.pop_front()
	if times.size() >= RUSH_BOARDS:
		times.clear()
		tally.credit(id, ChallengeStats.BOARD_RUSHES)
	mine[id] = times
	_mends[window] = mine
	var lately: Dictionary = _last_mend.get(window, {})
	for other: int in lately:
		if other != id and lately[other] >= _now - PIT_SECONDS:
			tally.credit(id, ChallengeStats.BOARDS_SHARED)
			break
	lately[id] = _now
	_last_mend[window] = lately


func _on_purchase(event: Dictionary, tally: NightTally) -> void:
	var id := int(event["player_id"])
	var price := int(event.get("price", 0))
	if price > 0:
		_spent[id] = true
		tally.credit(id, ChallengeStats.POINTS_SPENT, price)
	var item: StringName = event["item_id"]
	if not _door_ids.has(item):
		return
	if _now < EARLY_DOOR_SECONDS:
		tally.credit(id, ChallengeStats.DOORS_EARLY)
	_doors_open[item] = true
	if not _doors_done and _doors_open.size() >= _door_ids.size():
		_doors_done = true
		if _round < ALL_DOORS_BEFORE_ROUND:
			for each in tally.present_ids():
				tally.credit(each, ChallengeStats.DOORS_ALL_EARLY)


func _on_downed(id: int, tally: NightTally) -> void:
	if _active and _now - _round_began <= QUICK_DOWN_SECONDS:
		tally.credit(id, ChallengeStats.DOWNS_EARLY)


func _on_round_started(round_number: int, tally: NightTally) -> void:
	_round = round_number
	_round_began = _now
	_active = true
	_dark = not _lit.is_empty() and not _lit.values().has(true)
	_in_round.clear()
	_fired.clear()
	_killed.clear()
	_booth_whole.clear()
	var present := tally.present_ids()
	if round_number == 1:
		_from_start.clear()
	for id in present:
		_in_round[id] = true
		if round_number == 1:
			_from_start[id] = true
		if _inside.get(id, false):
			_booth_whole[id] = true
		if _from_start.has(id) and not _spent.has(id):
			tally.reach(id, ChallengeStats.ROUND_UNSPENT, round_number)
	_hidden.round_started(round_number, tally)


func _on_round_ended(event: Dictionary, tally: NightTally) -> void:
	_active = false
	var standing: Array = event.get("standing", [])
	var crew: Array[int] = []
	for id: int in _in_round:
		if tally.is_present(id):
			crew.append(id)
	var whole := crew.size() >= CREW
	for id in crew:
		whole = whole and standing.has(id)
	for id in crew:
		if not standing.has(id):
			continue
		if not _fired.has(id):
			tally.credit(id, ChallengeStats.ROUNDS_UNFIRED)
		if not _killed.has(id):
			tally.credit(id, ChallengeStats.ROUNDS_NO_KILLS)
		if _is_dry(id, tally):
			tally.credit(id, ChallengeStats.ROUNDS_DRY)
		if _booth_whole.has(id):
			tally.credit(id, ChallengeStats.ROUNDS_BOOTH)
		if _dark:
			tally.reach(id, ChallengeStats.ROUND_DARK, int(event["round"]))
		if whole:
			tally.credit(id, ChallengeStats.ROUNDS_WHOLE)


func _on_game_over(event: Dictionary, tally: NightTally) -> void:
	var people: Array[int] = []
	for id in tally.present_ids():
		tally.credit(id, ChallengeStats.map_nights(StringName(_map_id())))
		if not _bots.get(id, false):
			people.append(id)
	if people.size() >= TOGETHER:
		for id in people:
			tally.credit(id, ChallengeStats.NIGHTS_TOGETHER)
	_hidden.game_over(event, tally)


func _map_id() -> String:
	return _map if _map != "" else MapRegistry.DEFAULT


## Whether the gun in this player's hands has nothing in the magazine and nothing in reserve.
func _is_dry(id: int, tally: NightTally) -> bool:
	var held := tally.held_by(id)
	return (
		held != &""
		and not _is_melee(held)
		and _magazine.get(id, 1) == 0
		and _reserve.get(id, 1) == 0
	)


func _is_melee(weapon: StringName) -> bool:
	if not _melee.has(weapon):
		var def := WeaponCatalog.get_def(weapon) if WeaponCatalog.has(weapon) else null
		_melee[weapon] = def != null and def.is_melee()
	return _melee[weapon]
