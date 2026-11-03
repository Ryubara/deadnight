extends Node
## What blood looks like when a zombie is hit, from the player's own camera: the real night (the
## combat server answers every shot, the view draws it), one zombie held in front of the player with
## a wall behind it, shot with each gun on the body and on the head, and a melee blow. Not a test.
## Run with Movie Maker at a fixed rate; it prints `CASE <name> <first frame> <last frame>` for the
## frames of each case (the shot is sent on its sixth frame), and `MARKS <name> <count>` for the
## marks alive at its end:
##
##     gds godot -- --path game --write-movie <abs>/blood.png --fixed-fps 30 --quit-after N \
##         res://tests/captures/blood_sheet.tscn [-- --only=rifle_head]
## The frame names say what is what; the caller assembles them.

const CASES: Array[Dictionary] = [
	{"name": "pistol_body", "weapon": &"pistol", "aim": 1.1, "away": 2.4},
	{"name": "crowbar_melee", "weapon": &"crowbar", "aim": 1.1, "away": 1.6},
	{"name": "smg_body", "weapon": &"smg", "aim": 1.1, "away": 2.4},
	{"name": "shotgun_body", "weapon": &"shotgun", "aim": 1.1, "away": 2.4},
	{"name": "rifle_body", "weapon": &"rifle", "aim": 1.1, "away": 2.4},
	{"name": "pistol_head", "weapon": &"pistol", "aim": 1.62, "away": 2.4},
	{"name": "rifle_head", "weapon": &"rifle", "aim": 1.62, "away": 2.4},
]
const SEGMENT_FRAMES := 40
const WARMUP_FRAMES := 18
const FIRE_FRAME := 6

var _night: Night
var _frame := 0
var _ready_to_run := false
var _only := ""
## `--blood=off` hides the blood, which is how a night looked before it (the small puffs stay).
var _blood_off := false
## Frames of one case; a browser run asks for more with `?frames=N`.
var _segment := SEGMENT_FRAMES
var _spot: ShotSpot
var _zombie_spot := Vector3.ZERO
var _zombie_id := -1
var _target := Vector3.ZERO
var _firing := false
var _cases: Array[Dictionary] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
		if arg == "--blood=off":
			_blood_off = true
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("location.search"))
		for pair in query.trim_prefix("?").split("&", false):
			var parts := pair.split("=", true, 1)
			if parts[0] == "only" and parts.size() > 1:
				_only = parts[1]
			elif parts[0] == "blood" and parts.size() > 1:
				_blood_off = parts[1] == "off"
			elif parts[0] == "frames" and parts.size() > 1:
				_segment = int(parts[1])
	for entry in CASES:
		if _only == "" or entry["name"] == _only:
			_cases.append(entry)
	_night = Night.new()
	add_child(_night)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.first_spawn_delay = 0.3
	tuning.rounds.spawn_interval_start = 0.3
	tuning.rounds.count_base = 16.0
	await _night.start(Night.Mode.MANUAL, 5, tuning)
	_night.server.rules.apply(RulesAction.skip_break())
	_night.ticked.connect(_hold_zombie)
	_night.view.effects.blood.visible = not _blood_off
	print("FRAMES ", WARMUP_FRAMES + _cases.size() * _segment + 4)
	_ready_to_run = true


func _process(_delta: float) -> void:
	if not _ready_to_run:
		return
	if _frame == 8:
		_survey()
	if _frame < WARMUP_FRAMES:
		_frame += 1
		return
	var index := (_frame - WARMUP_FRAMES) / _segment
	var within := (_frame - WARMUP_FRAMES) % _segment
	_frame += 1
	if index >= _cases.size():
		_say("window.__blood = {done: true};")
		get_tree().quit()
		return
	var entry := _cases[index]
	if within == 0:
		_begin(entry)
	_firing = within == FIRE_FRAME
	_aim_rig()
	if within == 0:
		print("CASE %s %d" % [entry["name"], Engine.get_frames_drawn()])
		_say("window.__blood = {case: '%s', index: %d};" % [entry["name"], index])
	if within == _segment - 1:
		print(
			(
				"MARKS %s %d splashes=%d"
				% [
					entry["name"],
					_night.view.effects.blood.marks_alive(),
					_night.view.effects.blood.splashes_alive()
				]
			)
		)


## Looks over the lot for a place to stand and puts the player there; the zombie goes between the
## player and the wall.
func _survey() -> void:
	var player := _night.player()
	_spot = ShotSpot.find(player)
	player.teleport(_spot.stand)
	print(
		(
			"SURVEY stand=%s wall_yaw=%.2f (%.1f m)"
			% [_spot.stand, _spot.wall_yaw, _spot.wall_distance]
		)
	)


func _begin(entry: Dictionary) -> void:
	_night.view.effects.blood.stop_all()
	_night.server.combat.apply(CombatAction.give_weapon(1, entry["weapon"]))
	_night.server.combat.apply(CombatAction.equip(1, entry["weapon"]))
	var wall := Vector3(-sin(_spot.wall_yaw), 0.0, -cos(_spot.wall_yaw))
	_zombie_spot = _spot.stand + wall * float(entry["away"])
	_target = _zombie_spot + Vector3(0.0, float(entry["aim"]), 0.0)


func _aim_rig() -> void:
	var rig := _night.player().camera_rig
	var lens: Vector3 = rig.aim_transform().origin
	var d := (_target - lens).normalized()
	rig.yaw = atan2(-d.x, -d.z)
	rig.pitch = asin(d.y)
	var command := NightCommand.new()
	command.motion.aim = true
	command.motion.yaw = rig.yaw
	command.motion.pitch = rig.pitch
	command.fire = _firing
	command.origin = rig.aim_transform().origin
	command.dir = -rig.aim_transform().basis.z
	_night.link.send(command.to_dict())


## The zombie stands where the gun points at it, one only, facing the player.
func _hold_zombie() -> void:
	var chosen: ZombieBody = null
	for body: ZombieBody in _night.server.sim.zombies.values():
		if body.is_alive() and (body.id == _zombie_id or chosen == null):
			chosen = body
	if chosen == null:
		return
	_zombie_id = chosen.id
	chosen.position = Vector3(_zombie_spot.x, chosen.position.y, _zombie_spot.z)
	var toward := _spot.stand - _zombie_spot
	chosen.yaw = atan2(-toward.x, -toward.z)
	chosen.velocity = Vector3.ZERO
	if chosen.mode == ZombieBody.Mode.ATTACK:
		chosen.enter(ZombieBody.Mode.CHASE)


## Tells the page which case is on (a browser run: `tools/web_smoke/blood_capture.py` films it).
func _say(script: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(script)
