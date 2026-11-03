extends Node
## Scripted capture of weapon models in the Soldier's hands before they are in the catalogue (#796),
## with the hands measured (`model_hold_sheet.tscn`, #797, films the one-handed and #797's guns):
## a model batch films its models held by the night's own builder (`HeldWeapon`, through
## `PlayerAnimation`) from a hold made here (`HOLDS`, the plan's numbers), beside catalogue weapons
## equipped the normal way, from the side (third person), the player's shoulder camera, behind, and
## close on each hand, at the hip, aimed and running; then `parts` with each moving node moved off
## its rest, and `recut` in the re-cut skin (#787). Not a test. Run with Movie Maker; each view
## lasts SHOT_FRAMES and prints `SHOT <weapon> <pose> <view> <frame>` for its last frame, the one
## to keep:
##
##     gds godot -- --path game --write-movie <abs>/held.png --fixed-fps 10 --quit-after N \
##         res://tests/captures/model_hands_sheet.tscn [-- --only=m249,smg] [--views=side,shoulder]
## What a landscape phone shows: scale a frame to 390 px tall (the vertical field of view is fixed,
## so an object is as many pixels tall as on the phone; the phone shows more width).
## The hold files themselves are the build issue's (#793): once a model has one, film it with
## `weapon_hold_sheet.tscn`.

const SHOT_FRAMES := 8
## The shoulder camera's pitch for every shot, radians (negative looks down).
const SHOULDER_PITCH := -0.3
## The player scene's scale of the Soldier (docs/design/weapon-hold.md).
const SOLDIER_SCALE := 0.8
## A model with no hold file yet: its hold, from docs/research/weapon-models.md (model units,
## Godot's axes: x along the gun, y up). `grip_offset` puts the butt at the shoulder: the butt's
## distance behind the grip in the game and 5 cm, as the Tommy gun's is.
const HOLDS := {
	"m249":
	{
		"class": &"Rifle",
		"scene": "res://assets/weapons/m249/m249.glb",
		"model_scale": 1.3,
		"real_length": 1.04,
		"model_length": 0.94,
		"grip_offset": Vector3(0.0, -0.09, -0.37),
		"support": Vector3(-0.30, -0.025, 0.0),
		"muzzle": Vector3(-0.62, 0.05, 0.0),
		"butt": Vector3(0.31, 0.0, 0.0),
		"stance_turn_deg": 30.0,
	},
	"fifty_cal":
	{
		"class": &"Rifle",
		"scene": "res://assets/weapons/fifty_cal/fifty_cal.glb",
		"model_scale": 1.21,
		"size_factor": 0.93,
		"real_length": 1.45,
		"model_length": 1.40,
		"grip_offset": Vector3(0.0, -0.09, -0.385),
		"support": Vector3(-0.28, -0.01, 0.0),
		"muzzle": Vector3(-1.05, 0.05, 0.0),
		"butt": Vector3(0.345, 0.0, 0.0),
		"stance_turn_deg": 30.0,
	},
	"pump_870":
	{
		"class": &"Shotgun",
		"scene": "res://assets/weapons/pump_870/pump_870.glb",
		"model_scale": 1.3,
		"real_length": 0.98,
		"model_length": 0.93,
		"grip_offset": Vector3(0.0, -0.09, -0.365),
		"support": Vector3(-0.32, -0.02, 0.0),
		"muzzle": Vector3(-0.62, 0.05, 0.0),
		"butt": Vector3(0.30, 0.0, 0.0),
		"stance_turn_deg": 30.0,
	},
}
## What to film, in order: catalogue ids are equipped as the night does, the others take `HOLDS`.
const WEAPONS: Array[String] = ["smg", "m249", "fifty_cal", "shotgun", "pump_870"]
## pose: the views filmed in it.
const SHOTS := {
	"idle": ["side", "shoulder"],
	"aim": ["side", "shoulder", "rear", "right", "front"],
	"run": ["side"],
	"parts": ["side"],
	"recut": ["side", "right"],
}
## Each moving node's way off its rest for `parts` (model units, Godot's axes; degrees about z).
const MOVES := {
	"Cover": {"turn_z": 70.0},
	"Box": {"slide": Vector3(0.0, -0.12, 0.0)},
	"Belt": {"slide": Vector3(0.0, -0.12, 0.0)},
	"Bolt": {"slide": Vector3(0.10, 0.0, 0.0)},
	"Magazine": {"slide": Vector3(0.015, -0.13, 0.0)},
	"Pump": {"slide": Vector3(0.045, 0.0, 0.0)},
}

