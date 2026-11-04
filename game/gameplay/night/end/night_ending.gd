class_name NightEnding
extends RefCounted
## What a night does the moment it is over (docs/design/end-of-night.md), kept out of `Night`: the
## player's body stops taking controls and the camera leaves the player's own lens for the end
## sequence (`EndCamera`). The night itself stands still and the server counts the intermission.


## The night ended (`game_over`, or a frame of a night that already was): controls off, and the
## pull-back and the angles of the map start from the lens the player was looking through.
static func begin(night: Night) -> void:
	var body := night.player()
	if night.mode == Night.Mode.HUMAN and body != null:
		body.set_controls_enabled(false)
	var lens := night.get_viewport().get_camera_3d()
	if night.end_camera != null or lens == null:
		return
	var focus := body.global_position if body != null else night.state.position()
	var camera := EndCamera.new()
	camera.name = "EndCamera"
	night.add_child(camera)
	var first := maxi(night.state.player_id - 1, 0)
	camera.begin(lens, focus, night.world.map_info.end_shots, null, first)
	# The dead's animation is thinned by their distance from the lens: the one the picture has now.
	night.view.horde.throttle.camera = camera
	night.end_camera = camera


## A frame of a game server's night that is already over (the seat was taken in its intermission: no
## `game_over` was heard) says so with its clock: the night is over for this client too.
static func noticed(night: Night, frame: Dictionary) -> void:
	if int(frame.get("over_left", -1)) >= 0 and not night.state.over:
		night.state.over = true
		night.state.round_reached = int(frame.get("round", 0))
		night.night_over.emit(night.state.round_reached)
