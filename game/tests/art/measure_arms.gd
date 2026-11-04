extends Node
## Prints the Soldier's arm in every hold of the menu's stage (#978): one `ARM` line per look and
## weapon with each arm's upper arm and forearm as drawn (a hold that stretched a bone would show
## here), how far the shoulder is from the wrist against the arm's whole reach, and how far the
## left hand bone is from where the hold wanted it (an arm too short for a fore-end stops short).
## Not a test: the table behind `test_arm_proportions.gd` and docs/research/soldier-parts.md.
##
##     godot --headless --path game res://tests/art/measure_arms.tscn -- [--looks=0,10]

const SIDES := {
	"R": ["UpperArm.R", "LowerArm.R", "Index1.R"], "L": ["UpperArm.L", "LowerArm.L", "Index1.L"]
}

## A trial forearm length (a share of the built one), set on the skeleton's rest at run time: the
## hold's reach for a shorter arm before the model is built with it. 1 measures the model as built.
static var forearm_trial := 1.0
## Trial changes to every two-handed hold (stance turned): degrees more stance, metres pulled back.
static var stance_trial := 0.0
static var pull_trial := 0.0
## The view's pitch the arms are posed at (radians, up positive), or the menu's low ready.
static var pitch_trial := NAN
## The trial holds, kept so the loader's cache hands out these and not fresh copies.
static var _kept: Array[WeaponHold] = []

var _host: Node3D


func _ready() -> void:
	var looks := PackedStringArray(["0", "10"])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--looks="):
			looks = arg.substr(8).split(",")
		elif arg.begins_with("--forearm="):
			forearm_trial = float(arg.substr(10))
		elif arg.begins_with("--stance="):
			stance_trial = float(arg.substr(9))
		elif arg.begins_with("--pitch="):
			pitch_trial = float(arg.substr(8))
		elif arg.begins_with("--pull="):
			pull_trial = float(arg.substr(7))
	for id in MenuHero.available():
		var h := WeaponHoldMap.hold_for(id)
		if h != null and h.stance_turn_deg > 0.0:
			_kept.append(h)
			h.stance_turn_deg += stance_trial
			h.grip_offset.z += pull_trial
	_host = Node3D.new()
	add_child(_host)
	var worst := {"reach": 0.0, "miss": 0.0, "stretch": 0.0}
	for spec in looks:
		for id in MenuHero.available():
			var m := await measure(_host, CharacterLook.from_preset(int(spec)), id)
			print(
				(
					(
						"ARM %s %-12s R upper %.3f fore %.3f reach %.2f"
						+ " | L upper %.3f fore %.3f reach %.2f miss %.3f pulled %.3f"
					)
					% [
						spec,
						id,
						m.R.upper,
						m.R.fore,
						m.R.reach,
						m.L.upper,
						m.L.fore,
						m.L.reach,
						m.L.miss,
						m.get("pulled", 0.0)
					]
				)
			)
			worst.reach = maxf(worst.reach, maxf(m.R.reach, m.L.reach))
			worst.miss = maxf(worst.miss, m.L.miss)
	print("ARM_SUMMARY ", worst)
	get_tree().quit()


## One look holding weapon `id` on the menu's stage, read when the skeleton has the hand pose on:
## {R, L: {upper, fore, reach (shoulder to wrist over upper + fore), miss (metres, the left hand
## bone from the hold's place for it; 0 with no left grip)}}, in the game's metres.
static func measure(host: Node3D, look: CharacterLook, id: StringName) -> Dictionary:
	var hero := MenuHero.new()
	host.add_child(hero)
	hero.show_look(look, id)
	var skeleton := hero.model.find_child("Skeleton3D", true, false) as Skeleton3D
	if forearm_trial != 1.0:
		for b in skeleton.get_bone_count():
			var parent := skeleton.get_bone_parent(b)
			if parent >= 0 and skeleton.get_bone_name(parent).begins_with("LowerArm"):
				var r := skeleton.get_bone_rest(b)
				r.origin *= forearm_trial
				skeleton.set_bone_rest(b, r)
				skeleton.set_bone_pose_position(b, r.origin)
	var hands := _ik(skeleton)
	for _i in 30:
		if hands != null and not is_nan(pitch_trial):
			hands.aim_pitch = pitch_trial
		hero.advance(1.0 / 30.0)
		await host.get_tree().process_frame
	var out := {}
	var grab := func() -> void:
		if not out.is_empty():
			return
		var ik := _ik(skeleton)
		for side: String in SIDES:
			var p: Array[Vector3] = []
			for name: String in SIDES[side]:
				var bone := skeleton.find_bone(name)
				p.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin)
			var upper := p[0].distance_to(p[1])
			var fore := p[1].distance_to(p[2])
			var miss := 0.0
			if side == "L" and ik != null and ik.active and ik.grip != null and ik.grip.has_left:
				miss = ik.solved_left().origin.distance_to(p[2])
			if side == "L" and ik != null:
				out["pulled"] = ik.pulled()
			out[side] = {
				"upper": upper,
				"fore": fore,
				"reach": p[0].distance_to(p[2]) / (upper + fore),
				"miss": miss
			}
	skeleton.skeleton_updated.connect(grab)
	if hands != null and not is_nan(pitch_trial):
		hands.aim_pitch = pitch_trial
	hero.advance(1.0 / 30.0)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	skeleton.skeleton_updated.disconnect(grab)
	host.remove_child(hero)
	hero.free()
	return out


static func _ik(skeleton: Skeleton3D) -> WeaponHandsIK:
	for child in skeleton.get_children():
		if child is WeaponHandsIK:
			return child
	return null