var _player: Player
var _animation: PlayerAnimation
var _skeleton: Skeleton3D
var _side: Camera3D
var _rear: Camera3D
var _close: Camera3D
var _steps: Array = []
var _frame := 0
var _contact: HandContact
## The shot whose hands the next skeleton update measures ("" for none).
var _measure_tag := ""


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_player.teleport(Vector3(0.0, 0.05, 6.0))
	_side = _camera(36.0)
	_rear = _camera(40.0)
	_close = _camera(26.0)
	var only: PackedStringArray = []
	var views: PackedStringArray = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=").split(",")
		elif argument.begins_with("--views="):
			views = argument.trim_prefix("--views=").split(",")
	for weapon in WEAPONS:
		if not only.is_empty() and weapon not in only:
			continue
		for pose: String in SHOTS:
			for view: String in SHOTS[pose]:
				if views.is_empty() or view in views:
					_steps.append([weapon, pose, view])
	print("FRAMES ", _steps.size() * SHOT_FRAMES + 12)


func _camera(fov: float) -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = fov
	camera.near = 0.02
	add_child(camera)
	return camera


func _process(_delta: float) -> void:
	if _frame < 6:
		_frame += 1
		return
	var index := (_frame - 6) / SHOT_FRAMES
	var within := (_frame - 6) % SHOT_FRAMES
	_frame += 1
	if index >= _steps.size():
		get_tree().quit()
		return
	var step: Array = _steps[index]
	if within == 0:
		_begin(step, index)
	if step[1] == "parts":
		_move_parts()
	_follow(step[2])
	if within == SHOT_FRAMES - 1:
		print("SHOT %s %s %s %d" % [step[0], step[1], step[2], _frame - 1])
		if step[2] == "side":
			_report(step)


## The hold of a model that has no hold file yet.
static func make_hold(spec: Dictionary) -> WeaponHold:
	var hold := WeaponHold.new()
	hold.weapon_class = spec["class"]
	hold.scene = spec.scene
	hold.model_scale = spec.model_scale
	hold.size_factor = spec.get("size_factor", 1.0)
	hold.real_length = spec.real_length
	hold.model_length = spec.model_length
	hold.shouldered = true
	hold.grip_offset = spec.grip_offset
	hold.support = spec.support
	hold.muzzle = spec.muzzle
	hold.butt = spec.butt
	hold.stance_turn_deg = spec.stance_turn_deg
	return hold


func _hold(weapon: String) -> void:
	if HOLDS.has(weapon):
		var spec: Dictionary = HOLDS[weapon]
		# The night's own path for a weapon and its hold (`equip` does the same for a catalogue id).
		_animation._set_class(spec["class"], make_hold(spec))
		_animation._weapon_visible(true)
	else:
		_animation.equip(StringName(weapon))


func _move_parts() -> void:
	var weapon := _animation.weapon()
	if weapon == null:
		return
	for node_name: String in MOVES:
		var part := weapon.find_child(node_name, true, false) as Node3D
		if part == null:
			continue
		if not part.has_meta("rest"):
			part.set_meta("rest", part.transform)
		var rest: Transform3D = part.get_meta("rest")
		var move: Dictionary = MOVES[node_name]
		var turned := rest.basis * Basis(Vector3.BACK, deg_to_rad(move.get("turn_z", 0.0)))
		part.transform = Transform3D(turned, rest.origin + move.get("slide", Vector3.ZERO))


## Every moved part back at its rest.
func _rest_parts() -> void:
	var weapon := _animation.weapon()
	if weapon == null:
		return
	for node_name: String in MOVES:
		var part := weapon.find_child(node_name, true, false) as Node3D
		if part != null and part.has_meta("rest"):
			part.transform = part.get_meta("rest")


func _bone(name: String) -> Vector3:
	return (
		_skeleton.global_transform
		* _skeleton.get_bone_global_pose(_skeleton.find_bone(name)).origin
	)


