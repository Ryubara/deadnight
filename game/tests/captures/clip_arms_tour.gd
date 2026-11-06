extends Node
## The arms in the clips the night plays (#939), on the player's own body in the test room: each
## weapon is equipped, held, aimed, fired (from the aim, as hip fire is), struck with, sprinted with
## and reloaded; then a board is repaired, a grenade cooked and thrown, the body goes down, crawls,
## gets up and kneels at a revive. The player is driven by commands and the animation's own calls
## (no device input), so the same run gives the same poses on any build. Not part of the game.
##
## Measure (headless): every few ticks the pose the skeleton draws (read at `skeleton_updated`,
## after the hand IK and the finger poses have run) is kept, and after the run each is measured
## by `ClipFit` (a forearm or hand inside the trunk, the head, the legs or the other arm deeper
## than its tolerance). One `NIGHT` line per weapon, beat and check with a fault, a `NIGHT_SUMMARY`:
##
##     godot --headless --path game --fixed-fps 60 res://tests/captures/clip_arms_tour.tscn \
##         -- --measure [--look=10] [--weapons=dual_pistols,rifle] [--write=<file.json>] [--trace]
##         [--every=1] [--reload-only]
##
## `--trace` adds one `TRACE` line per kept pose with a fault: the tick, the check, how deep, the
## group and its place in the skeleton's frame. `--every=N` keeps a pose every N ticks, and
## `--reload-only` plays each weapon's equip and reload and nothing else (a few seconds a weapon).
##
## Film (windowed, off the person's desktop): the player's shoulder camera, or `--view=side` a close
## view from his right, `--view=front` from ahead and to his right, `--view=left` from his left:
##
##     gds godot -- --path game res://tests/captures/clip_arms_tour.tscn --write-movie <abs>/f.png \
##         --fixed-fps 30 -- [--look=10] [--weapons=dual_pistols] [--view=side]
##
## `--shots=<dir>` (windowed) saves one still of each beat at the tick that shows its arms
## (`SHOT_AT`; `--reload-shot=<tick>` for the reload's) as
## `<dir>/<look>_<view>_<weapon>_<beat><tick>.png`, with no movie.
##
## Prints one `BEAT <weapon> <beat> frame <n>` line as each beat starts (frames at the fixed fps).

const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 17.0)
## Ticks between two kept poses while measuring.
const SAMPLE_EVERY := 3
## The beats, in ticks (60 a second).
const EQUIP_TICKS := 40
const HOLD_TICKS := 30
const AIM_TICKS := 40
const FIRE_TICKS := 60
const SHOT_EVERY := 9
const SETTLE_TICKS := 30
const STRIKE_TICKS := 45
const SPRINT_TICKS := 60
const RELOAD_SECONDS := 1.6
const RELOAD_TICKS := 110
const DOWN_TICKS := 150
const CRAWL_TICKS := 100
const REVIVE_TICKS := 100
## The cameras beside the player, in his frame (x right, y up, z back), and the point they look at.
const VIEWS := {
	"side": Vector3(2.2, 1.0, -0.2),
	"front": Vector3(1.0, 1.1, -2.4),
	"left": Vector3(-1.9, 0.9, -0.8),
}
const LOOK := Vector3(0.0, 0.85, 0.0)
## The tick of each beat a still is taken at (`--shots`): the deepest pose the measure found on
## main.
const SHOT_AT := {
	"equip": 21,
	"fire": 6,
	"strike": 21,
	"sprint": 39,
	"reload": 39,
	"repair": 60,
	"downed": 140,
	"crawl": 60,
	"revive": 60,
}

