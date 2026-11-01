extends Node
## The ammunition card and the equipment slot over a night: shots spend the magazine, a reload
## runs and refills it, a bought rifle takes the hand and the revolver goes to the equipment slot,
## the crowbar uses no ammunition. The combat actions go straight to the server and their events
## reach the client as the link would deliver them. Not part of the game. Run with Movie Maker:
## `godot --path game res://tests/captures/night_hud_weapons.tscn --fixed-fps 10
## --write-movie out.png --quit-after 700`.

const HOLD_TICKS := 60
## Ticks between two shots, past the weapons' fire interval.
const SHOT_GAP := 30

var _night: Night
var _seq := 0


func _ready() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	await _hold(HOLD_TICKS)
	print("revolver, full")
	for _i in 4:
		await _shoot()
	print("four shots fired")
	await _hold(HOLD_TICKS)
	_do(CombatAction.reload_weapon(1))
	await _hold(40)
	print("reloading")
	await _hold(HOLD_TICKS * 2)
	print("reloaded")
	_do(CombatAction.give_weapon(1, &"rifle"))
	await _hold(HOLD_TICKS)
	print("rifle in hand, revolver in the slot")
	await _shoot()
	await _hold(HOLD_TICKS)
	_do(CombatAction.give_weapon(1, &"crowbar"))
	await _hold(HOLD_TICKS)
	print("crowbar in hand")
	_do(CombatAction.equip(1, &"rifle"))
	await _hold(HOLD_TICKS)
	print("rifle again, crowbar in the slot")
	get_tree().quit()


## One combat action to the server; its events go to the client.
func _do(action: Dictionary) -> void:
	_night.state.apply_events(_night.server.combat.apply(action))


func _shoot() -> void:
	var eye := _night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	_seq += 1
	var now := _night.server.combat.now
	_do(CombatAction.fire(1, _seq, eye, Vector3.FORWARD, eye, now))
	await _hold(SHOT_GAP)


func _hold(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame
