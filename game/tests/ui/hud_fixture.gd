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
## Ruby, Moe, Dee and Cal, the first being the local one. Not started.
static func make(host: Control, players := 1, seed_value := 1958) -> HudFixture:
	var fixture := HudFixture.new()
	var tuning := (load(TUNING) as RulesTuning).duplicate(true)
	fixture.rules = GameRules.new(tuning, seed_value)
	fixture.hud = (load(Hud.SCENE) as PackedScene).instantiate()
	host.add_child(fixture.hud)
	var state := fixture.hud.state
	state.configure(
		tuning.fuel.capacity, tuning.fuel.circuit_drain.keys(), tuning.fuel.start_circuits
	)
	var names := ["Ruby", "Moe", "Dee", "Cal"]
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
			hud.gains, hud.crosshair, hud.damage, hud.banner, hud.events_feed, hud.notices
		]:
			part.advance(step)
		hud.state.tick(step)
		left -= step


static func hurt(direction: float, health: float) -> Dictionary:
	return {
		"type": HudState.PLAYER_HURT,
		"player_id": 1,
		"health": health,
		"direction": direction,
	}
