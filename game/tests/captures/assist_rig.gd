class_name AssistRig
extends RefCounted
## The stage of the touch aim assist's captures and its browser run (#286): one zombie held 7 m
## from the player, a little to the left of where the view looks, every other zombie sent behind the
## player. The thumb then drags the view toward it and stops short, and `lateral` says how far the
## crosshair is from its chest. Not part of the game.

const DISTANCE := 7.0
## How far to the left of the crosshair's ray the zombie stands, in degrees.
const OFFSET_DEGREES := 9.0
## The thumb drags until the crosshair is this near the chest (metres) and no nearer: beside the
## zombie, not on it (its body is about 0.26 m wide).
const STOP_METRES := 0.55
## The share of the remaining turn one drag event covers.
const STEP_SHARE := 0.4
const CHEST := 1.2
const BEHIND := 30.0
## How the view is turned in search of open ground: the most steps, and the angle of each.
const TURNS := 24
const TURN_STEP := deg_to_rad(15.0)

var night: Night
var zombie: ZombieBody

var _spot := Vector3.ZERO
var _facing := 0.0


func _init(p_night: Night) -> void:
	night = p_night


## Waits for the first zombie of the night to come out and holds it where `place` says. False when
## none came within `frames`.
func start(tree: SceneTree, frames := 900) -> bool:
	night.state.apply_events(night.server.rules.apply(RulesAction.skip_break()))
	for _i in frames:
		await tree.process_frame
		if not night.server.sim.zombies.is_empty():
			zombie = night.server.sim.zombies.values()[0]
			await _face_open_ground(tree)
			place()
			night.ticked.connect(pin)
			# The zombie is drawn from the client's list, which has it once it is out of the ground.
			for _j in frames:
				if not night.state.zombies.is_empty():
					return true
				await tree.process_frame
			return false
	return false


## Turns the view, a step at a time, until nothing stands between the lens and where the zombie
## will be: a truck against the camera would hide it, and the assist would rightly ignore it.
func _face_open_ground(tree: SceneTree) -> void:
	var probe := WorldProbe.new(night.get_world_3d().direct_space_state)
	var rig := night.player().camera_rig
	for _i in TURNS:
		await tree.process_frame
		await tree.process_frame
		place()
		var view := rig.aim_transform()
		var chest := _spot + Vector3.UP * CHEST
		if probe.distance(view.origin, chest) < 0.0:
			return
		rig.yaw = wrapf(rig.yaw + TURN_STEP, -PI, PI)


## The zombie `DISTANCE` off, `OFFSET_DEGREES` to the left of where the view looks now, facing the
## player.
func place() -> void:
	var view := night.player().camera_rig.aim_transform()
	var level := Vector3(-view.basis.z.x, 0.0, -view.basis.z.z).normalized()
	var turned := level.rotated(Vector3.UP, deg_to_rad(OFFSET_DEGREES))
	_spot = view.origin + turned * DISTANCE
	_spot.y = night.player().global_position.y
	# A zombie's yaw is the way it walks: toward the player.
	_facing = atan2(-turned.x, -turned.z)


## Every tick: the first zombie stays where it was put, the others stand well behind the player.
func pin() -> void:
	var first := true
	for body: ZombieBody in night.server.sim.zombies.values():
		body.velocity = Vector3.ZERO
		if first:
			body.position = _spot
			body.yaw = _facing
			first = false
		else:
			body.position = night.player().global_position + Vector3(0.0, 0.0, BEHIND)


## How far the crosshair's ray passes from the zombie's chest, in metres.
func lateral() -> float:
	var view := night.player().camera_rig.aim_transform()
	var to_chest := _spot + Vector3.UP * CHEST - view.origin
	return to_chest.cross(-view.basis.z).length()


## The turn that would put the crosshair on the chest, in radians: yaw (left is positive) and pitch
## (up is positive), as the camera rig counts them.
func turn_to_chest() -> Vector2:
	var view := night.player().camera_rig.aim_transform()
	var wanted := AimAssist.view_angles((_spot + Vector3.UP * CHEST - view.origin).normalized())
	var now := AimAssist.view_angles(-view.basis.z)
	return Vector2(angle_difference(now.x, wanted.x), wanted.y - now.y)


## The thumb's next drag event, in canvas units of a canvas `height` units tall: a share of the
## turn that is left, so it slows as it nears. A finger that drags right turns the view right.
func thumb_step(height: float) -> Vector2:
	var units_per_radian := height / TouchLook.tuning.radians_per_height
	var turn := turn_to_chest() * STEP_SHARE
	return Vector2(-turn.x, -turn.y) * units_per_radian
