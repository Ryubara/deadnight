class_name HudLoadout
extends RefCounted
## The weapons side of the HUD's mirror, as plain functions over a `HudState`: what the local
## player holds, what they put away last, and the rounds of each, kept from the weapons' own
## events (`CombatServer`: `weapon_equipped`, `shot_fired`, `reload_started`, `reload_finished`)
## and written into the state's readings (`set_ammo`, `set_equipment`). The data lives in the
## state (`weapon_id`, `holstered_id`, `rounds`, `weapon_names`, `ammo_free`), so it stays plain.
##
## Two sources keep it true. The weapons' events set the rounds at once (a shot, a reload, a weapon
## taken, and rounds added: a locker, a wall buy of a weapon already carried, a pickup). The frame
## then says what the server holds (`sync`: the weapon in hand, its rounds, whether it reloads, and
## the rounds of everything carried), so a change that sent no event, or one the HUD missed, shows
## on the same tick all the same.
##
## The ammo card reads the held weapon: magazine, reserve, name, and whether it is reloading. The
## equipment slot reads the weapon put away last, with the rounds it has left (magazine and
## reserve together); a weapon that uses no ammunition (the crowbar) has no count.
##
## Whatever ammunition fields the weapons' events carry are read as they are: `ammo` for the
## magazine and `reserve` for the rest. How the reserve comes to be (a starting stock, a shop) is
## the weapons' and the rules' business.

## The weapons' events this reads; the binding forwards these and no other weapon event.
const EVENTS: Array[StringName] = [
	&"weapon_replaced",
	&"weapon_equipped",
	&"shot_fired",
	&"reload_started",
	&"reload_round",
	&"reload_interrupted",
	&"reload_finished",
	&"ammo_added",
	&"weapon_upgraded"
]
## The equipment count of a weapon that has no rounds to count.
const NO_COUNT := -1


## Mirrors one weapons' event for the local player; any other is left alone.
static func apply(event: Dictionary, state: HudState) -> void:
	var owner_id := int(event.get("player_id", event.get("shooter_id", -1)))
	if owner_id != state.local_player_id:
		return
	var weapon_id := StringName(event.get("weapon_id", &""))
	match event["type"]:
		&"weapon_replaced":
			# The weapon in hand is gone, not put away: the other one stays the one put away. Its
			# slot stays empty until the weapon that replaces it is equipped into it.
			state.weapon_id = &""
			state.rounds.erase(StringName(event["dropped"]))
			var emptied := state.slot_ids.duplicate()
			var at := emptied.find(StringName(event["dropped"]))
			if at >= 0:
				emptied[at] = &""
			state.set_slots(emptied, 0)
		&"weapon_equipped":
			equip(weapon_id, int(event["ammo"]), int(event["reserve"]), state)
		&"shot_fired", &"reload_finished":
			if weapon_id == state.weapon_id:
				_count(state, weapon_id, int(event["ammo"]), int(event["reserve"]))
				_show(state, false)
		&"reload_started":
			if weapon_id == state.weapon_id:
				_show(state, true)
		&"reload_round":
			# A by-round reload put one more round in the magazine; it goes on.
			if weapon_id == state.weapon_id:
				_count(state, weapon_id, int(event["ammo"]), int(event["reserve"]))
				_show(state, true)
		&"reload_interrupted":
			if weapon_id == state.weapon_id:
				_count(state, weapon_id, int(event["ammo"]), int(event["reserve"]))
				_show(state, false)
		&"weapon_upgraded":
			# A re-cut: the name changes, and the magazine and reserve come back full.
			state.weapon_names[weapon_id] = String(event["display_name"])
			_count(state, weapon_id, int(event["ammo"]), int(event["reserve"]))
			_show(state, false)
		&"ammo_added":
			# Rounds for the weapon in hand move the card; for one put away, the equipment slot.
			_count(state, weapon_id, int(event["ammo"]), int(event["reserve"]))
			_show(state, state.ammo_reloading)


