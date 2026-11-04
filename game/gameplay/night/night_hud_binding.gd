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
## that joined after the events needs no replay). The scoreboard's counts come the same way, from
## the frame (`_show_stats`).

## What the player is told at each door: the name on the card (the shop ids are the shop's).
const DOOR_NAMES := {
	&"door_concession": "Concession stand",
	&"door_yard": "Generator yard",
	&"door_booth": "Projection booth",
	&"door_back_lot": "Back lot",
	&"door_road": "The ticket plaza",
}
## How high over a zombie's feet its damage number starts: a headshot over the head, any other hit
## at the chest.
const HEAD_HEIGHT := 1.65
const BODY_HEIGHT := 1.1
const BREACH_NAME := "Broken fence"
const FUEL_NAME := "Fuel can"
const CRANE_NAME := "Prize crane"
## The line on the crane's card while it breaks down (the play is refunded), and while it digs.
const CRANE_BROKEN := "OUT OF ORDER: REFUNDED"
const CRANE_DIGGING := "YOUR PRIZE IS COMING"
## What the player is told at each breaker post: the lights it switches.
const CIRCUIT_NAMES := {
	&"screen_lot": "Screen field lights",
	&"concession": "Concession lights",
	&"booth": "Booth lights",
	&"back_lot": "Back lot lights",
}

var _hud: Hud
var _state: ClientState
## The popup lane's setting and sounds, held for as long as the night plays.
var _popup_link: PopupLink
## What the map calls its links and breaches; null on the lot, whose words are the defaults above.
var _words: MapWords
var _weapon_names: Dictionary[StringName, String] = {}
var _fuel: FuelTuning
var _upgrade: UpgradeTuning
var _perks: PerkTuning
var _economy: EconomyTuning
## Units a whole can adds, by shop item: what the card says a can is worth.
var _can_units: Dictionary[StringName, int] = {}


## `hud` is in the tree or about to be; `state` is the client's; `tuning` is read once, for the
## numbers both sides know from the shared tuning (the fuel tank), and not after.
## `looks` is the client's table of looks: the HUD shows each player's portrait from it. `words` is
## the map's own names for its links and breaches (`MapLayout.words`), null for the lot.
func _init(
	hud: Hud,
	state: ClientState,
	tuning: RulesTuning,
	looks: LookRegistry = null,
	words: MapWords = null
) -> void:
	_hud = hud
	_state = state
	_words = words
	if words != null:
		hud.state.link_names = words.link_names
	var ammo_free: Array[StringName] = []
	for def in WeaponCatalog.all():
		_weapon_names[def.id] = def.display_name
		if def.is_melee():
			ammo_free.append(def.id)
	hud.state.weapon_names = _weapon_names
	hud.state.ammo_free = ammo_free
	var fuel: FuelTuning = tuning.fuel
	_fuel = fuel
	_upgrade = tuning.upgrade
	_perks = tuning.perks
	_economy = tuning.economy
	for item in tuning.economy.items:
		if item.kind == ShopItem.Kind.FUEL:
			_can_units[item.id] = int(item.amount)
	hud.state.local_player_id = state.player_id
	hud.state.revive_seconds = tuning.health.revive_seconds
	hud.state.bleed_total = tuning.revive.bleed_out_seconds
	hud.state.self_revive_total = tuning.perks.self_revive_seconds
	hud.state.configure(fuel.capacity, fuel.circuit_drain.keys(), fuel.start_circuits)
	hud.state.special_schedule = HudSpecials.schedule_of(tuning.specials)
	state.event_received.connect(_on_event)
	_popup_link = PopupLink.new(hud.popups)
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
				_hud.state.apply_event(_with_world_point(event))
				PerfProbe.end(&"hud.event", began)


## A hit on a zombie also says where in the world it landed, so its number can stay there while
## the camera moves (`HudCrosshair.projector`): the zombie's place in the last frame, lifted to the
## head or the chest.
func _with_world_point(event: Dictionary) -> Dictionary:
	if event["type"] != &"zombie_damaged":
		return event
	for zombie in _state.zombies:
		if zombie["id"] == event["zombie_id"]:
			var lift := HEAD_HEIGHT if str(event.get("zone", "")) == "head" else BODY_HEIGHT
			var marked := event.duplicate()
			marked["world"] = zombie["position"] + Vector3(0.0, lift, 0.0)
			return marked
	return event


func _on_frame() -> void:
	var state := _hud.state
	_show_stats(state)
	var me := _state.me()
	if me.is_empty():
		return
	state.facing = me["facing"]
	# The weapons' events set the ammunition the moment they are heard; the frame says what the
	# server holds, every tick, so rounds that came by any road show now, and a HUD that joined
	# late (it heard no event) takes the weapon in hand.
	HudLoadout.sync(me, state)
	# The third weapon perk adds a place to the weapon slots; losing it takes the place away.
	var places := WeaponSlots.count()
	if PerkEffects.mask_has_effect(_economy, int(me.get("perks", 0)), ShopItem.Effect.EXTRA_WEAPON):
		places += _perks.extra_weapons
	state.set_slot_count(places)
	# The badges beside the health card are the frame's perk bits, so a purchase adds one and a down
	# that takes the perks takes the badges with them.
	state.set_perks(PerkEffects.mask_tonics(_economy, int(me.get("perks", 0))))
	show_prompt(me["prompt"])