## The side and rear cameras keep their place beside the Soldier; the close one looks at the right
## hand from his right or at the left hand on the fore-end from his left.
func _follow(view: String) -> void:
	var centre := _player.global_position + Vector3(0.0, 1.0, 0.0)
	var yaw := Basis(Vector3.UP, _player.rotation.y)
	_side.global_position = centre + yaw * Vector3(3.0, 0.15, -0.3)
	_side.look_at(centre + yaw * Vector3(0.0, 0.0, -0.3))
	_rear.global_position = centre + yaw * Vector3(1.9, 0.5, 2.3)
	_rear.look_at(centre + yaw * Vector3(0.0, 0.0, -0.4))
	var weapon := _animation.weapon()
	if weapon == null:
		return
	var right_hand := _bone("Index1.R")
	var target := right_hand.lerp(weapon.global_position, 0.5)
	var offset := Vector3(1.35, 0.18, -0.2)
	if view == "front":
		target = weapon.to_global(_animation.weapon_hold().support)
		offset = Vector3(-1.3, 0.25, -0.55)
	_close.global_position = target + yaw * offset
	_close.look_at(target)


func _begin(step: Array, index: int) -> void:
	var weapon: String = step[0]
	var pose: String = step[1]
	var first_view: bool = (
		index == 0 or _steps[index - 1][0] != weapon or _steps[index - 1][1] != pose
	)
	if first_view:
		for action in ["move_forward", "aim"]:
			Input.action_release(action)
		_player.teleport(Vector3(0.0, 0.05, 6.0))
		_player.camera_rig.yaw = 0.0
		# Looking a little down, as a player does at the zombies on the ground: the shoulder camera
		# then shows the weapon past the head (at a level view the head fills it).
		_player.camera_rig.pitch = SHOULDER_PITCH
		if index == 0 or _steps[index - 1][0] != weapon or pose == "idle":
			_hold(weapon)
		_rest_parts()
		_animation.set_recut(pose == "recut")
		match pose:
			"run":
				Input.action_press("move_forward")
			"aim", "parts", "recut":
				Input.action_press("aim")
	match step[2]:
		"side":
			_side.make_current()
		"rear":
			_rear.make_current()
		"right", "front":
			_close.make_current()
		"shoulder":
			_player.camera_rig.get_node("Camera3D").make_current()


## On each side shot, the hands are measured against the weapon as the grip test does
## (`HandContact`, on the skin as drawn, after the skeleton's update): `HANDS` prints the parts more
## than 2 mm in or the contacts more than 5 mm off, or `ok`.
func _report(step: Array) -> void:
	var weapon := _animation.weapon()
	if weapon == null:
		print("HELD %s %s none" % [step[0], step[1]])
		return
	print(
		(
			"HELD %s %s visible=%s length=%.2f m"
			% [
				step[0],
				step[1],
				weapon.visible,
				_animation.weapon_hold().world_length(SOLDIER_SCALE)
			]
		)
	)
	_measure_tag = "%s %s" % [step[0], step[1]]


func _on_skeleton_updated() -> void:
	if _measure_tag == "":
		return
	var tag := _measure_tag
	_measure_tag = ""
	var grip := _animation.weapon_grip()
	if grip == null:
		print("HANDS %s no grip" % tag)
		return
	if _contact == null:
		_contact = HandContact.new(_skeleton)
	_contact.set_weapon(_animation.weapon())
	var fails: Array[String] = []
	fails.append_array(HandContact.failures(tag + " R", _contact.measure("R"), grip.right_contacts))
	var left_on := grip.has_left and _animation.fingers().left_weight >= 0.99
	if left_on:
		fails.append_array(
			HandContact.failures(tag + " L", _contact.measure("L"), grip.left_contacts)
		)
	# How far the left hand bone stopped from where the arms' IK sent it (0: it reached).
	var left_gap := _bone("Index1.L").distance_to(_animation._held.hands.solved_left().origin)
	print(
		(
			"HANDS %s right=%.2f left=%.2f left_gap=%.3f m %s"
			% [
				tag,
				_animation.fingers().right_weight,
				_animation.fingers().left_weight,
				left_gap,
				"ok" if fails.is_empty() else str(fails)
			]
		)
	)
