class_name NightHudBinding
extends RefCounted
## Joins the HUD (`game/ui/hud/`) to a night. The HUD reads a `HudState` and nothing else; this
## feeds that state from what a client hears and nothing more: `ClientState.event_received`. The
## rules' events (round, points, party, fuel, purchases, and the player's health: `player_added`,
## `player_hurt`, `player_healed`, `player_downed`) go in as they are, and so do the weapons' events
## the ammo card and the equipment slot read (`HudLoadout.EVENTS`: equipped, shot, reload, rounds
## added). Each `frame` carries what neither announces: which way the local player faces, what the
## hand would do (the prompt at a door, a breach or a breaker post), and the weapons' state, which
## `HudLoadout.sync` reads every tick, so the ammo card is the server's whatever changed it (a HUD
## that joined after the events needs no replay).

## What the player is told at each door: the name on the card (the shop ids are the shop's).
const DOOR_NAMES := {
	&"door_concession": "Concession stand",
	&"door_yard": "Generator yard",
	&"door_booth": "Projection booth",
	&"door_back_lot": "Back lot",
	&"door_road": "The road",
}
const BREACH_NAME := "Broken fence"
const FUEL_NAME := "Fuel can"
const CRANE_NAME := "Prize crane"
## What the player is told at each breaker post: the lights it switches.
const CIRCUIT_NAMES := {
	&"screen_lot": "Screen field lights",
	&"concession": "Concession lights",
	&"booth": "Booth lights",
	&"back_lot": "Back lot lights",
}

var _hud: Hud
var _state: ClientState
var _weapon_names: Dictionary[StringName, String] = {}
var _fuel: FuelTuning
## Units a whole can adds, by shop item: what the card says a can is worth.
var _can_units: Dictionary[StringName, int] = {}


## `hud` is in the tree or about to be; `state` is the client's; `server` is read once, for the
## numbers both sides know from the shared tuning (the fuel tank), and not after.
## `looks` is the client's table of looks: the HUD shows each player's portrait from it.
func _init(hud: Hud, state: ClientState, server: NightServer, looks: LookRegistry = null) -> void:
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
	_fuel = fuel
	for item in server.rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.FUEL:
			_can_units[item.id] = int(item.amount)
	hud.state.local_player_id = state.player_id
	hud.state.configure(fuel.capacity, fuel.circuit_drain.keys(), fuel.start_circuits)
	hud.state.special_schedule = HudSpecials.schedule_of(server.rules.tuning.specials)
	state.event_received.connect(_on_event)
	if looks != null:
		looks.changed.connect(_on_look.bind(looks))


## A look arrived or changed: the HUD hears it as the `player_look` event it knows, for every
## player of the table (the resolved looks, as the bodies wear them).
func _on_look(_player_id: int, looks: LookRegistry) -> void:
	var resolved := looks.resolved()
	for id: int in resolved:
		(
			_hud
			. state
			. apply_event(
				{
					"type": &"player_look",
					"player_id": id,
					"seat": looks.seats[id],
					"look": (resolved[id] as CharacterLook).to_dict(),
				}
			)
		)


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"frame":
			_on_frame()
		_:
			if (
				HudLoadout.EVENTS.has(event["type"])
				or not NightServer.COMBAT_EVENTS.has(event["type"])
			):
				var began := PerfProbe.begin()
				_hud.state.apply_event(event)
				PerfProbe.end(&"hud.event", began)


func _on_frame() -> void:
	var state := _hud.state
	var me := _state.me()
	if me.is_empty():
		return
	state.facing = me["facing"]
	# The weapons' events set the ammunition the moment they are heard; the frame says what the
	# server holds, every tick, so rounds that came by any road show now, and a HUD that joined
	# late (it heard no event) takes the weapon in hand.
	HudLoadout.sync(me, state)
	show_prompt(me["prompt"])


## Puts what `NightServer.use_target` found on the HUD's prompt card, or clears it.
func show_prompt(prompt: Dictionary) -> void:
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
		&"weapon":
			_offer(&"buy_weapon", _weapon_name(prompt["weapon"]), prompt["price"], "")
		&"crane":
			_offer(&"buy_crane", CRANE_NAME, prompt["price"], "")
		&"crane_take":
			_offer(&"crane_take", _weapon_name(WeaponCatalog.catalog_id(prompt["weapon"])), 0, "")
		&"crane_busy":
			var own: bool = prompt["buyer"] == _state.player_id
			_offer(&"crane_busy", CRANE_NAME, 0, "YOUR PRIZE IS COMING" if own else "")
		&"ammo":
			var label := "%s rounds" % _weapon_name(prompt["weapon"])
			_offer(
				&"buy_ammo", label, prompt["price"], "%d ROUNDS FOR YOUR RESERVE" % prompt["rounds"]
			)
		&"circuit":
			_set_circuit_prompt(prompt["id"], prompt["on"])
		&"fuel":
			_set_fuel_prompt(prompt)
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


## The breaker post: which lights, how they stand, and what switching them does to the tank (the
## circuit's draw, as a share of a full tank a minute).
func _set_circuit_prompt(circuit_id: StringName, on: bool) -> void:
	var share := roundi(_fuel.circuit_drain.get(circuit_id, 0.0) * 60.0 / _fuel.capacity * 100.0)
	var label: String = "%s: %s" % [CIRCUIT_NAMES.get(circuit_id, "Lights"), "ON" if on else "OFF"]
	var detail := "COSTS %d%% FUEL A MINUTE"
	if on:
		detail = "SAVES %d%% FUEL A MINUTE"
	var state := _hud.state
	if state.prompt.get("kind") != &"circuit" or state.prompt.get("label") != label:
		state.set_prompt(&"circuit", label, 0, detail % share)


## The fuel can: what it adds to the tank (a whole can, or only the room left) and its price. A full
## tank has nothing to sell: the card says so and shows no price.
func _set_fuel_prompt(prompt: Dictionary) -> void:
	var units := roundi(prompt["units"])
	var detail := "THE TANK IS FULL"
	if units > 0:
		detail = "+%d UNITS OF FUEL" % units
		if units < _can_units.get(prompt["item"], units):
			detail = "FILLS UP: +%d UNITS" % units
	_hud.state.set_prompt(&"fill_fuel", FUEL_NAME, prompt["price"], detail)