var _player: Player
var _animation: PlayerAnimation
var _skeleton: Skeleton3D
var _camera: Camera3D
var _view := ""
var _measure := false
var _look := 10
var _write := ""
var _trace := false
var _every := SAMPLE_EVERY
var _reload_only := false
var _reload_shot := -1
var _shots := ""
var _weapons: Array[StringName] = []
var _latest: Array[Transform3D] = []
## Kept poses: [weapon, beat, clip, tick, poses].
var _samples: Array[Array] = []
var _ticks := 0
var _command := PlayerCommand.new()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for arg in OS.get_cmdline_user_args():
		if arg == "--measure":
			_measure = true
		elif arg.begins_with("--reload-shot="):
			_reload_shot = int(arg.trim_prefix("--reload-shot="))
		elif arg.begins_with("--every="):
			_every = int(arg.trim_prefix("--every="))
		elif arg == "--reload-only":
			_reload_only = true
		elif arg == "--trace":
			_trace = true
		elif arg.begins_with("--look="):
			_look = int(arg.trim_prefix("--look="))
		elif arg.begins_with("--weapons="):
			for id in arg.trim_prefix("--weapons=").split(","):
				_weapons.append(StringName(id))
		elif arg.begins_with("--view="):
			_view = arg.trim_prefix("--view=")
		elif arg.begins_with("--write="):
			_write = arg.trim_prefix("--write=")
		elif arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
	if _weapons.is_empty():
		_weapons = WeaponCatalog.IDS.duplicate()
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_player.dress(CharacterLook.from_preset(_look))
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.skeleton_updated.connect(_grab)
	if VIEWS.has(_view):
		_camera = Camera3D.new()
		_camera.fov = 40.0
		_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_camera)
		_camera.make_current()
	_player.teleport(START)
	_player.camera_rig.yaw = 0.0
	_player.camera_rig.pitch = -0.08
	await _run()
	if _measure:
		await _measure_all()
	get_tree().quit()


func _process(_delta: float) -> void:
	if _camera == null:
		return
	var at := _player.global_position
	var yaw := Basis(Vector3.UP, _player.rotation.y)
	_camera.look_at_from_position(at + yaw * VIEWS[_view], at + LOOK, Vector3.UP)


func _grab() -> void:
	_latest.clear()
	for b in _skeleton.get_bone_count():
		_latest.append(_skeleton.get_bone_global_pose(b))


## Runs `ticks` physics ticks of a beat, submitting the command each tick and keeping a pose every
## few when measuring; `each` (when given) is called with the beat's tick first.
func _beat(weapon: StringName, beat: String, ticks: int, each := Callable()) -> void:
	print("BEAT %s %s frame %d" % [weapon, beat, Engine.get_process_frames()])
	for t in ticks:
		if each.is_valid():
			each.call(t)
		_command.yaw = _player.camera_rig.yaw
		_command.pitch = _player.camera_rig.pitch
		_player.submit_command(_command)
		await get_tree().physics_frame
		await get_tree().process_frame
		_ticks += 1
		if _measure and beat != "" and t % _every == 0 and not _latest.is_empty():
			_samples.append([weapon, beat, String(_animation.action_clip), t, _latest.duplicate()])
		var shoot: int = SHOT_AT.get(beat, -1)
		if beat == "reload" and _reload_shot >= 0:
			shoot = _reload_shot
		if _shots != "" and shoot == t:
			await RenderingServer.frame_post_draw
			var view := _view if _view != "" else "shoulder"
			var path := "%s/%d_%s_%s_%s%d.png" % [_shots, _look, view, weapon, beat, t]
			get_viewport().get_texture().get_image().save_png(path)


