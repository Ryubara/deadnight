extends Node
## What the muzzle flash really looks like on the screen, measured. For each firearm the real night
## is played from the shoulder camera: the player stands in the open, fires one shot, and for
## every frame drawn from then on the probe measures what the flash did to the picture. It draws
## each frame three times (with the flash, with only its light, with neither) and compares them,
## so the numbers are exactly the flash's own pixels, not a guess from colour.
##
## Prints `FLASH <weapon> <aim|hip> <n> ...` rows (n = frames since the shot was sent) and a
## `FLASHSUM` line per weapon: the frames it was up, its peak size (share of the screen height and
## of the screen area), its peak and mean brightness, and the light's share. Exits with code 1
## when a weapon's flash fails the floors in `FlashFloors` (frames up, size, brightness), so it is
## also a check. Windowed only (the picture is read back from the renderer); run it with
## `gds godot` (docs/godot/no-focus.md), at the frame rate being measured, with Movie Maker when
## the frames are wanted as files:
##
##     gds godot -- --path game --write-movie <abs>/f.png --fixed-fps 60 --quit-after 700 \
##         res://tests/captures/flash_probe.tscn -- --out=<abs folder> [--weapons=pistol,smg]
##         [--aim] [--no-depth] [--shots=1]
## Options after the second `--`: `--out` a folder for the crops, `--weapons` a list (default the
## four hitscan guns and the flare gun), `--aim` shoots with the aim button held (zoomed), and
## `--no-depth` draws the flash without the depth test, to tell how much of it the gun and the
## body hide.

const WEAPONS: Array[StringName] = [&"pistol", &"smg", &"rifle", &"shotgun", &"flare_gun"]
const SETTLE_FRAMES := 40
const FIRE_FRAME := 4
## Frames kept after the shot is sent (the flash lives 3 to 5 of them).
const KEEP_FRAMES := 9
const SEGMENT_FRAMES := SETTLE_FRAMES + FIRE_FRAME + KEEP_FRAMES + 3
const WARMUP_FRAMES := 24
const CHEST := ShotSpot.CHEST

var _night: Night
var _frame := 0
var _ready_to_run := false
var _spot: ShotSpot
var _target := Vector3.ZERO
var _firing := false
var _aim := false
var _no_depth := false
var _out := ""
var _weapons: Array[StringName] = []
var _shots := 1
var _segment := -1
var _sent_at := -1
var _rows: Dictionary = {}
var _failed := false
var _meter := FlashMeter.new()


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--aim":
			_aim = true
		elif argument == "--no-depth":
			_no_depth = true
		elif argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--shots="):
			_shots = int(argument.trim_prefix("--shots="))
		elif argument.begins_with("--weapons="):
			for id in argument.trim_prefix("--weapons=").split(","):
				_weapons.append(StringName(id))
	if _weapons.is_empty():
		_weapons.assign(WEAPONS)
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_night = Night.new()
	add_child(_night)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	# No dead in the picture, so the numbers are the flash's alone.
	tuning.rounds.first_spawn_delay = 600.0
	tuning.rounds.spawn_interval_start = 600.0
	await _night.start(Night.Mode.MANUAL, 5, tuning)
	_night.server.rules.apply(RulesAction.skip_break())
	_night.player().capture_mouse = false
	_night.player().local_input = false
	if _no_depth:
		FlashFloors.draw_without_depth_test()
	RenderingServer.frame_post_draw.connect(_after_draw)
	print("FRAMES ", WARMUP_FRAMES + _weapons.size() * _shots * SEGMENT_FRAMES + 4)
	_ready_to_run = true


func _process(_delta: float) -> void:
	if not _ready_to_run:
		return
	if _frame == 8:
		_spot = ShotSpot.find(_night.player())
		_night.player().teleport(_spot.stand)
		var free := Vector3(-sin(_spot.free_yaw), 0.0, -cos(_spot.free_yaw))
		_target = _spot.stand + Vector3(0.0, CHEST, 0.0) + free * 30.0
		print("SPOT stand=%s free_yaw=%.2f aim=%s" % [_spot.stand, _spot.free_yaw, _aim])
	if _frame < WARMUP_FRAMES:
		_frame += 1
		return
	var index := (_frame - WARMUP_FRAMES) / SEGMENT_FRAMES
	var within := (_frame - WARMUP_FRAMES) % SEGMENT_FRAMES
	_frame += 1
	if index >= _weapons.size() * _shots:
		_finish()
		return
	_segment = index
	if within == 0:
		_begin(_weapons[index / _shots])
	_firing = within == SETTLE_FRAMES + FIRE_FRAME
	if _firing:
		_sent_at = Engine.get_frames_drawn()
	_aim_rig()


func _begin(weapon: StringName) -> void:
	if _segment % _shots == 0:
		_night.server.combat.apply(CombatAction.give_weapon(1, weapon))
		_night.server.combat.apply(CombatAction.equip(1, weapon))
	_sent_at = -1


func _aim_rig() -> void:
	var rig := _night.player().camera_rig
	var lens: Vector3 = rig.aim_transform().origin
	var d := (_target - lens).normalized()
	rig.yaw = atan2(-d.x, -d.z)
	rig.pitch = asin(d.y)
	var command := NightCommand.new()
	command.motion.aim = _aim
	command.motion.yaw = rig.yaw
	command.motion.pitch = rig.pitch
	command.fire = _firing
	command.origin = rig.aim_transform().origin
	command.dir = -rig.aim_transform().basis.z
	_night.link.send(command.to_dict())


func _active_flash() -> MuzzleFlash:
	var found := get_tree().root.find_children("*", "MuzzleFlash", true, false)
	for node in found:
		if (node as MuzzleFlash).is_up():
			return node
	return null


## After the frame is drawn: `FlashMeter` reads it back, draws it again without the flash, and
## compares.
func _after_draw() -> void:
	# Drawing the frame again ends in this call again: only the first counts.
	if FlashMeter.busy or not _ready_to_run or _sent_at < 0 or _segment < 0:
		return
	var since := Engine.get_frames_drawn() - _sent_at
	if since < 0 or since > KEEP_FRAMES:
		return
	var weapon := _weapons[_segment / _shots]
	var flash := _active_flash()
	var row := _meter.measure(get_viewport(), flash)
	row["weapon"] = weapon
	row["n"] = since
	_row(row)
	if _out != "" and flash != null:
		var name := "%s_%s_%d" % [weapon, "aim" if _aim else "hip", since]
		_meter.crop.save_png("%s/%s_crop.png" % [_out, name])
		if since == 1:
			_meter.full.save_png("%s/%s_full.png" % [_out, name])


func _row(row: Dictionary) -> void:
	var weapon: StringName = row["weapon"]
	if not _rows.has(weapon):
		_rows[weapon] = []
	_rows[weapon].append(row)
	print("FLASH %s %s %s" % [weapon, "aim" if _aim else "hip", JSON.stringify(row)])


func _finish() -> void:
	var failures := 0
	for weapon: StringName in _rows:
		var summary := FlashFloors.summarise(_rows[weapon])
		print("FLASHSUM %s %s %s" % [weapon, "aim" if _aim else "hip", JSON.stringify(summary)])
		for problem in FlashFloors.problems(summary):
			failures += 1
			print("FLASHFAIL %s: %s" % [weapon, problem])
	_failed = failures > 0
	get_tree().quit(1 if _failed else 0)