## The scoreboard's numbers, as the server counts them in its frame: every player's kills, downs and
## revives and the ping it last heard, and the night's clock; and the revive's rings (each player's
## bleed-out clock and the progress of the hold on them). One batch, so the HUD redraws once.
func _show_stats(state: HudState) -> void:
	var players: Dictionary = _state.frame.get("players", {})
	state.hold()
	for player_id: int in players:
		var player: Dictionary = players[player_id]
		state.set_player_stats(
			player_id,
			int(player.get("kills", 0)),
			int(player.get("downs", 0)),
			int(player.get("ping", HudState.NO_PING)),
			int(player.get("revives", 0))
		)
		state.set_player_tally(
			player_id, int(player.get("headshots", 0)), int(player.get("rounds", 0))
		)
		state.set_player_revive(
			player_id,
			bool(player.get("dead", false)),
			float(player.get("bleed", 0.0)),
			float(player.get("revive", 0.0)),
			int(player.get("reviver", 0)),
			float(player.get("self_revive", 0.0))
		)
	state.set_night_clock(int(_state.frame.get("clock", 0)))
	state.release()


## Puts what `NightServer.use_target` found on the HUD's prompt card, or clears it.
func show_prompt(prompt: Dictionary) -> void:
	var state := _hud.state
	var kind: StringName = prompt.get("kind", &"")
	match kind:
		&"door":
			var id := StringName(prompt["id"])
			var detail := _words.link_detail(id) if _words != null else ""
			_offer(&"buy_door", door_name(id, _words), prompt["price"], detail)
		&"repair":
			if state.prompt.get("kind") != &"repair":
				var breach := _words.breach_name if _words != null else ""
				state.set_prompt(&"repair", breach if breach != "" else BREACH_NAME)
		&"revive":
			_set_revive_prompt(prompt)
		&"weapon":
			_offer(
				&"buy_weapon",
				_weapon_name(prompt["weapon"]),
				prompt["price"],
				_replaces_line(prompt)
			)
		&"crane":
			_offer(&"buy_crane", CRANE_NAME, prompt["price"], "")
		&"crane_take":
			_offer(
				&"crane_take",
				_weapon_name(WeaponCatalog.catalog_id(prompt["weapon"])),
				0,
				_replaces_line(prompt)
			)
		&"crane_busy":
			_offer(&"crane_busy", CRANE_NAME, 0, _crane_busy_detail(prompt["buyer"]))
		&"ammo":
			var label := "%s rounds" % _weapon_name(prompt["weapon"])
			_offer(
				&"buy_ammo", label, prompt["price"], "%d ROUNDS FOR YOUR RESERVE" % prompt["rounds"]
			)
		&"grenades":
			_offer(
				&"buy_grenades", "Grenades", prompt["price"], "%d FOR YOUR PACK" % prompt["count"]
			)
		&"circuit":
			_set_circuit_prompt(prompt["id"], prompt["on"])
		&"fuel":
			_set_fuel_prompt(prompt)
		_:
			if not MachinePrompts.show(state, prompt, _weapon_names, _upgrade, _perks):
				state.clear_prompt()


## The name of the door `id` on its card and its marker: the map's own, else the lot's, else a
## plain one. `words` is the map's (null on the lot).
static func door_name(id: StringName, words: MapWords = null) -> String:
	var own := words.link_name(id) if words != null else ""
	if own != "":
		return own
	return DOOR_NAMES.get(id, "A way through")


## A downed teammate in reach: whose, and how long they have (the ring itself is `HudRevive`'s).
func _set_revive_prompt(prompt: Dictionary) -> void:
	var member: Dictionary = _hud.state.team.get(int(prompt["id"]), {})
	var label := "Revive %s" % str(member.get("name", "your teammate"))
	var detail := "HOLD TO REVIVE: DEAD IN %d S" % ceili(float(prompt.get("bleed", 0.0)))
	_offer(&"revive", label, 0, detail)


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


## What the card of a busy crane says: that it broke down (to everyone), or, to the buyer, that the
## prize is on its way. Anyone else gets the card's own line, "only the buyer".
func _crane_busy_detail(buyer: int) -> String:
	var stage: int = _state.frame.get("crane", {}).get("stage", CraneState.Stage.SPIN)
	if stage == CraneState.Stage.LEAVING:
		return CRANE_BROKEN
	return CRANE_DIGGING if buyer == _state.player_id else ""


## What a weapon on offer costs the hands: "REPLACES CROWBAR" when the hands are full, else the
## card's own line (an empty detail).
func _replaces_line(prompt: Dictionary) -> String:
	var replaced := StringName(prompt.get("replaces", &""))
	return "REPLACES %s" % _weapon_name(replaced) if replaced != &"" else ""


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
