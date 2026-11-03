## Writes the Soldier's grip on every weapon model (Deadnight #460):
## `gameplay/player/grips/<model>.tres`, solved from each model's hand sockets by `GripSolver`
## (docs/design/animation.md, "Grips"). About two minutes a gun on a quiet machine.
## Rerun it after changing a model, its sockets or its hold's size, then the test
## `tests/player/test_hand_grips.gd`.
##
##     godot --headless --path game -s res://tests/art/solve_grips.gd
##         [-- --only revolver,crowbar] [--dry] [--dump <dir>] [--fingers]
## `--fingers` keeps each model's written hold and left hand and solves the right hand's fingers
## only: the sprint carries are built from the hold (`tools/blender/soldier_clips.py`), so a finger
## fix that keeps it needs no new carry.
## Give it a timeout: a script that fails to parse leaves headless Godot running. `--dump` writes
## an OBJ of each solved hand and `table.json` for `tools/blender/render_grips.py`.
## Prints a `GRIP` line per model and a `FINGER` line per finger; `--dry` writes nothing.
extends SceneTree

## Every held model: its scene, the hold file whose size it is held at (or a size), how it is held,
## and for a melee weapon the hold whose turn about the handle it keeps.
const MODELS := {
	"revolver": {"hold": "res://gameplay/player/holds/pistol.tres", "kind": "gun"},
	"flare_gun": {"hold": "res://gameplay/player/holds/flare_gun.tres", "kind": "gun"},
	"tommy_gun": {"hold": "res://gameplay/player/holds/smg.tres", "kind": "gun"},
	"lever_rifle": {"hold": "res://gameplay/player/holds/rifle.tres", "kind": "gun"},
	"double_shotgun": {"hold": "res://gameplay/player/holds/shotgun.tres", "kind": "gun"},
	"baseball_bat": {"hold": "res://gameplay/player/holds/melee.tres", "kind": "melee"},
	"crowbar": {"hold": "res://gameplay/player/holds/crowbar.tres", "kind": "melee"},
	"hammer": {"hold": "res://gameplay/player/holds/hammer.tres", "kind": "hammer"},
	"fire_axe":
	{"scene": "res://assets/weapons/fire_axe/fire_axe.glb", "model_scale": 0.95, "kind": "melee"},
	"grenade": {"hold": "res://gameplay/player/holds/grenade.tres", "kind": "ball"},
	# The heavy batch (#796), at the plan's sizes (docs/research/weapon-models.md#the-nine) until
	# #793 adds their holds: a hold must keep this `model_scale` or the grip is solved again.
	"fifty_cal":
	{"scene": "res://assets/weapons/fifty_cal/fifty_cal.glb", "model_scale": 1.21, "kind": "gun"},
	"pump_870":
	{"scene": "res://assets/weapons/pump_870/pump_870.glb", "model_scale": 1.3, "kind": "gun"},
	"m249": {"scene": "res://assets/weapons/m249/m249.glb", "model_scale": 1.3, "kind": "gun"},
	# #797's models, at the size their holds will give them (docs/research/weapon-models.md): the
	# holds are #788's and #789's, so the size is written here until they point at these models.
	"service_pistol":
	{
		"scene": "res://assets/weapons/service_pistol/service_pistol.glb",
		"model_scale": 1.95,
		"kind": "gun"
	},
	"ray_gun":
	{"scene": "res://assets/weapons/ray_gun/ray_gun.glb", "model_scale": 2.275, "kind": "gun"},
	"freeze_gun":
	{"scene": "res://assets/weapons/freeze_gun/freeze_gun.glb", "model_scale": 1.3, "kind": "gun"},
}

var _args := {}


