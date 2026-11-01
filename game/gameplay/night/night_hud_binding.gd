class_name NightHudBinding
extends RefCounted
## Joins the HUD (`game/ui/hud/`) to a night. The HUD reads a `HudState` and nothing else; this
## feeds that state from what a client hears and nothing more: `ClientState.event_received`. The
## rules' events (round, points, party, fuel, purchases) go in as they are; each `frame` carries
## what the rules do not announce, the local player's own readings (health, the held weapon's
## ammunition) and what the hand would do (the prompt at a door or a breach).
##
## The server sends health as `player_damaged` and the prompt in the frame until the rules own
## them (#132, #133); this is the one place that knows, and the HUD does not change when they move.

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
## numbers both sides know from the shared tuning (the fuel tank, the health bar), and not after.
func _init(hud: Hud, state: ClientState, server: NightServer) -> void:
	_hud = hud
	_state = state
	for def in WeaponCatalog.all():
		_weapon_names[def.id] = def.display_name
	var fuel: FuelTuning = server.rules.tuning.fuel
	hud.state.local_player_id = state.player_id
	hud.state.configure(fuel.capacity, fuel.circuit_drain.keys(), fuel.start_circuits)
	hud.state.set_health(server.tuning.max_health, server.tuning.max_health)
	state.event_received.connect(_on_event)


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"frame":
			_on_frame(event)
		&"player_damaged":
			_on_damaged(event)
		_:
			if not NightServer.COMBAT_EVENTS.has(event["type"]):
				_hud.state.apply_event(event)


func _on_frame(frame: Dictionary) -> void:
	var state := _hud.state
	var me := _state.me()
	if me.is_empty():
		return
	var health: float = me["health"]
	if not is_equal_approx(health, state.health):
		state.set_health(health)
	var weapon: StringName = me["weapon"]
	var weapon_name: String = _weapon_names.get(weapon, str(weapon))
	if (
		me["ammo"] != state.ammo_magazine
		or me["reserve"] != state.ammo_reserve
		or weapon_name != state.weapon_name
	):
		state.set_ammo(me["ammo"], me["reserve"], weapon_name)
	var left: int = frame["remaining"]
	if left != state.zombies_left and state.phase == HudState.PHASE_ACTIVE:
		state.zombies_left = left
		state.changed.emit()
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


## The blow as the HUD knows it: the health, and the bearing of the dead one that struck it.
func _on_damaged(event: Dictionary) -> void:
	if event["player_id"] != _state.player_id:
		return
	var hurt := {
		"type": HudState.PLAYER_HURT,
		"player_id": event["player_id"],
		"health": event["health"],
		"direction": _bearing(event.get("from", null)),
	}
	_hud.state.apply_event(hurt)


## Radians clockwise from straight ahead of the local player to `from` (0 when unknown).
func _bearing(from: Variant) -> float:
	if not from is Vector3:
		return 0.0
	var me := _state.me()
	var offset: Vector3 = (from as Vector3) - me.get("pos", Vector3.ZERO)
	var facing: float = me.get("facing", 0.0)
	return wrapf(atan2(offset.x, -offset.z) + facing, -PI, PI)
