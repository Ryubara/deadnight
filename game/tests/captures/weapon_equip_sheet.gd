extends Node
## Every weapon of the catalogue taken in hand through the real combat action, seen on the player
## view from the shoulder camera and from the side (Deadnight, weapon id to model). Not a test. Run
## with Movie Maker; one view lasts SHOT_FRAMES frames and prints `SHOT <weapon> <view> <frame>` for
## its last frame, the one to keep:
##
##     godot --path game --write-movie <abs>/equip.png --fixed-fps 10 --quit-after N \
##         res://tests/captures/weapon_equip_sheet.tscn
## Also prints `HOLD <weapon> <class>` for each weapon. The player holds the aim button.

const SHOT_FRAMES := 8
const WARMUP_FRAMES := 8
const VIEWS := ["shoulder", "side"]

var _night: Night
var _side: Camera3D
var _steps: Array = []
var _frame := 0
var _ready_to_run := false


func _ready() -> void:
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.MANUAL)
	# The aim button held for the whole sheet (the server keeps the last command).
	var command := NightCommand.new()
	command.motion.aim = true
	_night.link.send(command.to_dict())
	_side = Camera3D.new()
	_side.fov = 40.0
	add_child(_side)
	for weapon_id in WeaponCatalog.IDS:
		for view in VIEWS:
			_steps.append([weapon_id, view])
	print("FRAMES ", _steps.size() * SHOT_FRAMES + WARMUP_FRAMES + 4)
	_ready_to_run = true


func _process(_delta: float) -> void:
	if not _ready_to_run:
		return
	var player := _night.player()
	var centre := player.global_position + Vector3(0.0, 1.0, 0.0)
	var yaw := Basis(Vector3.UP, player.rotation.y)
	_side.global_position = centre + yaw * Vector3(2.6, 0.2, 0.0)
	_side.look_at(centre)
	if _frame < WARMUP_FRAMES:
		_frame += 1
		return
	var index := (_frame - WARMUP_FRAMES) / SHOT_FRAMES
	var within := (_frame - WARMUP_FRAMES) % SHOT_FRAMES
	_frame += 1
	if index >= _steps.size():
		get_tree().quit()
		return
	var step: Array = _steps[index]
	if within == 0:
		_begin(step, index)
	if within == SHOT_FRAMES - 1:
		print("SHOT %s %s %d" % [step[0], step[1], _frame - 1])


func _begin(step: Array, index: int) -> void:
	var weapon_id: StringName = step[0]
	if index == 0 or _steps[index - 1][0] != weapon_id:
		_night.server.combat.apply(CombatAction.give_weapon(1, weapon_id))
		_night.server.combat.apply(CombatAction.equip(1, weapon_id))
		print("HOLD %s %s" % [weapon_id, WeaponHoldMap.class_of(weapon_id)])
	if step[1] == "side":
		_side.make_current()
	else:
		_night.player().camera_rig.camera().make_current()
