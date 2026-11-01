## Headless check of the boss zombie (Deadnight #98): the file holds the shared 50-bone skeleton,
## both levels of detail, the lit weak spot and every clip in clips.json with its length; every
## boss clip moves the bones it should, and the moments the behaviour code times on hold: the
## attack's hands are overhead at `telegraph` and down at `hit`, the stagger folds the chest, the
## death ends on the ground; and the zombie behaviour's `ZombieRig` drives it unchanged.
## Build the .glb first (tools/blender/build_boss.py).
##
##     godot --headless --path game -s res://tests/art/check_zombie_boss.gd
## Prints CLIP:/POSE:/RESULT: lines and exits 1 on any failure.
extends SceneTree

const GLB := "res://assets/characters/zombie_boss/zombie_boss.glb"
const SPEC := "res://assets/characters/zombie_boss/clips.json"
const KIT_CLIPS := ["Idle", "Walk", "Run", "Punch", "HitReact", "Death"]
## Bones every boss clip must turn by at least MIN_TURN degrees somewhere in the clip.
const MOVERS := {
	"Boss_Walk": ["UpperLeg.L", "UpperLeg.R", "Torso"],
	"Boss_Attack": ["UpperArm.L", "UpperArm.R", "Torso", "Abdomen"],
	"Boss_Roar": ["UpperArm.L", "UpperArm.R", "Head", "Torso"],
	"Boss_Stagger": ["Torso", "Abdomen", "LowerArm.L"],
	"Boss_Death": ["Torso", "UpperLeg.L", "Body"],
}
const MIN_TURN := 10.0

var fails := 0
var sk: Skeleton3D
var player: AnimationPlayer


func _init() -> void:
	_run.call_deferred()


func _fail(msg: String) -> void:
	printerr(msg)
	fails += 1


func _run() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var boss: Node3D = (load(GLB) as PackedScene).instantiate()
	root.add_child(boss)
	player = boss.find_child("AnimationPlayer", true, false)
	sk = boss.find_child("Skeleton3D", true, false)
	_check_file(boss, spec)
	for clip: String in spec.clips:
		_check_motion(clip, spec.clips[clip])
	_check_moments(spec.clips)
	_check_shared_rig()
	print("RESULT: ", "ok" if fails == 0 else "%d failures" % fails)
	quit(1 if fails else 0)


func _check_file(boss: Node3D, spec: Dictionary) -> void:
	if sk.get_bone_count() != 50:
		_fail("bones %d != 50 (the kit zombie's skeleton)" % sk.get_bone_count())
	for mesh_name in ["Zombie_Mesh", "Zombie_Far"]:
		var mesh := boss.find_child(mesh_name, true, false) as MeshInstance3D
		if mesh == null:
			_fail("missing mesh " + mesh_name)
			continue
		var tris := 0
		for s in mesh.mesh.get_surface_count():
			tris += mesh.mesh.surface_get_array_index_len(s) / 3
		var mat := mesh.get_active_material(0) as StandardMaterial3D
		var lit := mat != null and mat.emission_enabled and mat.emission_texture != null
		print(
			(
				"MESH: %s %d tris, %d surface(s), emission %s"
				% [mesh_name, tris, mesh.mesh.get_surface_count(), lit]
			)
		)
		if not lit:
			_fail(mesh_name + " has no emission map: the weak spot would not glow")
	var weak := boss.find_child("WeakSpot", true, false) as Node3D
	var attach := weak.get_parent() as BoneAttachment3D if weak else null
	print("WEAKSPOT: ", weak != null, " on ", attach.bone_name if attach else "-")
	if attach == null or attach.bone_name != spec.weak_spot.bone:
		_fail("WeakSpot is not on the %s bone" % spec.weak_spot.bone)
	var scale := (sk.get_parent() as Node3D).scale.x
	if absf(scale - float(spec.height)) > 0.01:
		_fail("armature scale %.2f != height %.2f" % [scale, spec.height])
	for clip: String in KIT_CLIPS + Array(spec.clips.keys()):
		if not player.has_animation(clip):
			_fail("missing clip " + clip)
	for clip: String in spec.clips:
		var a := player.get_animation(clip)
		if a and absf(a.length - float(spec.clips[clip].seconds)) > 0.05:
			_fail("length %s %.3f != %.3f" % [clip, a.length, spec.clips[clip].seconds])


