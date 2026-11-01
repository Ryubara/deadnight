class_name NightHudBinding
extends RefCounted
## Joins the HUD (`game/ui/hud/`) to a night. The HUD reads a `HudState` and nothing else; this
## feeds that state from what a client hears and nothing more: `ClientState.event_received`. The
## rules' events (round, points, party, fuel, purchases, and the player's health: `player_added`,
## `player_hurt`, `player_healed`, `player_downed`) go in as they are, and so do the weapons' events
## the ammo card and the equipment slot read (`HudLoadout.EVENTS`: equipped, shot, reload). Each
## `frame` carries what neither announces: which way the local player faces, what the hand would
## do (the prompt at a door or a breach), and, once, the weapon in hand for a HUD that joined after
## its events.

## What the player is told at each door: the name on the card (the shop ids are the shop's).
const DOOR_NAMES := {
	&"door_concession": "Concession stand",
	&"door_yard": "Generator yard",
	&"door_booth": "Projection booth",
	&"door_back_lot": "Back lot",
	&"door_road": "The road",
}
const BREACH_NAME := "Broken fence"
const CRANE_NAME := "Prize crane"

var _hud: Hud
var _state: ClientState
var _weapon_names: Dictionary[StringName, String] = {}


## `hud` is in the tree or about to be; `state` is the client's; `server` is read once, for the
## numbers both sides know from the shared tuning (the fuel tank), and not after.
func _init(hud: Hud, state: ClientState, server: NightServer) -> void:
	_hud = hud
	_state = state
	var ammo_free: Array[StringName] = []
	for def in WeaponCatalog.all():
		_weapon_names[def.id] = def.display_name
		if def.is_melee():
			ammo_free.append(def.id)
	hud.state.weapon_names = _weapon_names
	hud.state.ammo_free = ammo_free
	var fuel: FuelTuning = server.rules.tuning.fuel
	hud.state.local_player_id = state.player_id
	hud.state.configure(fuel.capacity, fuel.circuit_drain.keys(), fuel.start_circuits)
	state.event_received.connect(_on_event)


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"frame":
			_on_frame()
		_:
			if (
				HudLoadout.EVENTS.has(event["type"])
				or not NightServer.COMBAT_EVENTS.has(event["type"])
			):
				_hud.state.apply_event(event)


func _on_frame() -> void:
	var state := _hud.state
	var me := _state.me()
	if me.is_empty():
		return
	state.facing = me["facing"]
	# The weapons' events set the ammunition; a HUD that joined late has heard none, so the frame
	# gives it the weapon in hand once.
	var weapon: StringName = me["weapon"]
	if state.weapon_id == &"" and weapon != &"":
		HudLoadout.equip(weapon, me["ammo"], me["reserve"], state)
	_set_prompt(me["prompt"])


func _set_prompt(prompt: Dictionary) -> void:
	var state := _hud.state
	var kind: StringName = prompt.get("kind", &"")
	match kind:
		&"door":
			var label: String = DOOR_NAMES.get(prompt["id"], "A way through")
			if state.prompt.get("label") != label or state.prompt.get("cost") != prompt["price"]:
				state.set_prompt(&"buy_door", label, prompt["price"])
		&"weapon":
			_offer(&"buy_weapon", _weapon_name(prompt["weapon"]), prompt["price"], "")
		&"crane":
			_offer(&"buy_crane", CRANE_NAME, prompt["price"], "")
		&"ammo":
			var label := "%s rounds" % _weapon_name(prompt["weapon"])
			_offer(
				&"buy_ammo", label, prompt["price"], "%d ROUNDS FOR YOUR RESERVE" % prompt["rounds"]
			)
		&"repair":
			if state.prompt.get("kind") != &"repair":
				state.set_prompt(&"repair", BREACH_NAME)
		_:
			state.clear_prompt()


func _offer(kind: StringName, label: String, cost: int, detail: String) -> void:
	var state := _hud.state
	var now := state.prompt
	if (
		now.get("kind") != kind
		or now.get("label") != label
		or now.get("cost") != cost
		or now.get("detail") != detail
	):
		state.set_prompt(kind, label, cost, detail)


func _weapon_name(weapon: StringName) -> String:
	return _weapon_names.get(weapon, str(weapon))
