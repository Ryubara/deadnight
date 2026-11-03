extends Node
## The six breach aprons from the player's camera, for captures (Deadnight #850): the shoulder
## camera of a player standing in the field in line with a breach, turned to the gap, with the
## first dead of that breach just out of the dark. One PNG per breach, round 1's night.
## Not part of the game. Run with a window (not headless):
## `godot --path game res://tests/captures/apron_lamps.tscn --resolution 1280x720
## -- --out=<folder> [--tag=before]`.

## Where the player stands, in metres inside the fence and to the side of the gap, in the order
## tried; the first stand with nothing between the camera and the gap is used.
const STAND_BACKS: Array[float] = [9.0, 11.0, 7.0, 13.0, 15.0, 18.0]
const STAND_SIDES: Array[float] = [0.0, 1.5, -1.5, 3.0, -3.0]
## Physics frames after the first dead of a breach appears, then render frames before the shot.
const WAIT_FRAMES := 14
const SETTLE_FRAMES := 8
## How far above the player the second view of a breach is, in metres.
const HIGH_RISE := 7.0
## The apron view: this far into the field from the gap and this high.
const APRON_BACK := 2.0
const APRON_UP := 14.0
const GIVE_UP_FRAMES := 3000
const ALL_LAYERS := 0x7fffffff

var _night: Night
var _camera: Camera3D
var _out := "user://apron"
var _tag := "shot"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		if arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute(_out)
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.MANUAL)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.near = 0.05
	# A jump from one breach to the next is a cut, not a glide through the physics ticks.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.make_current()
	_act(RulesAction.skip_break())
	var gates := _night.world.spawn_gates()
	for breach in _night.world.barricade_ids():
		var points: Array[Vector3] = []
		for point: Vector3 in gates:
			if gates[point] == breach:
				points.append(point)
		await _shoot(breach, points)
	get_tree().quit()


func _shoot(breach: StringName, points: Array[Vector3]) -> void:
	var before: Array = _night.server.sim.zombies.keys()
	for zombie_id: int in _night.server.rules.zombie_ids():
		_act(RulesAction.zombie_gone(zombie_id))
	_night.server.director.spawn_points = points
	for _i in GIVE_UP_FRAMES:
		if _night.server.sim.zombies.keys().any(func(id: int) -> bool: return not before.has(id)):
			break
		await get_tree().physics_frame
	for _i in WAIT_FRAMES:
		await get_tree().physics_frame
	var rig := _stand(_night.world.barricade(breach))
	if rig.is_empty():
		push_error("no clear stand for %s" % breach)
		return
	var aim := points[0] + Vector3(0.0, 1.0, 0.0)
	_camera.global_position = rig["camera"]
	_camera.look_at(aim, Vector3.UP)
	_camera.make_current()
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	var path := "%s/%s_%s.png" % [_out, _tag, breach]
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path, " from ", _camera.global_position)
	# The same breach from above the fence, to see the whole apron's light and the dead on it.
	_camera.global_position = rig["camera"] + Vector3(0.0, HIGH_RISE, 0.0)
	_camera.look_at(aim, Vector3.UP)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s_%s_high.png" % [_out, _tag, breach])
	# And from straight over the gap, down on the apron's floor.
	var barricade := _night.world.barricade(breach)
	_camera.global_position = (
		barricade.centre() + barricade.inward() * APRON_BACK + Vector3.UP * APRON_UP
	)
	_camera.look_at(points[0], Vector3.UP)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s_%s_apron.png" % [_out, _tag, breach])


## The shoulder camera of the first stand in line with `barricade` that sees its gap, or empty.
func _stand(barricade: Barricade) -> Dictionary:
	var inward := barricade.inward()
	var along := inward.cross(Vector3.UP)
	var yaw := atan2(inward.x, inward.z)
	var space := _camera.get_world_3d().direct_space_state
	var gap := barricade.centre() + Vector3(0.0, 1.2, 0.0) + inward * 0.8
	for back: float in STAND_BACKS:
		for side: float in STAND_SIDES:
			var feet := barricade.centre() + inward * back + along * side
			var rig := CameraProbe.rig(space, feet, yaw)
			var query := PhysicsRayQueryParameters3D.create(rig["camera"], gap, ALL_LAYERS)
			if rig["arm"] >= 2.2 and space.intersect_ray(query).is_empty():
				return rig
	return {}


## A rules action from outside the server's tick, its events delivered as the link would.
func _act(action: Dictionary) -> void:
	_night.state.apply_events(_night.server.rules.apply(action))
