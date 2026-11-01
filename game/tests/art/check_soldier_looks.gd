## Headless check of the modular Soldier (Deadnight #100): assembles every preset in parts.json
## with SoldierLook and checks that the right parts show and are skinned to the skeleton, that the
## triangle count matches the catalog and the player budget, that the look's colours reach the
## atlas, and that every clip is in the file and the weapon clips move the bones on each preset.
## The far level of detail (#139): every shown part's far mesh shows with it, is skinned to the same
## skeleton, shares its material and takes over at `SoldierLook.FAR_FROM`; the far triangles match
## the catalog and stay within the far budget.
## Build the .glb first (docs/design/characters.md, Rebuilding).
##
##     godot --headless --path game -s res://tests/art/check_soldier_looks.gd
## Prints LOOK:/FAR:/CLIPS:/WEAPON: lines and exits 1 on any failure.
extends SceneTree

## Bones the weapon clips must move: the spine and both arms carry recoil, sway and the swing.
const PROBE_BONES := ["Abdomen", "Torso", "UpperArm.R", "LowerArm.R", "UpperArm.L"]
const MIN_DEGREES := 1.0

var fails := 0


func _init() -> void:
	_run.call_deferred()


func _fail(msg: String) -> void:
	printerr("FAIL ", msg)
	fails += 1


func _run() -> void:
	var cat := SoldierLook.catalog()
	var ids := []
	for p: Dictionary in SoldierLook.presets():
		ids.append(p.id)
		_check_preset(cat, p)
	if ids.size() != 8:
		_fail("expected 8 presets, got %d" % ids.size())
	# Default looks: the first eight joiners all differ.
	var taken := []
	for i in 8:
		taken.append(SoldierLook.default_preset(taken).id)
	if taken.size() != 8 or _unique(taken) != 8:
		_fail("default presets repeat: %s" % [taken])
	print("DEFAULTS: ", taken)
	# A bad look still assembles: unknown parts fall back, indices wrap.
	var bad := SoldierLook.normalized({"parts": {"hair": "mohawk"}, "colours": {"skin": 99}})
	if (
		bad.parts.hair != cat.slots.hair.default
		or bad.colours.skin != 99 % cat.palettes.skin.size()
	):
		_fail("normalized() did not repair a bad look: %s" % [bad])
	print("RESULT: ", "ok" if fails == 0 else "%d failures" % fails)
	quit(1 if fails else 0)


func _check_preset(cat: Dictionary, p: Dictionary) -> void:
	var model := SoldierLook.instantiate()
	root.add_child(model)
	var tris := SoldierLook.apply(model, p)
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var want := SoldierLook.visible_meshes(p)
	var shown: Array[String] = []
	var meshes := SoldierLook.part_meshes(model)
	for mesh_name: String in meshes:
		var mi: MeshInstance3D = meshes[mesh_name]
		if not mi.visible:
			continue
		shown.append(mesh_name)
		if mi.skin == null or mi.get_node_or_null(mi.skeleton) != sk:
			_fail("%s: %s is not skinned to the skeleton" % [p.id, mesh_name])
			continue
		for b in mi.skin.get_bind_count():
			if sk.find_bone(mi.skin.get_bind_name(b)) < 0:
				_fail("%s: %s binds a missing bone" % [p.id, mesh_name])
	shown.sort()
	want.sort()
	if shown != want:
		_fail("%s shows %s, wants %s" % [p.id, shown, want])
	for slot: String in cat.slots:
		var part: Dictionary = cat.slots[slot].parts[p.parts[slot]]
		if part.mesh != null and not meshes.has(part.mesh):
			_fail("%s: no mesh %s in the model" % [p.id, part.mesh])
	if tris != int(p.tris) or tris > int(cat.budget):
		_fail("%s: %d tris (catalog %d, budget %d)" % [p.id, tris, p.tris, cat.budget])
	_check_far(cat, p, model, meshes, sk)
	# The look's primary colour sits in the primary swatch of the material the parts share.
	var mi0: MeshInstance3D = meshes[want[0]]
	var img := (mi0.material_override as StandardMaterial3D).albedo_texture.get_image()
	var cell: Array = cat.atlas.cells.primary
	var px: int = cat.atlas.swatch_px
	var got := img.get_pixel(int(cell[0]) * px + px / 2, int(cell[1]) * px + px / 2)
	var hex: String = cat.palettes.cloth[int(p.colours.primary)]
	if not got.is_equal_approx(Color.html(hex)):
		_fail("%s: primary swatch %s, wants %s" % [p.id, got.to_html(false), hex])
	print(
		(
			"LOOK: %-13s %d tris, %d parts, skin %d hair %d primary %d secondary %d accent %d"
			% [
				p.id,
				tris,
				shown.size(),
				p.colours.skin,
				p.colours.hair,
				p.colours.primary,
				p.colours.secondary,
				p.colours.accent
			]
		)
	)
	var missing := []
	for clip: String in cat.clips:
		if not player.has_animation(clip):
			missing.append(clip)
	if missing:
		_fail("%s: clips missing %s" % [p.id, missing])
	if p.id == SoldierLook.presets()[0].id:
		print(
			(
				"CLIPS: %d in the file, %d in parts.json"
				% [player.get_animation_list().size(), cat.clips.size()]
			)
		)
	var moved_all := 0
	var total := 0
	for cls: String in cat.weapon_clips:
		for clip: String in cat.weapon_clips[cls]:
			total += 1
			var deg := _max_motion(player, sk, clip)
			if deg < MIN_DEGREES:
				_fail("%s: %s moves the probe bones %.2f degrees" % [p.id, clip, deg])
			else:
				moved_all += 1
	print("WEAPON: %-13s %d/%d weapon clips move the spine and arms" % [p.id, moved_all, total])
	model.queue_free()


