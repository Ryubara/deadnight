class_name HudFixture
extends RefCounted
## Shared helpers for the HUD suites: a real night's rules, a HUD fed from them, and a few
## hand-made events for the things the rules do not send.

const TUNING := "res://gameplay/rules/default_tuning.tres"
const KILLING := 99999.0
const STEP := 0.1

var rules: GameRules
var hud: Hud


## A HUD inside `host` (any Control the test owns) over a fresh night with `players` players, named
## Ruby, Moe, Dee, Cal, Ned, Ivy, Sal and Pat, the first being the local one. Not started. The
## portraits and the weapon silhouettes build no 3D world unless `portraits` (a suite about them
## says so): the picture does not change a layout.
static func make(host: Control, players := 1, seed_value := 1958, portraits := false) -> HudFixture:
	HudPortrait.live = portraits
	WeaponSilhouettes.live = portraits
	var fixture := HudFixture.new()
	var tuning := (load(TUNING) as RulesTuning).duplicate(true)
	fixture.rules = GameRules.new(tuning, seed_value)
	fixture.hud = (load(Hud.SCENE) as PackedScene).instantiate()
	host.add_child(fixture.hud)
	var state := fixture.hud.state
	state.special_schedule = HudSpecials.schedule_of(tuning.specials)
	state.configure(
		tuning.fuel.capacity, tuning.fuel.circuit_drain.keys(), tuning.fuel.start_circuits
	)
	var names := ["Ruby", "Moe", "Dee", "Cal", "Ned", "Ivy", "Sal", "Pat"]
	for i in players:
		state.set_player_name(i + 1, names[i])
		fixture.act(RulesAction.add_player(i + 1))
	return fixture


## Applies an action to the rules and feeds the events it caused to the HUD, as a client would
## receive them from the server.
func act(action: Dictionary) -> Array[Dictionary]:
	var events := rules.apply(action)
	hud.feed(events)
	return events


## Starts the night and plays through the intro so round 1 is active.
func into_round_one() -> void:
	act(RulesAction.start())
	act(RulesAction.skip_break())


## Ticks the rules until `count` zombies have asked to spawn; returns their ids.
func spawn(count: int) -> Array[int]:
	var ids: Array[int] = []
	for _i in 600:
		for event in act(RulesAction.tick(STEP)):
			if event["type"] == &"zombie_spawn_requested":
				ids.append(int(event["zombie_id"]))
		if ids.size() >= count:
			break
	return ids


## Moves every time-driven part on by `seconds` (a fixed step, no real clock).
func advance(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(STEP, left)
		for part in [
			hud.gains,
			hud.crosshair,
			hud.damage,
			hud.banner,
			hud.events_feed,
			hud.notices,
			hud.fuel,
			hud.challenge
		]:
			part.advance(step)
		hud.state.tick(step)
		left -= step


## The longest content the game allows, all on screen at once: names at the name limit, a
## three-digit round, the largest points and ammo, a long weapon, equipment and prompt, a busy
## party.
## The fixture must have four players (`make(host, 4)`) and round one running.
func fill_worst_case() -> void:
	var state := hud.state
	var names := [
		"Maximiliana Rosewood",
		"Bartholomew Okonkwo",
		"Wolfgang Amadeus Zed",
		"Persephone Q-Laneway",
		"Guinevere Abernathy",
		"Thaddeus Fontaine-Wu",
		"Ottoline Brandybuck",
		"Cornelius Vandermeer"
	]
	for i in names.size():
		state.set_player_name(i + 1, names[i])
	state.apply_event({"type": &"round_started", "round": 123, "zombie_count": 999})
	state.apply_event({"type": &"points_changed", "player_id": 1, "total": 99999999, "delta": 0})
	state.set_health(100.0, 100.0)
	state.set_ammo(999, 9999, "Double-Barrel Coach Gun")
	state.set_equipment("Molotov Cocktail", 12)
	state.apply_event({"type": &"grenade_count_changed", "player_id": 1, "count": 5})
	state.set_area(
		"The Concession Stand", "Light the booth to open the back lot and the lot beyond"
	)
	state.set_prompt(
		&"buy_weapon",
		"Double-Barrel Coach Gun",
		99999,
		"Two barrels, one very loud night in the back lot"
	)
	act(RulesAction.set_downed(2, true))
	act(RulesAction.set_downed(3, true))
	hud.banner.show_banner("ROUND 123 SURVIVED", "CATCH YOUR BREATH", HudBanner.Rank.ROUND)
	for text in [
		"MAXIMILIANA ROSEWOOD OPENED THE PROJECTION BOOTH",
		"LIGHTS OFF: THE CONCESSION STAND",
		"BARTHOLOMEW OKONKWO IS DOWN",
	]:
		hud.events_feed.push(text)
	hud.notices.push("PERSEPHONE Q-LANEWAY CONNECTED")
	for amount in [100, 60, 130, 60]:
		hud.gains.add_gain(&"headshot_kill", amount)
	hud.fuel.peek()
	advance(HudTuning.current().banner_in + 0.1)


## The rules' `player_hurt` for the local player: a blow from `bearing`, `health` left of 100.
static func hurt(bearing: float, health: float) -> Dictionary:
	return {
		"type": HudState.PLAYER_HURT,
		"player_id": 1,
		"damage": 10.0,
		"health": health,
		"max_health": 100.0,
		"bearing": bearing,
		"source_id": 1,
	}