## Reads the local player's entry of a frame (`NightServer` frame: `weapon`, `ammo`, `reserve`,
## `reloading`, `arms`, the id of each weapon carried to `[ammo, reserve, tier]`, the tier 1 for a
## re-cut weapon) into the state. The frame is the server's own word, so it wins over what the
## events said; a state it already matches announces nothing.
static func sync(me: Dictionary, state: HudState) -> void:
	var weapon := StringName(me.get("weapon", &""))
	if weapon == &"":
		return
	state.hold()
	var arms: Dictionary = me.get("arms", {})
	# The server's order of the weapons carried is the order of the slots.
	var placed: Array[StringName] = []
	for carried: StringName in arms:
		placed.append(carried)
	for carried: StringName in arms:
		var rounds: Array = arms[carried]
		_count(state, carried, int(rounds[0]), int(rounds[1]))
		if rounds.size() > 2 and int(rounds[2]) > 0:
			state.weapon_names[carried] = _recut_name(carried)
	if weapon != state.weapon_id and state.weapon_id != &"":
		state.holstered_id = state.weapon_id
	state.weapon_id = weapon
	_count(state, weapon, int(me["ammo"]), int(me["reserve"]))
	_show_slots(state, bool(me.get("reloading", false)), placed)
	state.release()


## Takes `weapon_id` in hand with these rounds; the weapon that was in hand is put away. A late
## joiner calls this from the frame's reading, since no event is replayed.
static func equip(weapon_id: StringName, ammo: int, reserve: int, state: HudState) -> void:
	if weapon_id != state.weapon_id and state.weapon_id != &"":
		state.holstered_id = state.weapon_id
	state.weapon_id = weapon_id
	_count(state, weapon_id, ammo, reserve)
	_show_slots(state, false, _seated(state, weapon_id))


## The name a re-cut weapon has, from the shipped table (its profile's own, or the prefix and its
## name): what a late joiner shows until the `weapon_upgraded` event, which brings the server's
## name, would have said it.
static func _recut_name(weapon_id: StringName) -> String:
	var spec := UpgradeTuning.shipped()
	var cut := spec.profile_of(weapon_id)
	var plain := _base_name(weapon_id)
	return cut.name_of(plain, spec.name_prefix) if cut != null else spec.name_prefix + plain


## The name a weapon has as it is shipped, from the catalogue.
static func _base_name(weapon_id: StringName) -> String:
	var def := WeaponCatalog.get_def(weapon_id)
	return def.display_name if def != null else String(weapon_id)


static func name_of(weapon_id: StringName, state: HudState) -> String:
	return state.weapon_names.get(weapon_id, String(weapon_id))


static func _count(state: HudState, weapon_id: StringName, ammo: int, reserve: int) -> void:
	state.rounds[weapon_id] = {"ammo": ammo, "reserve": reserve}


## Puts a weapon taken in hand into the slot it is in, or the first empty one (the slot of the
## weapon it replaced), or a new one after the last.
static func _seated(state: HudState, weapon_id: StringName) -> Array[StringName]:
	var seated := state.slot_ids.duplicate()
	if seated.has(weapon_id):
		return seated
	var hole := seated.find(&"")
	if hole >= 0:
		seated[hole] = weapon_id
	else:
		seated.append(weapon_id)
	return seated


static func _show(state: HudState, reloading: bool) -> void:
	_show_slots(state, reloading, state.slot_ids)


## Writes the ammo card and the equipment slot from what the state holds, and the weapon slots
## (`ids`, the weapons by slot).
static func _show_slots(state: HudState, reloading: bool, ids: Array[StringName]) -> void:
	state.set_slots(ids, ids.find(state.weapon_id) + 1)
	var none := {"ammo": 0, "reserve": 0}
	var held: Dictionary = state.rounds.get(state.weapon_id, none)
	var used := not state.ammo_free.has(state.weapon_id)
	state.set_ammo(held["ammo"], held["reserve"], name_of(state.weapon_id, state), reloading, used)
	if state.holstered_id == &"":
		state.set_equipment("", 0)
		return
	var away: Dictionary = state.rounds.get(state.holstered_id, none)
	var count: int = away["ammo"] + away["reserve"]
	if state.ammo_free.has(state.holstered_id):
		count = NO_COUNT
	state.set_equipment(name_of(state.holstered_id, state), count)
