extends Node
## Scripted capture of weapon models that have a hold file but no catalogue entry yet (the model
## batches #795-#797, before the build issues wire them in): each in the Soldier's hands through
## the night's own builder (`PlayerAnimation` with the model's `holds/<model>.tres`, so
## `HeldWeapon`, its grip file and the arms' IK), at the hip and aimed, from the side (another
## player's view), the player's shoulder camera and a teammate's distance. Not a test. Run with
## Movie Maker; each view lasts SHOT_FRAMES and prints `SHOT <model> <pose> <view> <frame>` for its
## last frame, the one to keep:
##
##     gds godot -- --path game --write-movie <abs>/batch.png --fixed-fps 10 --quit-after N \
##         res://tests/captures/model_batch_sheet.tscn -- --models=ppsh,mp5,m4a1
## `--models=` names the hold files (`smg` films the Tommy gun beside them for scale). For a phone,
## add `--resolution 844x390`.
## Also prints, for each aimed pose, `FIT <model> stock_to_shoulder=<m> left_to_grip=<m>` and one
## `CONTACT` line per hand part that misses the grip test's limits (`HandContact.failures`: 2 mm
## in, 5 mm off), so the hold's numbers are checked before the model is a catalogue weapon.

const SHOT_FRAMES := 10
const POSES := ["idle", "aim"]
const VIEWS := ["side", "shoulder", "teammate"]
const HOLDS_DIR := "res://gameplay/player/holds/"

var _player: Player
var _animation: PlayerAnimation
var _skeleton: Skeleton3D
var _contact: HandContact
var _side: Camera3D
var _far: Camera3D
var _steps: Array = []
var _frame := 0
var _want := ""


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.skeleton_updated.connect(_on_updated)
	_player.teleport(Vector3(0.0, 0.05, 6.0))
	_side = Camera3D.new()
	_side.fov = 32.0
	add_child(_side)
	_far = Camera3D.new()
	_far.fov = 60.0
	add_child(_far)
	var models := PackedStringArray(["ppsh", "mp5", "m4a1"])
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--models="):
			models = argument.trim_prefix("--models=").split(",")
	for model in models:
		for pose in POSES:
			for view in VIEWS:
				_steps.append([model, pose, view])
	print("FRAMES ", _steps.size() * SHOT_FRAMES + 12)


func _process(_delta: float) -> void:
	if _frame == 2:
		_contact = HandContact.new(_skeleton)
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
	_follow()
	if within == SHOT_FRAMES - 1:
		print("SHOT %s %s %s %d" % [step[0], step[1], step[2], _frame - 1])
		if step[2] == "side":
			_want = "%s %s" % [step[0], step[1]]


## The side camera stands off the Soldier's right; the teammate's 8 m off his front-right, the
## distance the phone silhouettes are drawn for (42 px a metre).
func _follow() -> void:
	var centre := _player.global_position + Vector3(0.0, 1.05, 0.0)
	var yaw := Basis(Vector3.UP, _player.rotation.y)
	_side.global_position = centre + yaw * Vector3(2.4, 0.1, -0.3)
	_side.look_at(centre + yaw * Vector3(0.0, 0.0, -0.3))
	_far.global_position = centre + yaw * Vector3(5.6, 0.4, -5.7)
	_far.look_at(centre)


func _begin(step: Array, index: int) -> void:
	var model: String = step[0]
	var pose: String = step[1]
	if index == 0 or _steps[index - 1][0] != model or _steps[index - 1][1] != pose:
		Input.action_release("aim")
		_player.teleport(Vector3(0.0, 0.05, 6.0))
		_player.camera_rig.yaw = 0.0
		_player.camera_rig.pitch = 0.0
		if index == 0 or _steps[index - 1][0] != model:
			var hold := load(HOLDS_DIR + model + ".tres") as WeaponHold
			# The step `equip` takes for a catalogue weapon (`_set_class`) with this hold in place of
			# the catalogue's, so the model, its grip file and the arms' pose come from `HeldWeapon`;
			# no Equip clip, which would keep the arms for its length.
			_animation._set_class(hold.weapon_class, hold)
		if pose == "aim":
			Input.action_press("aim")
	match step[2]:
		"side":
			_side.make_current()
		"teammate":
			_far.make_current()
		"shoulder":
			_player.camera_rig.get_node("Camera3D").make_current()


## Measured at the end of the skeleton's update, as the grip test does.
func _on_updated() -> void:
	if _want == "" or _contact == null:
		return
	var tag := _want
	_want = ""
	var weapon := _animation.weapon()
	var hold := _animation.weapon_hold()
	var grip := _animation.weapon_grip()
	if weapon == null or hold == null or grip == null:
		print("FIT %s no weapon, hold or grip" % tag)
		return
	var shoulder := (
		_skeleton.global_transform
		* _skeleton.get_bone_global_pose(_skeleton.find_bone("UpperArm.R"))
	)
	var left := (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone("Index1.L"))
	)
	print(
		(
			"FIT %s stock_to_shoulder=%.3f left_to_grip=%.3f right_weight=%.2f left_weight=%.2f"
			% [
				tag,
				weapon.to_global(hold.butt).distance_to(shoulder.origin),
				left.origin.distance_to(_animation.hands().solved_left().origin),
				_animation.fingers().right_weight,
				_animation.fingers().left_weight,
			]
		)
	)
	_contact.set_weapon(weapon)
	var measured := {"R": _contact.measure("R")}
	var fails := HandContact.failures(tag + " R", measured.R, grip.right_contacts)
	if grip.has_left and _animation.fingers().left_weight >= 0.99:
		measured.L = _contact.measure("L")
		fails.append_array(HandContact.failures(tag + " L", measured.L, grip.left_contacts))
	for line in fails:
		print("CONTACT ", line)
	print("CONTACTS %s %d off" % [tag, fails.size()])
	# Where each part that misses is, in the model's own space (Godot axes, model units), to find
	# the piece of the model it meets.
	for side: String in measured:
		var contacts := grip.right_contacts if side == "R" else grip.left_contacts
		var single := {}
		for part: String in measured[side]:
			single = {part: measured[side][part]}
			if not HandContact.failures("", single, contacts).is_empty():
				var at: Vector3 = weapon.to_local(measured[side][part].point)
				print("AT %s %s %s (%.3f, %.3f, %.3f)" % [tag, side, part, at.x, at.y, at.z])
