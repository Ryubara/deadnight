extends Node
## Scripted capture of weapon models that have no catalogue weapon yet (#797: the service pistol,
## the ray gun, the freeze gun) in the Soldier's hands, beside the catalogue weapon of their class,
## from the side, the player's shoulder camera, behind, the left and close on the hand, idle and
## aiming. Not a test. Each model is held through the one builder (`PlayerAnimation` ->
## `HeldWeapon`) with a hold made here from its class's file and the model's own numbers (`MODELS`):
## the size its hold file will give it, its muzzle, butt and support. Run with Movie Maker; one view
## lasts SHOT_FRAMES and prints `SHOT <model> <pose> <view> <frame>` for its last frame, the one to
## keep:
##
##     gds godot -- --path game --write-movie <abs>/hold.png --fixed-fps 10 --quit-after N \
##         res://tests/captures/model_hold_sheet.tscn [-- --only=ray_gun]
## A phone's view is a frame scaled to 390 px tall (the movie keeps the project's window size).

const SHOT_FRAMES := 8
## model: {class, the catalogue weapon whose hold file is copied (and filmed first as the
## reference), scene, model_scale, model_length, real_length, size_factor, muzzle, butt, support}.
## Points are the model's own units in Godot's axes (the glb's: muzzle along -X, up +Y).
const MODELS := {
	"service_pistol":
	{
		"reference": &"pistol",
		"scene": "res://assets/weapons/service_pistol/service_pistol.glb",
		"model_scale": 1.95,
		"size_factor": 1.5,
		"real_length": 0.216,
		"model_length": 0.25,
		"muzzle": Vector3(-0.17, 0.045, 0.0),
		"butt": Vector3(0.074, 0.0, 0.0),
		"support": Vector3.ZERO,
	},
	"ray_gun":
	{
		"reference": &"pistol",
		"scene": "res://assets/weapons/ray_gun/ray_gun.glb",
		"model_scale": 2.275,
		"size_factor": 1.75,
		"real_length": 0.28,
		"model_length": 0.278,
		"muzzle": Vector3(-0.2, 0.05, 0.0),
		"butt": Vector3(0.078, 0.0, 0.0),
		"support": Vector3.ZERO,
	},
	"freeze_gun":
	{
		"reference": &"smg",
		"scene": "res://assets/weapons/freeze_gun/freeze_gun.glb",
		"model_scale": 1.3,
		"size_factor": 1.0,
		"real_length": 0.9,
		"model_length": 0.908,
		"muzzle": Vector3(-0.6, 0.05, 0.0),
		"butt": Vector3(0.3, 0.0, 0.0),
		"support": Vector3(-0.295, -0.045, 0.0),
	},
}
const POSES := ["idle", "aim"]
const VIEWS := ["side", "shoulder", "rear", "left", "hand"]
## Where the close camera stands from the weapon, in the Soldier's frame (x right, z back), metres.
const HAND_BESIDE := Vector3(0.75, 0.15, 0.05)

var _player: Player
var _animation: PlayerAnimation
var _side: Camera3D
var _rear: Camera3D
var _left: Camera3D
var _hand: Camera3D
var _steps: Array = []
var _frame := 0


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_player.teleport(Vector3(0.0, 0.05, 6.0))
	_side = _camera()
	_rear = _camera()
	_left = _camera()
	_hand = _camera()
	_hand.fov = 30.0
	var only := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")
	for model: String in MODELS:
		if only != "" and model != only:
			continue
		var reference: StringName = MODELS[model].reference
		for subject in [String(reference), model]:
			for pose in POSES:
				for view in VIEWS:
					_steps.append([subject, pose, view])
	print("FRAMES ", _steps.size() * SHOT_FRAMES + 12)


func _camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	return camera


## The hold a model will have: its class's catalogue hold with the model's own numbers.
static func hold_of(model: String) -> WeaponHold:
	var spec: Dictionary = MODELS[model]
	var hold := WeaponHoldMap.hold_for(spec.reference).duplicate() as WeaponHold
	for key in [
		"scene",
		"model_scale",
		"size_factor",
		"real_length",
		"model_length",
		"muzzle",
		"butt",
		"support"
	]:
		hold.set(key, spec[key])
	return hold


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
	_follow()
	if within == 0:
		_begin(step, index)
	if within == SHOT_FRAMES - 1:
		print("SHOT %s %s %s %d" % [step[0], step[1], step[2], _frame - 1])
		if step[2] == "side":
			_report(step)


## The side, rear and left cameras keep their place beside the Soldier.
func _follow() -> void:
	var centre := _player.global_position + Vector3(0.0, 1.0, 0.0)
	var yaw := Basis(Vector3.UP, _player.rotation.y)
	_side.global_position = centre + yaw * Vector3(2.4, 0.15, -0.3)
	_side.look_at(centre + yaw * Vector3(0.0, 0.1, -0.3))
	_rear.global_position = centre + yaw * Vector3(1.6, 0.45, 1.9)
	_rear.look_at(centre + yaw * Vector3(0.0, 0.1, -0.4))
	_left.global_position = centre + yaw * Vector3(-2.2, 0.3, -1.2)
	_left.look_at(centre + yaw * Vector3(0.0, 0.1, -0.3))
	var weapon := _animation.weapon()
	if weapon != null:
		_hand.global_position = weapon.global_position + yaw * HAND_BESIDE
		_hand.look_at(weapon.global_position)


func _begin(step: Array, index: int) -> void:
	var subject: String = step[0]
	var pose: String = step[1]
	var first_view: bool = (
		index == 0 or _steps[index - 1][0] != subject or _steps[index - 1][1] != pose
	)
	if first_view:
		Input.action_release("aim")
		_player.teleport(Vector3(0.0, 0.05, 6.0))
		_player.camera_rig.yaw = 0.0
		_player.camera_rig.pitch = 0.0
		if index == 0 or _steps[index - 1][0] != subject:
			_equip(subject)
		if pose == "aim":
			Input.action_press("aim")
	match step[2]:
		"side":
			_side.make_current()
		"rear":
			_rear.make_current()
		"left":
			_left.make_current()
		"hand":
			_hand.make_current()
		"shoulder":
			_player.camera_rig.get_node("Camera3D").make_current()


## A catalogue weapon through `equip`; a model through the same hold path with its own hold.
func _equip(subject: String) -> void:
	if not MODELS.has(subject):
		_animation.equip(StringName(subject))
		return
	var hold := hold_of(subject)
	_animation._set_class(WeaponHoldMap.class_of(MODELS[subject].reference), hold)
	_animation.cancel_reload()
	_animation.play_action(&"Equip")


func _report(step: Array) -> void:
	var weapon := _animation.weapon()
	if weapon == null:
		print("HOLD %s %s no weapon" % [step[0], step[1]])
		return
	var hand := _animation.weapon_mount().global_position
	var grip := _animation.weapon_grip()
	print(
		(
			"HOLD %s %s grip_to_hand=%.3f visible=%s grip=%s"
			% [
				step[0],
				step[1],
				weapon.global_position.distance_to(hand),
				weapon.visible,
				grip.resource_path if grip != null else "none"
			]
		)
	)
