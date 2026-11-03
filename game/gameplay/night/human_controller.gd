class_name HumanController
extends RefCounted
## Turns a person's controls into the same `NightCommand` the autopilot sends: the player node
## samples movement and look, this adds the trigger, reload and use (the press, and whether it is
## still down: a held use keeps repairing), and the camera ray.

const ACTION_FIRE := &"fire"
const ACTION_RELOAD := &"reload"
const ACTION_USE := &"interact"
const ACTION_SWAP := &"swap_weapon"
const ACTION_PING := &"ping"
## The quick melee: a blow with whatever is in hand (#411).
const ACTION_MELEE := &"quick_melee"

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
		result.fire = player.trigger_held() or (assist != null and assist.wants_fire())
		# The body hears the trigger too (the hip-fire zoom and the pose follow it).
		result.motion.fire = result.fire
		result.reload = _edge(ACTION_RELOAD)
		result.use = _edge(ACTION_USE)
		result.use_held = Input.is_action_pressed(ACTION_USE)
		result.swap = _edge(ACTION_SWAP)
		result.slot = _slot_edge()
		result.motion.melee = _edge(ACTION_MELEE)
	# The aim ray is the view without the shot shake: a shake moves the picture, never the shot.
	result.origin = player.camera_rig.aim_transform().origin
	result.dir = (-player.camera_rig.aim_transform().basis.z)
	return result


## Whether the ping key went down this tick (the controls must be on).
func ping_pressed(player: Player) -> bool:
	return player.controls_enabled() and _edge(ACTION_PING)


## The slot whose key went down this tick (the highest when two did), or `WeaponSlots.NONE`. Every
## key's edge is read each tick, so a key held through a swap does not fire when it is let go.
func _slot_edge() -> int:
	var picked := WeaponSlots.NONE
	for action in WeaponSlots.ACTIONS:
		if _edge(action):
			picked = WeaponSlots.slot_of(action)
	return picked


func _edge(action: StringName) -> bool:
	var down := Input.is_action_pressed(action)
	var edge: bool = down and not _was_down.get(action, false)
	_was_down[action] = down
	return edge
