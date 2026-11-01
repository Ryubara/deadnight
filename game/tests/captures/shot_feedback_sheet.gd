extends Node
## What a shot looks like, for each hitscan gun: the muzzle flash from the shoulder camera and from
## a close camera at the muzzle, the impact on a wall, and the impact on a zombie, each from the
## shoulder camera and from a close camera. The night is the real one (the combat server answers
## every shot, the view draws it); only the zombie is posed, in front of the gun. Not a test. Run
## with Movie Maker; prints `FRAME <weapon> <view> <frame>` for the frames to keep (the flash is up
## on `FLASH` and the puff on `PUFF`):
##
##     godot --path game --write-movie <abs>/shots.png --fixed-fps 10 --quit-after N \
##         res://tests/captures/shot_feedback_sheet.tscn
## `tools/shot_sheet.py`-style assembly is left to the caller; the frame names say what is what.

const WEAPONS: Array[StringName] = [&"pistol", &"smg", &"rifle", &"shotgun"]
const VIEWS := ["flash", "flash_close", "wall", "wall_close", "zombie", "zombie_close"]
const SEGMENT_FRAMES := 10
const WARMUP_FRAMES := 18
## The frame of a segment on which the shot is sent, and the ones to keep.
const FIRE_FRAME := 4
const FLASH := 5
const PUFF := 6
const ZOMBIE_DISTANCE := 4.0
const CHEST := 1.1

var _night: Night
var _close: Camera3D
var _frame := 0
var _ready_to_run := false
var _stand := Vector3.ZERO
var _wall_distance := 0.0
var _free_yaw := 0.0
var _wall_yaw := 0.0
var _wall_hit := Vector3.ZERO
var _zombie_spot := Vector3.ZERO
var _zombie_id := -1
var _target := Vector3.ZERO
var _firing := false
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	_night = Night.new()
	add_child(_night)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.first_spawn_delay = 0.3
	tuning.rounds.spawn_interval_start = 0.3
	tuning.rounds.count_base = 4.0
	await _night.start(Night.Mode.MANUAL, 5, tuning)
	_night.server.rules.apply(RulesAction.skip_break())
	_close = Camera3D.new()
	_close.fov = 45.0
	add_child(_close)
	_night.ticked.connect(_hold_zombie)
	_night.state.event_received.connect(_log)
	print("FRAMES ", WARMUP_FRAMES + WEAPONS.size() * VIEWS.size() * SEGMENT_FRAMES + 4)
	_ready_to_run = true


func _process(_delta: float) -> void:
	if not _ready_to_run:
		return
	if _frame == 8:
		_survey()
	if _frame < WARMUP_FRAMES:
		_frame += 1
		return
	var index := (_frame - WARMUP_FRAMES) / SEGMENT_FRAMES
	var within := (_frame - WARMUP_FRAMES) % SEGMENT_FRAMES
	_frame += 1
	if index >= WEAPONS.size() * VIEWS.size():
		get_tree().quit()
		return
	var weapon: StringName = WEAPONS[index / VIEWS.size()]
	var view: String = VIEWS[index % VIEWS.size()]
	if within == 0:
		_begin(weapon, view, index)
	if within == FIRE_FRAME:
		_firing = true
	elif within == FIRE_FRAME + 1:
		_firing = false
	_aim_rig()
	if within == FLASH or within == PUFF:
		print(
			(
				"FRAME %s %s %d %s"
				% [weapon, view, Engine.get_frames_drawn(), "FLASH" if within == FLASH else "PUFF"]
			)
		)


## Looks over the lot for a place to stand with room round it for the shoulder camera, a wall a few
## metres off (the wall impact) and a long free line (the flash and the zombie), and puts the player
## there.
func _survey() -> void:
	var player := _night.player()
	var space := player.get_world_3d().direct_space_state
	var found := false
	var origin := player.global_position
	for ring in range(0, 40, 3):
		for step in maxi(1, ring * 2):
			var angle := TAU * float(step) / float(maxi(1, ring * 2))
			var spot := Vector3(sin(angle), 0.0, cos(angle)) * float(ring) + origin
			if _try_spot(space, spot):
				found = true
				break
		if found:
			break
	player.teleport(_stand)
	print(
		(
			"SURVEY stand=%s free_yaw=%.2f wall_yaw=%.2f (%.1f m)"
			% [_stand, _free_yaw, _wall_yaw, _wall_distance]
		)
	)


