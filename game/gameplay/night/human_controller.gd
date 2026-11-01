class_name HumanController
extends RefCounted
## Turns a person's controls into the same `NightCommand` the autopilot sends: the player node
## samples movement and look, this adds the trigger, reload and use, and the camera ray.

const ACTION_FIRE := &"fire"
const ACTION_RELOAD := &"reload"
const ACTION_USE := &"interact"

var _was_down := {}


func command(player: Player, player_id: int) -> NightCommand:
	var result := NightCommand.new()
	result.player_id = player_id
	result.motion = player.sample_command()
	if player.controls_enabled():
		result.fire = Input.is_action_pressed(ACTION_FIRE)
		result.reload = _edge(ACTION_RELOAD)
		result.use = _edge(ACTION_USE)
	var camera := player.camera_rig.camera()
	result.origin = camera.global_position
	result.dir = -camera.global_transform.basis.z
	return result


func _edge(action: StringName) -> bool:
	var down := Input.is_action_pressed(action)
	var edge: bool = down and not _was_down.get(action, false)
	_was_down[action] = down
	return edge