func _pose_at(clip: String, t: float) -> void:
	player.play(clip)
	player.seek(t, true)


func _check_motion(clip: String, info: Dictionary) -> void:
	var length := float(info.seconds)
	var turns := {}
	for bone: String in MOVERS[clip]:
		var b := sk.find_bone(bone)
		_pose_at(clip, 0.0)
		var first := sk.get_bone_pose_rotation(b)
		var most := 0.0
		for i in 13:
			_pose_at(clip, length * i / 12.0)
			most = maxf(most, rad_to_deg(first.angle_to(sk.get_bone_pose_rotation(b))))
		turns[bone] = most
		if most < MIN_TURN:
			_fail("%s: %s turns only %.1f deg" % [clip, bone, most])
	var parts := PackedStringArray()
	for bone: String in turns:
		parts.append("%s %.0f" % [bone, turns[bone]])
	print("CLIP: %s %.2f s, max turn: %s" % [clip, length, ", ".join(parts)])


## Height of a bone above the skeleton origin, in the skeleton's up axis (Z: the armature node
## turns it).
func _height(bone: String) -> float:
	return sk.get_bone_global_pose(sk.find_bone(bone)).origin.z


func _hands() -> float:
	return minf(_height("Index1.L"), _height("Index1.R"))


func _check_moments(clips: Dictionary) -> void:
	var fps := 24.0
	_pose_at("Idle", 0.0)
	var idle_head := _height("Head")
	var idle_hands := _hands()
	var atk: Dictionary = clips.Boss_Attack.events
	_pose_at("Boss_Attack", atk.telegraph / fps)
	var up_hands := _hands()
	var up_head := _height("Head")
	_pose_at("Boss_Attack", atk.hit / fps)
	var hit_hands := _hands()
	print(
		(
			"POSE: attack hands: idle %.2f, telegraph %.2f (head %.2f), hit %.2f"
			% [idle_hands, up_hands, up_head, hit_hands]
		)
	)
	if up_hands <= up_head:
		_fail("the attack's wind-up does not lift both hands above the head")
	if hit_hands >= idle_hands:
		_fail("the attack's hit does not bring the hands down")
	_pose_at("Boss_Stagger", 12 / fps)
	var fold := _height("Head")
	print("POSE: stagger head %.2f (idle %.2f)" % [fold, idle_head])
	if fold >= idle_head - 0.02:
		_fail("the stagger does not fold the body over the weak spot")
	_pose_at("Boss_Death", float(clips.Boss_Death.seconds))
	var dead := _height("Head")
	print("POSE: death head %.2f (idle %.2f)" % [dead, idle_head])
	if dead > idle_head * 0.45:
		_fail("the death does not end on the ground")


## The behaviour code's rig (shared library, state machine) on the boss: the walk moves its legs.
func _check_shared_rig() -> void:
	var boss: Node3D = (load(GLB) as PackedScene).instantiate()
	root.add_child(boss)
	var tree := ZombieRig.attach(boss)
	tree.set(ZombieRig.BLEND_PARAMETER, ZombieRig.WALK_AT)
	var playback: AnimationNodeStateMachinePlayback = tree.get(ZombieRig.PLAYBACK_PARAMETER)
	playback.start(ZombieRig.STATE_MOVE)
	var skel: Skeleton3D = boss.find_child("Skeleton3D", true, false)
	var leg := skel.find_bone("UpperLeg.L")
	tree.advance(0.0)
	var start := skel.get_bone_pose_rotation(leg)
	var most := 0.0
	for i in 8:
		tree.advance(0.1)
		most = maxf(most, rad_to_deg(start.angle_to(skel.get_bone_pose_rotation(leg))))
	print("RIG: ZombieRig walk on the boss turns UpperLeg.L %.0f deg" % most)
	if most < MIN_TURN:
		_fail("ZombieRig's walk does not move the boss's legs")
	ZombieRig.release()
	boss.queue_free()