func _init() -> void:
	var argv := OS.get_cmdline_user_args()
	for i in argv.size():
		if argv[i] == "--only":
			_args["only"] = argv[i + 1].split(",")
		elif argv[i] == "--dry":
			_args["dry"] = true
		elif argv[i] == "--dump":
			_args["dump"] = argv[i + 1]
		elif argv[i] == "--fingers":
			_args["fingers"] = true
	_run.call_deferred()


func _run() -> void:
	var solver := GripSolver.new(root)
	solver.dump_dir = _args.get("dump", "")
	var rows := []
	await process_frame
	for name: String in MODELS:
		if _args.has("only") and name not in _args.only:
			continue
		var spec: Dictionary = (MODELS[name] as Dictionary).duplicate()
		var scene := ""
		if spec.has("hold"):
			var hold := load(spec.hold) as WeaponHold
			scene = hold.scene
			spec["model_scale"] = hold.model_scale
		else:
			scene = spec.get("scene", "")
		spec["reference"] = _reference(spec.kind)
		spec["name"] = name
		var started := Time.get_ticks_msec()
		var grip := HandGrip.new()
		var written := HandGrip.for_name(name) if _args.has("fingers") else null
		if written != null:
			spec["keep_hold"] = written.hold
			grip = written.duplicate(true) as HandGrip
		grip.model_scale = spec.model_scale
		var right := solver.solve("R", _instance(scene), spec)
		grip.hold = right.hold
		grip.right = right.fingers
		grip.right_contacts = right.contacts
		grip.trigger_finger = right.trigger_finger
		rows.append(right.row)
		var model := _instance(scene)
		if written != null:
			model.free()
		elif model.find_child("Support", true, false) != null:
			var left_spec := spec.duplicate()
			left_spec["grip"] = "Support"
			left_spec.erase("reference")
			var left := solver.solve("L", model, left_spec)
			grip.has_left = true
			grip.left_hand = (
				(left.hold as Transform3D)
				. scaled_local(Vector3.ONE * spec.model_scale)
				. affine_inverse()
			)
			grip.left = left.fingers
			grip.left_contacts = left.contacts
			rows.append(left.row)
			print("GRIP %s L contacts=%s table=%s" % [name, left.contacts, left.table])
		else:
			model.free()
		print(
			(
				"GRIP %s R trigger=%s contacts=%s table=%s turn=%.1f deg (%d ms)"
				% [
					name,
					right.trigger_finger,
					right.contacts,
					right.table,
					_turn(spec.reference, right.hold),
					Time.get_ticks_msec() - started
				]
			)
		)
		if not _args.has("dry"):
			var path := HandGrip.DIR + name + ".tres"
			DirAccess.make_dir_recursive_absolute(HandGrip.DIR)
			var err := ResourceSaver.save(grip, path)
			if err != OK:
				printerr("could not write ", path)
	if solver.dump_dir != "":
		var f := FileAccess.open(solver.dump_dir.path_join("table.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(rows, "  "))
	for line in solver.log_lines:
		print(line)
	quit(0)


## The model to solve: its glb, or for the grenade the shell the hand shows.
func _instance(scene: String) -> Node3D:
	if scene == "":
		var shell := Node3D.new()
		GrenadeView.add_placeholder(shell)
		return shell
	return (load(scene) as PackedScene).instantiate() as Node3D


## The hold the model had before (the kit's), for its turn about the handle.
static func _reference(kind: String) -> Transform3D:
	match kind:
		"gun":
			return PlayerAnimation.HOLD_GUN
		"hammer":
			return PlayerAnimation.HOLD_HAMMER
		"ball":
			return Transform3D(Basis(), PlayerAnimation.HOLD_MELEE.origin)
	return PlayerAnimation.HOLD_MELEE


## Degrees between the old hold's turn and the new one.
static func _turn(reference: Transform3D, hold: Transform3D) -> float:
	var a := reference.basis.orthonormalized().get_rotation_quaternion()
	var b := hold.basis.orthonormalized().get_rotation_quaternion()
	return rad_to_deg(a.angle_to(b))
