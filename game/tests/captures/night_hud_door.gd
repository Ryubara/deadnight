extends Node
## The HUD over a night the player walks (the human's camera), for captures: the player stands at
## the concession's door without the points, then with them, then buys it, then at a fence breach.
## Not part of the game. Run with Movie Maker:
## `godot --path game res://tests/captures/night_hud_door.tscn --fixed-fps 10
## --write-movie out.png --quit-after 400`.

const DOOR := &"door_concession"
## Metres in front of a slab where the player stands.
const AT_DOOR := Vector3(0.0, 0.1, -2.0)
const BREACH_BACK := Vector3(0.0, 0.1, 1.5)
const HOLD_FRAMES := 60

var _night: Night


func _ready() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN)
	_act(RulesAction.skip_break())
	await _hold(HOLD_FRAMES)
	_night.player().teleport(_night.world.door_points(DOOR)[0] + AT_DOOR)
	print("poor at the door")
	await _hold(HOLD_FRAMES)
	_act(RulesAction.grant_points(1, 400))
	print("able to pay")
	await _hold(HOLD_FRAMES)
	var command := NightCommand.new()
	command.use = true
	_night.link.send(command.to_dict())
	print("bought")
	await _hold(HOLD_FRAMES)
	var breach := _night.world.repair_points()[0]
	_night.player().teleport(breach + BREACH_BACK)
	print("at the breach")
	await _hold(HOLD_FRAMES)
	get_tree().quit()


## A rules action from outside the server's tick, its events delivered as the link would.
func _act(action: Dictionary) -> void:
	_night.state.apply_events(_night.server.rules.apply(action))


func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