func _check_far(
	cat: Dictionary, p: Dictionary, model: Node, meshes: Dictionary, sk: Skeleton3D
) -> void:
	var far := SoldierLook.far_meshes(model)
	for mesh_name: String in meshes:
		var mi: MeshInstance3D = meshes[mesh_name]
		var fi: MeshInstance3D = far.get(mesh_name)
		if fi == null:
			_fail("%s: %s has no far mesh" % [p.id, mesh_name])
			continue
		if fi.visible != mi.visible:
			_fail("%s: %s far mesh shown %s, near %s" % [p.id, mesh_name, fi.visible, mi.visible])
		if not mi.visible:
			continue
		if fi.skin == null or fi.get_node_or_null(fi.skeleton) != sk:
			_fail("%s: %s far mesh is not skinned to the skeleton" % [p.id, mesh_name])
		elif fi.skin.get_bind_count() > 0 and sk.find_bone(fi.skin.get_bind_name(0)) < 0:
			_fail("%s: %s far mesh binds a missing bone" % [p.id, mesh_name])
		if fi.material_override != mi.material_override:
			_fail("%s: %s far mesh has another material" % [p.id, mesh_name])
		if (
			not is_equal_approx(mi.visibility_range_end, SoldierLook.FAR_FROM)
			or not is_equal_approx(fi.visibility_range_begin, SoldierLook.FAR_FROM)
		):
			_fail("%s: %s does not swap at %s m" % [p.id, mesh_name, SoldierLook.FAR_FROM])
		if SoldierLook.triangles(fi.mesh) > SoldierLook.triangles(mi.mesh):
			_fail("%s: %s far mesh is heavier than the near one" % [p.id, mesh_name])
	var tris_far := SoldierLook.far_triangles(model)
	if tris_far != int(p.tris_far) or tris_far > int(cat.far_budget):
		_fail(
			"%s: %d far tris (catalog %d, budget %d)" % [p.id, tris_far, p.tris_far, cat.far_budget]
		)
	print("FAR:  %-13s %d tris (near %d)" % [p.id, tris_far, p.tris])


## The largest rotation (degrees) of any probe bone away from its pose at the clip's first frame.
func _max_motion(player: AnimationPlayer, sk: Skeleton3D, clip: String) -> float:
	var anim := player.get_animation(clip)
	player.play(clip)
	player.seek(0.0, true)
	var start := {}
	for b: String in PROBE_BONES:
		start[b] = sk.get_bone_pose_rotation(sk.find_bone(b))
	var best := 0.0
	for i in range(1, 9):
		player.seek(anim.length * i / 8.0, true)
		for b: String in PROBE_BONES:
			var q: Quaternion = sk.get_bone_pose_rotation(sk.find_bone(b))
			best = maxf(best, rad_to_deg((start[b] as Quaternion).angle_to(q)))
	player.stop()
	return best


func _unique(a: Array) -> int:
	var d := {}
	for x in a:
		d[x] = true
	return d.size()
