class_name HumanController
extends RefCounted
## Turns a person's controls into the same `NightCommand` the autopilot sends: the player node
## samples movement and look, this adds the trigger, reload and use (the press, and whether it is
## still down: a held use keeps repairing), and the camera ray.

const ACTION_FIRE := &"fire"
const ACTION_RELOAD := &"reload"
const ACTION_USE := &"interact"
const ACTION_SWAP := &"swap_weapon"

var _was_down := {}


func command(player: Player, player_id: int) -> NightCommand:
	var result := NightCommand.new()
	result.player_id = player_id
	result.motion = player.sample_command()
	if player.controls_enabled():
		result.fire = Input.is_action_pressed(ACTION_FIRE)
		result.reload = _edge(ACTION_RELOAD)
		result.use = _edge(ACTION_USE)
		result.use_held = Input.is_action_pressed(ACTION_USE)
		result.swap = _edge(ACTION_SWAP)
	# The aim ray is the view without the shot shake: a shake moves the picture, never the shot.
	result.origin = player.camera_rig.aim_origin()
	result.dir = player.camera_rig.aim_direction()
	return result


func _edge(action: StringName) -> bool:
	var down := Input.is_action_pressed(action)
	var edge: bool = down and not _was_down.get(action, false)
	_was_down[action] = down
	return edge
