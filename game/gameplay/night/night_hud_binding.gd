class_name NightHudBinding
extends RefCounted
## Joins the HUD (`game/ui/hud/`) to a night. The HUD reads a `HudState` and nothing else; this
## feeds that state from what a client hears and nothing more: `ClientState.event_received`. The
## rules' events (round, points, party, fuel, purchases, and the player's health: `player_added`,
## `player_hurt`, `player_healed`, `player_downed`) go in as they are; each `frame` carries what
## the rules do not announce, which way the local player faces, the held weapon's ammunition
## (until the weapons' events feed it, #133) and what the hand would do (the prompt at a door or a
## breach).

## What the player is told at each door: the name on the card (the shop ids are the shop's).
const DOOR_NAMES := {
	&"door_concession": "Concession stand",
	&"door_yard": "Generator yard",
	&"door_booth": "Projection booth",
	&"door_back_lot": "Back lot",
	&"door_road": "The road",
}
const BREACH_NAME := "Broken fence"

var _hud: Hud
var _state: ClientState
var _weapon_names: Dictionary[StringName, String] = {}


## `hud` is in the tree or about to be; `state` is the client's; `server` is read once, for the
## numbers both sides know from the shared tuning (the fuel tank), and not after.
func _init(hud: Hud, state: ClientState, server: NightServer) -> void:
	_hud = hud
	_state = state
	for def in WeaponCatalog.all():
		_weapon_names[def.id] = def.display_name
	var fuel: FuelTuning = server.rules.tuning.fuel
	hud.state.local_player_id = state.player_id
	hud.state.configure(fuel.capacity, fuel.circuit_drain.keys(), fuel.start_circuits)
	state.event_received.connect(_on_event)


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"frame":
			_on_frame()
		_:
			if not NightServer.COMBAT_EVENTS.has(event["type"]):
				_hud.state.apply_event(event)


func _on_frame() -> void:
	var state := _hud.state
	var me := _state.me()
	if me.is_empty():
		return
	state.facing = me["facing"]
	var weapon: StringName = me["weapon"]
	var weapon_name: String = _weapon_names.get(weapon, str(weapon))
	if (
		me["ammo"] != state.ammo_magazine
		or me["reserve"] != state.ammo_reserve
		or weapon_name != state.weapon_name
	):
		state.set_ammo(me["ammo"], me["reserve"], weapon_name)
	_set_prompt(me["prompt"])


func _set_prompt(prompt: Dictionary) -> void:
	var state := _hud.state
	var kind: StringName = prompt.get("kind", &"")
	match kind:
		&"door":
			var label: String = DOOR_NAMES.get(prompt["id"], "A way through")
			if state.prompt.get("label") != label or state.prompt.get("cost") != prompt["price"]:
				state.set_prompt(&"buy_door", label, prompt["price"])
		&"repair":
			if state.prompt.get("kind") != &"repair":
				state.set_prompt(&"repair", BREACH_NAME)
		_:
			state.clear_prompt()
