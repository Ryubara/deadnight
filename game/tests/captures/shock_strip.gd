extends Node3D
## The shock shader on its own, from above on a dark floor, at six moments of its life (issue
## #687): the ring running out, the bolts, the flash. `-- --out=<folder>` saves
## `shock_strip_<n>.png`; the strip is the shader alone, with no night, so a change to it is seen
## without a reload and a zombie. Not part of the game.
##
## `gds godot -- --path game res://tests/captures/shock_strip.tscn --resolution 640x640 --
## --out=<folder>`

const MOMENTS: Array[float] = [0.04, 0.15, 0.3, 0.5, 0.72, 0.92]
const RADIUS := 4.0


func _ready() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 20.0
	floor_mesh.mesh = plane
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.1, 0.1, 0.12)
	floor_mesh.material_override = ground
	add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = RADIUS * 2.4
	camera.position = Vector3(0.0, 10.0, 0.0)
	camera.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	add_child(camera)
	camera.make_current()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.02, 0.02, 0.04)
	add_child(environment)
	var shock := ShockEffect.new()
	add_child(shock)
	shock.play(Vector3.ZERO, RADIUS, 3)
	for i in MOMENTS.size():
		shock.freeze(MOMENTS[i])
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if out != "":
			DirAccess.make_dir_recursive_absolute(out)
			get_viewport().get_texture().get_image().save_png("%s/shock_strip_%d.png" % [out, i])
	get_tree().quit()