func _run() -> void:
	await _beat(&"-", "", 30)
	for id in _weapons:
		_animation.equip(id)
		await _beat(id, "equip", EQUIP_TICKS)
		if _reload_only:
			_animation.reload(RELOAD_SECONDS)
			await _beat(id, "reload", RELOAD_TICKS)
			await _beat(id, "", SETTLE_TICKS)
			continue
		await _beat(id, "hold", HOLD_TICKS)
		_command.aim = true
		await _beat(id, "aim", AIM_TICKS)
		var def := WeaponCatalog.get_def(id)
		# A gun fires every few ticks; a melee weapon swings once (its swing outlasts the beat).
		var every := FIRE_TICKS if def.is_melee() else SHOT_EVERY
		var shot := func(t: int) -> void:
			if t % every == 0:
				_animation.play_action(&"Swing" if def.is_melee() else &"Fire", (t / every) % 2)
		await _beat(id, "fire", FIRE_TICKS, shot)
		_command.aim = false
		await _beat(id, "", SETTLE_TICKS)
		_animation.strike()
		await _beat(id, "strike", STRIKE_TICKS)
		_command.move = Vector2(0.0, -1.0)
		_command.sprint = true
		await _beat(id, "sprint", SPRINT_TICKS)
		_command.move = Vector2.ZERO
		_command.sprint = false
		await _beat(id, "", SETTLE_TICKS)
		_player.teleport(START)
		await _beat(id, "", SETTLE_TICKS)
		if not def.is_melee():
			_animation.reload(RELOAD_SECONDS)
			await _beat(id, "reload", RELOAD_TICKS)
		await _beat(id, "", SETTLE_TICKS)
	if _reload_only:
		return
	await _beat(
		&"-",
		"repair",
		150,
		func(t: int) -> void:
			if t % 50 == 0:
				_animation.board_repaired(0.8)
	)
	_animation.stop_repair()
	await _beat(&"-", "", SETTLE_TICKS)
	_animation.grenade(&"cook")
	await _beat(&"-", "grenade_cook", 40)
	_animation.grenade(&"throw")
	await _beat(&"-", "grenade_throw", 50)
	_animation.set_downed(true)
	await _beat(&"-", "downed", DOWN_TICKS)
	_command.move = Vector2(0.0, -1.0)
	await _beat(&"-", "crawl", CRAWL_TICKS)
	_command.move = Vector2.ZERO
	_animation.set_downed(false)
	await _beat(&"-", "", 90)
	_animation.set_reviving(true)
	await _beat(&"-", "revive", REVIVE_TICKS)
	_animation.set_reviving(false)
	await _beat(&"-", "", 30)


## Measures every kept pose: the deepest of each check per weapon and beat.
func _measure_all() -> void:
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	# The probes wait two physics steps for each new surface: step faster than the game does.
	Engine.physics_ticks_per_second = 480
	var host := Node3D.new()
	add_child(host)
	var fit := BodyFit.new(host, _skeleton)
	var sampler := ClipFit.new(fit, _player)
	var worst := {}
	var table := {}
	for s: Array in _samples:
		var found := await sampler.measure(s[4])
		for check: String in found:
			var deepest: Dictionary = found[check][0]
			var key := "%s %s %s" % [s[0], s[1], check]
			if _trace:
				var at: Vector3 = _skeleton.global_transform.affine_inverse() * deepest.position
				var fault := [check, deepest.depth, found[check].size(), deepest.group, at]
				print(
					"TRACE %s %s tick %d " % [s[0], s[1], s[3]], "%s: %.3f (%d, %s) at %s" % fault
				)
			if deepest.depth > worst.get(key, {"depth": 0.0}).depth:
				worst[key] = {
					"depth": deepest.depth,
					"clip": s[2],
					"tick": s[3],
					"mesh": deepest.mesh,
					"group": deepest.group,
					"count": found[check].size()
				}
	var summary := {}
	for key: String in worst:
		var e: Dictionary = worst[key]
		print(
			(
				"NIGHT %d %s: %d vertices, deepest %.3f m at tick %d (clip %s; %s %s)"
				% [_look, key, e.count, e.depth, e.tick, e.clip, e.mesh, e.group]
			)
		)
		table[key] = snappedf(e.depth, 0.001)
		var beat := (
			key.get_slice(" ", 1) + " " + key.get_slice(" ", 2) + " " + key.get_slice(" ", 3)
		)
		summary[beat] = maxf(summary.get(beat, 0.0), snappedf(e.depth, 0.001))
	print("NIGHT_SUMMARY %d %s" % [_look, summary])
	print("NIGHT_SAMPLES %d" % _samples.size())
	if _write != "":
		var file := FileAccess.open(_write, FileAccess.WRITE)
		file.store_string(JSON.stringify(table, " ", true) + "\n")
	fit.free_bodies()
