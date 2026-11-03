extends Node
## Every weapon, in the Soldier's hands before and after the re-cut, on the
## player view (Deadnight #787): the shoulder camera and a close side camera on the weapon. The
## re-cut goes through the real combat action; the skin sweeps on in the hand (`RecutStyle`), so
## each "after" waits for the sweep. Not a test. Run with Movie Maker (through `gds godot`):
##
##     godot --path game res://tests/captures/recut_sheet.tscn --write-movie <abs>/recut.png \
##         --fixed-fps 10 --quit-after N -- [--weapons=pistol,smg] [--views=side]
## It prints `FRAMES n` first and `SHOT <weapon> <before|after> <view> <frame>` for the last frame
## of
## each shot, the one to keep.

const SHOT_FRAMES := 6
## Frames after a re-cut before the "after" shots: the ignition (0.7 s at 10 frames a second) plus
## a few.
const IGNITE_FRAMES := 12
const WARMUP_FRAMES := 8
## The side camera's distance from the weapon: this and the weapon's length at the hold's size.
const SIDE_DISTANCE := 0.55

var _night: Night
var _side: Camera3D
var _steps: Array = []
var _frame := 0
var _ready_to_run := false
var _args := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		_args[arg.trim_prefix("--").get_slice("=", 0)] = (
			arg.get_slice("=", 1) if "=" in arg else "1"
		)
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.MANUAL)
	var command := NightCommand.new()
	command.motion.aim = true
	_night.link.send(command.to_dict())
	_side = Camera3D.new()
	_side.fov = 40.0
	add_child(_side)
	var weapons: Array = (
		String(_args["weapons"]).split(",") if _args.has("weapons") else WeaponCatalog.IDS
	)
	var views: Array = String(_args.get("views", "shoulder,side")).split(",")
	for weapon_id in weapons:
		for phase in ["before", "after"]:
			for view in views:
				_steps.append([StringName(weapon_id), phase, view])
	print(
		"FRAMES ", _steps.size() * SHOT_FRAMES + weapons.size() * IGNITE_FRAMES + WARMUP_FRAMES + 4
	)
	_ready_to_run = true


func _process(_delta: float) -> void:
	if not _ready_to_run:
		return
	_aim_side()
	if _frame < WARMUP_FRAMES:
		_frame += 1
		return
	_frame += 1
	# Shots are laid out by hand below: one shot is SHOT_FRAMES, a re-cut adds IGNITE_FRAMES.
	var at := _frame - 1 - WARMUP_FRAMES
	var cursor := 0
	for i in _steps.size():
		var step: Array = _steps[i]
		var length := SHOT_FRAMES + (IGNITE_FRAMES if _recut_before(i) else 0)
		if at < cursor + length:
			_play(step, at - cursor, i)
			return
		cursor += length
	get_tree().quit()


## The side camera: close on the weapon in the hand, looking along the player's right.
func _aim_side() -> void:
	var animation := _night.player().get_node("AnimationTree") as PlayerAnimation
	var weapon := animation.weapon()
	var at := weapon.global_position if weapon != null else _night.player().global_position
	var yaw := Basis(Vector3.UP, _night.player().rotation.y)
	var length := animation.weapon_hold().sized_length() if animation.weapon_hold() != null else 0.4
	_side.global_position = at + yaw * Vector3(SIDE_DISTANCE + length, 0.12 * length / 0.4, 0.1)
	_side.look_at(at)


## Whether step `i` is the first of the "after" shots of its weapon (the re-cut happens before it).
func _recut_before(i: int) -> bool:
	return _steps[i][1] == "after" and (i == 0 or _steps[i - 1][1] != "after")


func _play(step: Array, within: int, index: int) -> void:
	var weapon_id: StringName = step[0]
	var recut_frames := IGNITE_FRAMES if _recut_before(index) else 0
	if within == 0:
		if step[1] == "before" and (index == 0 or _steps[index - 1][0] != weapon_id):
			_night.server.combat.apply(CombatAction.give_weapon(1, weapon_id))
			_night.server.combat.apply(CombatAction.equip(1, weapon_id))
		if _recut_before(index):
			if UpgradeTuning.shipped().allows(weapon_id):
				_night.server.combat.apply(CombatAction.upgrade_weapon(1, weapon_id))
			else:
				# The melee weapons cannot be re-cut by the rules; the skin is put on by hand to show the
				# models wear it too (every weapon model does, whatever the rules allow).
				(_night.player().get_node("AnimationTree") as PlayerAnimation).set_recut(true, true)
		if step[2] == "side":
			_side.make_current()
		else:
			_night.player().camera_rig.camera().make_current()
	if within == recut_frames + SHOT_FRAMES - 1:
		print("SHOT %s %s %s %d" % [weapon_id, step[1], step[2], _frame - 1])
