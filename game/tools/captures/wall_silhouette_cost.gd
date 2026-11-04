extends Node
## What a wall silhouette costs (#829), measured in the real renderer: for each wall spot, the draw
## calls and primitives of a frame looking at its plaque with the silhouette, with the sign it
## replaced (a Label3D of the old settings) and with neither; and the time the meshes take to make,
## cold (the models not yet loaded) and warm. Not part of the game. Run it windowed:
##
##   gds godot -- --path game res://tools/captures/wall_silhouette_cost.tscn --resolution 1920x1080
##       -- --map=drive_in|small_indoor
##

const NAMES := {
	&"weapon_pistol": "REVOLVER",
	&"weapon_crowbar": "CROWBAR",
	&"weapon_shotgun": "SHOTGUN",
	&"weapon_smg": "TOMMY GUN",
	&"weapon_baseball_bat": "BAT",
	&"weapon_flare_gun": "FLARE GUN",
	&"weapon_fire_axe": "FIRE AXE",
	&"weapon_rifle": "RIFLE",
	&"grenades": "GRENADES",
}

var _map := "drive_in"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map="):
			_map = argument.trim_prefix("--map=")
	var path := (
		"res://world/drive_in_greybox.tscn"
		if _map == "drive_in"
		else "res://world/smallmap/smallmap_greybox.tscn"
	)
	var scene := load(path) as PackedScene
	# The models loaded first (the night's warm-up loads them for the Soldier's hands anyway), so the
	# time of the meshes below is the silhouettes' own.
	var loading := Time.get_ticks_usec()
	for folder in DirAccess.get_directories_at("res://assets/weapons"):
		var file := "res://assets/weapons/%s/%s.glb" % [folder, folder]
		if ResourceLoader.exists(file):
			load(file)
	print("loading the weapon models: %.1f ms" % ((Time.get_ticks_usec() - loading) / 1000.0))
	var started := Time.get_ticks_usec()
	var map := scene.instantiate() as Node3D
	var instantiate_ms := (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	var made := {}
	for node in map.find_children("*", "WallSilhouette", true, false):
		var each := Time.get_ticks_usec()
		var key := (
			"%s%s"
			% [(node as WallSilhouette).shop_id, "|up" if (node as WallSilhouette).upright else ""]
		)
		if not made.has(key):
			SilhouetteMesh.of(map).mesh_for(
				(node as WallSilhouette).shop_id, (node as WallSilhouette).upright
			)
			made[key] = (Time.get_ticks_usec() - each) / 1000.0
	print("mesh by mesh (ms): ", made)
	print("all meshes: %.1f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	started = Time.get_ticks_usec()
	add_child(map)
	var cold_ms := (Time.get_ticks_usec() - started) / 1000.0
	var shapes := map.find_children("*", "WallSilhouette", true, false)
	var tris := 0
	for node in shapes:
		tris += SilhouetteMesh.triangle_count((node as WallSilhouette).shape.mesh as ArrayMesh)
	print(
		(
			"%s: %d silhouettes, %d triangles; instantiate %.1f ms; entering the tree after that %.1f ms"
			% [_map, shapes.size(), tris, instantiate_ms, cold_ms]
		)
	)
	var texts: Array[Label3D] = []
	var label_clock := 0
	for node in shapes:
		var silhouette := node as WallSilhouette
		var sign_node := Label3D.new()
		sign_node.text = NAMES.get(silhouette.shop_id, "?")
		sign_node.pixel_size = 0.006
		sign_node.font_size = 60
		sign_node.outline_size = 24
		sign_node.modulate = Color(0.1, 0.07, 0.02)
		sign_node.outline_modulate = Color(1, 0.9, 0.6)
		sign_node.visible = false
		var shaped := Time.get_ticks_usec()
		silhouette.add_child(sign_node)
		sign_node.get_aabb()  # builds the text's mesh, as the first draw would
		label_clock += Time.get_ticks_usec() - shaped
		texts.append(sign_node)
	print(
		(
			"the %d old signs (Label3D), built and shaped: %.1f ms"
			% [texts.size(), label_clock / 1000.0]
		)
	)
	var camera := Camera3D.new()
	camera.fov = 62.0
	add_child(camera)
	camera.make_current()
	await get_tree().process_frame
	print("spot | silhouette calls/prims | label calls/prims | neither calls/prims")
	var totals := [0, 0, 0, 0, 0, 0]
	for i in shapes.size():
		var silhouette := shapes[i] as WallSilhouette
		var front := silhouette.global_basis.z
		camera.look_at_from_position(
			silhouette.global_position + front * 4.0, silhouette.global_position
		)
		silhouette.shape.visible = true
		texts[i].visible = false
		# The view settles (lights and shadows cull for the new place) before anything is read.
		for _i in 30:
			await get_tree().process_frame
		var with_shape := await _frame()
		silhouette.shape.visible = false
		texts[i].visible = true
		var with_text := await _frame()
		texts[i].visible = false
		var neither := await _frame()
		silhouette.shape.visible = true
		print(
			(
				"%s | %d / %d | %d / %d | %d / %d"
				% [
					silhouette.name,
					with_shape[0],
					with_shape[1],
					with_text[0],
					with_text[1],
					neither[0],
					neither[1]
				]
			)
		)
		totals[0] += with_shape[0] - neither[0]
		totals[1] += with_shape[1] - neither[1]
		totals[2] += with_text[0] - neither[0]
		totals[3] += with_text[1] - neither[1]
	print(
		(
			"added per spot looked at: silhouette %.2f calls %.0f prims; label %.2f calls %.0f prims"
			% [
				totals[0] / float(shapes.size()),
				totals[1] / float(shapes.size()),
				totals[2] / float(shapes.size()),
				totals[3] / float(shapes.size())
			]
		)
	)
	get_tree().quit()


## The calls and the primitives of the frame, the lowest of five drawn frames (the first ones after
## a change can still be settling: shadows and lights cull for the new view).
func _frame() -> Array[int]:
	var lowest := [1 << 30, 1 << 30]
	for _i in 5:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		lowest[0] = mini(
			lowest[0],
			int(
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
				)
			)
		)
		lowest[1] = mini(
			lowest[1],
			int(
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
				)
			)
		)
	return [lowest[0], lowest[1]]
