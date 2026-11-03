extends GdUnitTestSuite
## Hair and hats against the shoulder camera (#678): the rig hides the whole body once its lens is
## closer than `hide_body_distance` to the pivot over the feet (`ThirdPersonCamera`), so nothing a
## look wears may reach farther from that pivot than that distance less the near plane, or the
## lens would cut through it before the body hides. Her cuts (bob, pin curls, bun) are held to it
## like his, on the player scene's own model scale and turn.

const PLAYER := "res://gameplay/player/player.tscn"
const TUNING := "res://gameplay/player/player_tuning_default.tres"
const HERS: Array[String] = ["bob", "curls", "bun"]


## Metres from the camera pivot to the farthest vertex of each hair and headwear mesh, at rest.
func _reach() -> Dictionary:
	var tuning := load(TUNING) as PlayerTuning
	var holder := Node3D.new()
	add_child(auto_free(holder))
	var model := SoldierLook.instantiate()
	holder.add_child(model)
	model.basis = Basis(Vector3.UP, PI).scaled(Vector3.ONE * tuning.model_scale)
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var pivot := Vector3(0.0, tuning.pivot_height, 0.0)
	var out := {}
	for mesh_name: String in SoldierLook.part_meshes(model):
		if not (mesh_name.begins_with("hair__") or mesh_name.begins_with("headwear__")):
			continue
		var mi: MeshInstance3D = SoldierLook.part_meshes(model)[mesh_name]
		var far := 0.0
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var per := bones.size() / maxi(count, 1)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in count:
				# Skinned 100 % to one bone: its first influence.
				var bind := bones[v * per]
				var bone := mi.skin.get_bind_bone(bind)
				if bone < 0:
					bone = skeleton.find_bone(mi.skin.get_bind_name(bind))
				var at := (
					skeleton.global_transform
					* skeleton.get_bone_global_rest(bone)
					* mi.skin.get_bind_pose(bind)
					* vertices[v]
				)
				far = maxf(far, at.distance_to(pivot))
		out[mesh_name.trim_prefix("hair__").trim_prefix("headwear__")] = far
	return out


func test_no_hair_or_hat_reaches_the_lens_before_the_body_hides() -> void:
	var tuning := load(TUNING) as PlayerTuning
	var camera := (load(PLAYER) as PackedScene).instantiate()
	var near := (camera.get_node("CameraRig/Camera3D") as Camera3D).near
	camera.free()
	var reach := _reach()
	assert_int(reach.size()).is_greater(10)
	for part: String in reach:
		(
			assert_float(reach[part])
			. override_failure_message(
				"%s reaches %.2f m from the camera pivot" % [part, reach[part]]
			)
			. is_less(tuning.hide_body_distance - near)
		)


func test_her_cuts_reach_no_farther_than_what_he_already_wears() -> void:
	var reach := _reach()
	var his := 0.0
	for part: String in reach:
		if part not in HERS:
			his = maxf(his, reach[part])
	for part in HERS:
		(
			assert_float(reach[part])
			. override_failure_message(
				"%s reaches %.2f m, his farthest %.2f m" % [part, reach[part], his]
			)
			. is_less_equal(his)
		)