func _try_spot(space: PhysicsDirectSpaceState3D, spot: Vector3) -> bool:
	var down := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 2.0, spot + Vector3.DOWN * 3.0, 1)
	)
	if down.is_empty() or absf(down["normal"].y) < 0.9 or absf(down["position"].y) > 0.15:
		return false
	var feet: Vector3 = down["position"]
	# Under the open sky: not inside a building or under the screen.
	if not (
		space
		. intersect_ray(
			PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.5, feet + Vector3.UP * 12.0, 1)
		)
		. is_empty()
	):
		return false
	var from := feet + Vector3(0.0, CHEST, 0.0)
	var free_yaw := -1.0
	var wall_yaw := -1.0
	var wall_hit := Vector3.ZERO
	var wall_distance := 0.0
	for step in 24:
		var yaw := TAU * float(step) / 24.0
		var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, from + dir * 30.0, 1)
		)
		var distance := 30.0 if hit.is_empty() else from.distance_to(hit["position"])
		# Room for the camera behind: the opposite ray is free for 3 m.
		if distance >= 12.0 and free_yaw < 0.0:
			free_yaw = yaw
		if (
			not hit.is_empty()
			and distance >= 4.0
			and distance <= 6.0
			and absf(hit["normal"].y) < 0.2
		):
			wall_yaw = yaw
			wall_hit = hit["position"]
			wall_distance = distance
	if free_yaw < 0.0 or wall_yaw < 0.0:
		return false
	for step in 8:
		var back := Vector3(sin(TAU * step / 8.0), 0.0, cos(TAU * step / 8.0))
		if (
			(
				space
				. intersect_ray(PhysicsRayQueryParameters3D.create(from, from + back * 3.2, 1))
				. size()
			)
			> 0
		):
			return false
	_stand = feet
	_free_yaw = free_yaw
	_wall_yaw = wall_yaw
	_wall_hit = wall_hit
	_wall_distance = wall_distance
	var free_dir := Vector3(-sin(_free_yaw), 0.0, -cos(_free_yaw))
	_zombie_spot = feet + free_dir * ZOMBIE_DISTANCE
	return true


func _begin(weapon: StringName, view: String, index: int) -> void:
	if index % VIEWS.size() == 0:
		_night.server.combat.apply(CombatAction.give_weapon(1, weapon))
		_night.server.combat.apply(CombatAction.equip(1, weapon))
	var rig := _night.player().camera_rig
	var from := _night.player().global_position + Vector3(0.0, CHEST, 0.0)
	if view.begins_with("flash"):
		_target = from + Vector3(-sin(_free_yaw), 0.0, -cos(_free_yaw)) * 20.0
	elif view.begins_with("wall"):
		_target = _wall_hit
	else:
		_target = _zombie_spot + Vector3(0.0, CHEST, 0.0)
	var d := (_target - from).normalized()
	_yaw = atan2(-d.x, -d.z)
	_pitch = asin(d.y)
	if view.ends_with("_close"):
		_close_camera(view, from, d)
		_close.make_current()
	else:
		rig.camera().make_current()


## A camera that looks at the muzzle (flash) or at the point the shot lands (wall, zombie).
func _close_camera(view: String, from: Vector3, dir: Vector3) -> void:
	var right := dir.cross(Vector3.UP).normalized()
	if view == "flash_close":
		var animation := _night.player().get_node("AnimationTree") as PlayerAnimation
		var marker: Node3D = (
			animation.muzzle_point() if animation.has_method("muzzle_point") else null
		)
		var muzzle := marker.global_position if marker != null else from + dir * 0.6 + right * 0.3
		_close.look_at_from_position(
			muzzle + right * 0.9 - dir * 0.3 + Vector3(0, 0.15, 0), muzzle + dir * 0.25
		)
	else:
		_close.look_at_from_position(
			_target - dir * 1.4 + right * 0.55 + Vector3(0, 0.25, 0), _target
		)


func _aim_rig() -> void:
	var rig := _night.player().camera_rig
	# The crosshair is on the target from the lens, which sits over the shoulder: aim from there.
	var lens: Vector3 = (
		rig.call("aim_origin") if rig.has_method("aim_origin") else rig.camera().global_position
	)
	var d := (_target - lens).normalized()
	_yaw = atan2(-d.x, -d.z)
	_pitch = asin(d.y)
	rig.yaw = _yaw
	rig.pitch = _pitch
	var command := NightCommand.new()
	command.motion.aim = true
	command.motion.yaw = rig.yaw
	command.motion.pitch = rig.pitch
	command.fire = _firing
	if rig.has_method("aim_direction"):
		command.origin = rig.call("aim_origin")
		command.dir = rig.call("aim_direction")
	else:
		var camera := rig.camera()
		command.origin = camera.global_position
		command.dir = -camera.global_transform.basis.z
	_night.link.send(command.to_dict())


## The zombie stands where the gun points at it, one only, facing the player.
func _hold_zombie() -> void:
	var zombies: Array = _night.server.sim.zombies.values()
	var chosen: ZombieBody = null
	for body: ZombieBody in zombies:
		if body.is_alive() and (body.id == _zombie_id or chosen == null):
			chosen = body
	if chosen == null:
		return
	_zombie_id = chosen.id
	chosen.position = Vector3(_zombie_spot.x, chosen.position.y, _zombie_spot.z)
	chosen.yaw = 0.0
	chosen.velocity = Vector3.ZERO
	if chosen.mode == ZombieBody.Mode.ATTACK:
		chosen.enter(ZombieBody.Mode.CHASE)


func _log(event: Dictionary) -> void:
	if event["type"] == &"shot_fired":
		print(
			(
				"SHOT frame=%d muzzle=%s ends=%s flesh=%s"
				% [_frame, event["muzzle"], event["ends"], event.get("flesh")]
			)
		)
	elif event["type"] == &"fire_rejected":
		print("REJECT frame=%d %s" % [_frame, event["reason"]])
