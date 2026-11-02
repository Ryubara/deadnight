class_name HumanController
extends RefCounted
## Turns a person's controls into the same `NightCommand` the autopilot sends: the player node
## samples movement and look, this adds the trigger, reload and use (the press, and whether it is
## still down: a held use keeps repairing), and the camera ray.

const ACTION_FIRE := &"fire"
const ACTION_RELOAD := &"reload"
const ACTION_USE := &"interact"
const ACTION_SWAP := &"swap_weapon"

## The touch player's aim help (`TouchAimAssist`); null for a night that has none.
var assist: TouchAimAssist

var _was_down := {}


func command(player: Player, player_id: int) -> NightCommand:
	var result := NightCommand.new()
	result.player_id = player_id
	if assist != null:
		assist.prepare(player, player.get_physics_process_delta_time())
	result.motion = player.sample_command()
	if player.controls_enabled():
		result.fire = (
			Input.is_action_pressed(ACTION_FIRE) or (assist != null and assist.wants_fire())
		)
		# The body hears the trigger too (the hip-fire zoom and the pose follow it).
		result.motion.fire = result.fire
		result.reload = _edge(ACTION_RELOAD)
		result.use = _edge(ACTION_USE)
		result.use_held = Input.is_action_pressed(ACTION_USE)
		result.swap = _edge(ACTION_SWAP)
	# The aim ray is the view without the shot shake: a shake moves the picture, never the shot.
	result.origin = player.camera_rig.aim_transform().origin
	result.dir = (-player.camera_rig.aim_transform().basis.z)
	return result


func _edge(action: StringName) -> bool:
	var down := Input.is_action_pressed(action)
	var edge: bool = down and not _was_down.get(action, false)
	_was_down[action] = down
	return edge
