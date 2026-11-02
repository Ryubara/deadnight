## Probe (Deadnight #460): per weapon and pose (standing, running, aimed, firing, reloading; the
## swing for melee), the hand parts' signed distance to the weapon (`HandContact`), and OBJ dumps
## of the posed body and the weapon for the close contact sheets (`tools/blender/render_grips.py`).
##     godot --headless --path game -s res://tests/art/probe_hands.gd -- --out <dir>
extends SceneTree

const TICK := 1.0 / 60.0
const WEAPONS: Array[StringName] = [
	&"pistol", &"flare_gun", &"smg", &"rifle", &"shotgun", &"crowbar", &"Melee"
]

var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation
var _skeleton: Skeleton3D
var _contact: HandContact
var _out := ""
var _want := false
var _result := {}
var _tag := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[args.find("--out") + 1] if args.has("--out") else "user://probe"
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var room: Node = load("res://world/test_room.tscn").instantiate()
	root.add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_rig = _player.camera_rig
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_rig.set_process(false)
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.skeleton_updated.connect(_on_updated)
	_player.teleport(Vector3(0, 0.05, 10))
	await _ticks(20)
	_contact = HandContact.new(_skeleton)
	var table := []
	for id in WEAPONS:
		_animation.equip(id)
		await _ticks(60)
		var melee := _animation.weapon_class == &"Melee"
		var poses := (
			["idle", "run", "aim", "fire", "reload"] if not melee else ["idle", "run", "swing"]
		)
		for pose: String in poses:
			Input.action_release("aim")
			Input.action_release("move_forward")
			await _ticks(30)
			match pose:
				"run":
					Input.action_press("move_forward")
					await _ticks(30)
				"aim":
					Input.action_press("aim")
					await _ticks(40)
				"fire":
					Input.action_press("aim")
					await _ticks(40)
					_animation.play_action(&"Fire")
					await _ticks(2)
				"reload":
					_animation.play_action(&"Reload")
					await _ticks(30)
				"swing":
					_animation.play_action(&"Swing")
					await _ticks(10)
			_tag = "%s_%s" % [id, pose]
			_contact.set_weapon(_animation.weapon())
			_want = true
			await _ticks(1)
			table.append(_result.duplicate(true))
	Input.action_release("aim")
	Input.action_release("move_forward")
	var f := FileAccess.open(_out.path_join("table.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(table, "  "))
	quit(0)


func _on_updated() -> void:
	if not _want:
		return
	_want = false
	_contact.set_weapon(_animation.weapon())
	var row := {"tag": _tag, "left_weight": _animation.fingers().left_weight}
	for side in ["R", "L"]:
		var m := _contact.measure(side)
		var parts := {}
		for part: String in m:
			parts[part] = snappedf(m[part].distance * 1000.0, 0.1)
		row[side] = parts
	var bones := {}
	for b in ["Index1.R", "Index1.L", "LowerArm.R", "LowerArm.L"]:
		bones[b] = _v(
			(
				_skeleton.global_transform
				* _skeleton.get_bone_global_pose(_skeleton.find_bone(b)).origin
			)
		)
	row["bones"] = bones
	for side in ["R", "L"]:
		var pts := _contact.skin_points(side)
		var c := Vector3.ZERO
		var n := 0
		for part: String in pts:
			for q: Vector3 in pts[part]:
				c += q
				n += 1
		row["centre_" + side] = _v(c / maxf(n, 1))
	var w := _animation.weapon()
	if w != null:
		var b := w.global_basis.orthonormalized()
		row["weapon_basis"] = [_v(b.x), _v(b.y), _v(b.z)]
		row["weapon_origin"] = _v(w.global_position)
	_result = row
	print("ROW ", JSON.stringify(row))
	_contact.dump_obj(_out.path_join(_tag + ".obj"))


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)]


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
		_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)
	await process_frame
