extends Node3D
## What the wildest cosmetic tier could cost (issue #1053): four Soldiers in view, each wearing a
## test
## effect (wings with blue fire, flame sparks, a halo and the engine's glow), built in arms so each
## part's cost
## can be read from the frame. NOT part of the game: nothing here is loaded by a shipped scene, and
## the web
## export leaves `tests/` out. Read `docs/research/cosmetic-rarity.md`.
##
## Arms (`--arm=`, or `?arm=` in a page), each adds to the one before except where it says:
##   base    four Soldiers, nothing else
##   wings   a dark feathered wing pair on each back (one opaque surface)
##   flame   wings + the flame sheet over them (one additive surface)
##   gpu     flame + a `GPUParticles3D` of sparks each
##   cpu     flame + a `CPUParticles3D` of sparks each (instead of gpu)
##   halo    gpu + a billboard glow quad on each (the project's `glow.gdshader`): the fake glow
##   halo_small  the same halo at 1.8 m instead of 3.4 m: a quad costs by the pixels it covers
##   glow    gpu + the engine's glow (`Environment.glow_enabled`), a post pass
##   glow_lite  `glow` with one blur level (the fourth) instead of the default three: the cheaper
##   real glow
##   full    gpu + halo + glow
## Other arguments: `--frames=N` (measured, default 300), `--settle=N` (default 150), `--players=N`
## (default 4),
## `--orbit` (a slow turn of the camera, for a clip), `--shot=PATH` (desktop: save the view as PNG
## and quit),
## `--unpaced` (desktop: no vertical sync, so the frame time is the work).
## The page's query is read as the arguments; the report is `window.__bench`.

const FEATHERS := 7
const SEGMENTS := 5
const QUERY := "location.search.replace(/^\\?/, '')"
const GLOW_SHADER := "res://world/drive_in/glow.gdshader"
const WING_SHADER := preload("res://tests/captures/cosmetic_fx_wing.gdshader")
const FLAME_SHADER := preload("res://tests/captures/cosmetic_fx_flame.gdshader")
## Distance in metres from the camera and the turn of each player, so the four read as a party seen
## from behind
## and from the side (the third-person camera sees its own Soldier close and the others further
## away).
const SPOTS := [
	[Vector3(-1.9, 0, 0.5), 200.0],
	[Vector3(-0.2, 0, -1.5), 165.0],
	[Vector3(1.5, 0, -0.4), 235.0],
	[Vector3(3.2, 0, -2.4), 120.0],
]

var _args := {}
var _arm := "base"
var _players: Array[Node3D] = []
var _cam: Camera3D
var _frame := 0
var _last_usec := 0
var _rows: Array[Dictionary] = []
var _reported := false
var _glow_levels: Array[float] = []


func _ready() -> void:
	_args = _parse_args()
	_arm = String(_args.get("arm", "base"))
	if _args.has("unpaced"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_build_world()
	var count := mini(int(_args.get("players", 4)), SPOTS.size())
	for i in count:
		_players.append(_soldier(i))
	_last_usec = Time.get_ticks_usec()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.025, 0.045)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.35, 0.4, 0.55)
	env.environment.ambient_light_energy = 0.5
	if _arm in ["glow", "glow_lite", "full"]:
		env.environment.glow_enabled = true
		env.environment.glow_intensity = 0.9
		env.environment.glow_strength = 1.0
		env.environment.glow_bloom = 0.1
		env.environment.glow_hdr_threshold = 0.7
		env.environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		if _arm == "glow_lite":
			for level in 7:
				env.environment.set_glow_level(level, 1.0 if level == 3 else 0.0)
		for level in 7:
			_glow_levels.append(env.environment.get_glow_level(level))
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.light_energy = 0.5
	moon.rotation_degrees = Vector3(-50, 30, 0)
	add_child(moon)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.07, 0.07, 0.08)
	ground.material_override = asphalt
	add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = 55
	add_child(_cam)
	_place_camera(0.0)


func _place_camera(turn: float) -> void:
	# Behind the party, a little above head height, looking at the middle of them.
	var eye := Vector3(0.6, 1.9, 5.6)
	eye = eye.rotated(Vector3.UP, turn)
	_cam.position = eye
	_cam.look_at(Vector3(0.6, 1.25, -0.4))


func _soldier(index: int) -> Node3D:
	var look := SoldierLook.instantiate()
	SoldierLook.apply(look, SoldierLook.presets()[index % SoldierLook.presets().size()])
	look.scale = Vector3.ONE * 0.8
	look.position = SPOTS[index][0]
	look.rotation_degrees.y = SPOTS[index][1]
	add_child(look)
	var anim: AnimationPlayer = look.find_child("AnimationPlayer", true, false)
	# Two stand, two run: the wings follow a torso that moves.
	var clip := "Idle" if index % 2 == 0 else "Run"
	anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.play(clip)
	if _arm != "base":
		_dress(look)
	return look


## The effect on one Soldier, by arm.
func _dress(look: Node3D) -> void:
	var skeleton: Skeleton3D = look.find_child("Skeleton3D", true, false)
	var mount := BoneAttachment3D.new()
	mount.bone_name = "Torso"
	skeleton.add_child(mount)
	var root := Node3D.new()
	# Between the shoulder blades, turned so a wing's length runs up and out (the bone's axes are
	# the rig's).
	# The bone's rest axes are the rig's, not the world's: cancel them against the model's own, so
	# the wings stand up
	# as built at rest, and they then follow the torso's lean in every pose.
	var at_rest := (
		skeleton.global_basis * skeleton.get_bone_global_rest(skeleton.find_bone("Torso")).basis
	)
	root.basis = at_rest.inverse() * look.global_basis
	root.position = at_rest.inverse() * (look.global_basis * Vector3(0, -0.04, -0.14))
	mount.add_child(root)
	var wings := MeshInstance3D.new()
	wings.mesh = _wing_mesh(_arm != "wings")
	wings.set_surface_override_material(0, _wing_material())
	if wings.mesh.get_surface_count() > 1:
		wings.set_surface_override_material(1, _flame_material())
	wings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wings)
	if _arm in ["gpu", "halo", "halo_small", "glow", "glow_lite", "full"]:
		root.add_child(_gpu_sparks())
	if _arm == "cpu":
		root.add_child(_cpu_sparks())
	if _arm in ["halo", "halo_small", "full"]:
		root.add_child(_halo())


## Two wings, mirrored: a fan of tapered feathers each. Surface 0 is the feathers, surface 1 the
## same fan wider and
## longer for the flame (left out for the `wings` arm). COLOR.r is a number per feather the shaders
## vary by.
func _wing_mesh(with_flame := true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for pass_index in 2 if with_flame else 1:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for side in [-1.0, 1.0]:
			for f in FEATHERS:
				var t := float(f) / float(FEATHERS - 1)
				var angle := deg_to_rad(lerpf(52.0, 112.0, t))
				var length := lerpf(0.5, 0.95, sin(t * PI * 0.5 + 0.4) / sin(PI * 0.5 + 0.4))
				var width := lerpf(0.13, 0.17, t)
				if pass_index == 1:
					length *= 1.3
					width *= 1.7
				_feather(
					st, side, angle, length, width, float(f) / FEATHERS + (0.0 if side < 0 else 0.5)
				)
		st.generate_normals()
		st.commit(mesh)
	return mesh


func _feather(
	st: SurfaceTool, side: float, angle: float, length: float, width: float, seed_v: float
) -> void:
	# The feather leaves the root up and out (angle from straight up), curving back a little.
	var dir := Vector3(sin(angle) * side, cos(angle), -0.0).normalized()
	# The fan lies flat against the back (the XY plane): a feather is as wide in that plane as it
	# is long.
	var across := Vector3(dir.y, -dir.x, 0.0).normalized()
	var points: Array[Vector3] = []
	for s in SEGMENTS + 1:
		var u := float(s) / SEGMENTS
		var bend := Vector3(side * u * u * 0.18, -u * u * 0.22, -u * 0.05)
		points.append(dir * length * u + bend)
	for s in SEGMENTS:
		var u0 := float(s) / SEGMENTS
		var u1 := float(s + 1) / SEGMENTS
		var w0 := width * (1.0 - u0 * u0 * 0.85)
		var w1 := width * (1.0 - u1 * u1 * 0.85)
		var a := points[s] - across * w0
		var b := points[s] + across * w0
		var c := points[s + 1] - across * w1
		var d := points[s + 1] + across * w1
		var col := Color(seed_v, 0, 0)
		var quad := [
			[a, Vector2(0, u0)], [b, Vector2(1, u0)], [c, Vector2(0, u1)], [d, Vector2(1, u1)]
		]
		for i in [0, 1, 2, 1, 3, 2]:
			st.set_color(col)
			st.set_uv(quad[i][1])
			st.add_vertex(quad[i][0])


func _wing_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WING_SHADER
	return mat


func _flame_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FLAME_SHADER
	return mat


func _spark_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(0, 0, 0, 1))
	tex.gradient = grad
	mat.albedo_texture = tex
	return mat


func _spark_gradient() -> Gradient:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.82, 0.94, 1.0, 1.0))
	grad.add_point(0.4, Color(0.08, 0.38, 1.0, 1.0))
	grad.set_color(grad.get_point_count() - 1, Color(0.04, 0.2, 0.6, 0.0))
	return grad


func _spark_quad() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	quad.material = _spark_material()
	return quad


func _gpu_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.1
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3, 3, 3))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(0.7, 0.45, 0.04)
	m.direction = Vector3(0, 1, 0)
	m.spread = 25.0
	m.initial_velocity_min = 0.1
	m.initial_velocity_max = 0.4
	m.gravity = Vector3(0, 0.6, 0)
	m.scale_min = 0.5
	m.scale_max = 1.4
	var ramp := GradientTexture1D.new()
	ramp.gradient = _spark_gradient()
	m.color_ramp = ramp
	p.process_material = m
	p.draw_pass_1 = _spark_quad()
	return p


func _cpu_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.1
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.7, 0.45, 0.04)
	p.direction = Vector3(0, 1, 0)
	p.spread = 25.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.color_ramp = _spark_gradient()
	p.mesh = _spark_quad()
	return p


## The fake glow: a billboard quad the body stands in front of (the camera sits behind the wearer,
## so the quad is
## pushed into the chest and the body hides what it would veil), the project's own additive disc
## shader.
func _halo() -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.8, 1.8) if _arm == "halo_small" else Vector2(3.4, 3.4)
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load(GLOW_SHADER)
	mat.set_shader_parameter("tint", Color(0.12, 0.38, 1.0))
	mat.set_shader_parameter("energy", 0.4)
	mat.set_shader_parameter("falloff", 2.4)
	mat.set_shader_parameter("billboard", true)
	quad.material_override = mat
	quad.position = Vector3(0, 0.3, 0.45)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return quad


func _process(_delta: float) -> void:
	if _args.has("orbit"):
		_place_camera(sin(_frame * 0.02) * 0.7)
	var now := Time.get_ticks_usec()
	_frame += 1
	if _frame == int(_args.get("settle", 150)) + 1 and OS.has_feature("web"):
		JavaScriptBridge.eval("window.__settled = true;")  # the probe counts WebGL calls from here
	if _frame > int(_args.get("settle", 150)) and not _reported:
		_record((now - _last_usec) / 1000.0)
		if _args.has("shot") and _rows.size() == 5:
			_reported = true
			get_viewport().get_texture().get_image().save_png(String(_args.shot))
			get_tree().quit()
		if _rows.size() >= int(_args.get("frames", 300)):
			_reported = true
			_report.call_deferred()
	_last_usec = now


func _record(frame_ms: float) -> void:
	var rid := get_viewport().get_viewport_rid()
	(
		_rows
		. append(
			{
				"frame": frame_ms,
				"draws":
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
				),
				"objects":
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
				),
				"tris":
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
				),
				"gpu": RenderingServer.viewport_get_measured_render_time_gpu(rid),
				"cpu": RenderingServer.viewport_get_measured_render_time_cpu(rid),
			}
		)
	)


func _mean(key: String) -> float:
	var total := 0.0
	for row in _rows:
		total += float(row[key])
	return total / _rows.size()


func _report() -> void:
	var times: Array[float] = []
	for row in _rows:
		times.append(row.frame)
	times.sort()
	var out := {
		"arm": _arm,
		"players": _players.size(),
		"frames": _rows.size(),
		"frame_mean_ms": snappedf(_mean("frame"), 0.01),
		"frame_median_ms": snappedf(times[times.size() / 2], 0.01),
		"frame_p95_ms": snappedf(times[int(times.size() * 0.95)], 0.01),
		"draw_calls": snappedf(_mean("draws"), 0.1),
		"objects": snappedf(_mean("objects"), 0.1),
		"triangles": snappedf(_mean("tris"), 1.0),
		"gpu_ms": snappedf(_mean("gpu"), 0.001),
		"cpu_render_ms": snappedf(_mean("cpu"), 0.001),
		"renderer": RenderingServer.get_video_adapter_name(),
		"glow_levels": _glow_levels,
	}
	var json := JSON.stringify(out)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__bench = %s;" % json)
	print("COSMETIC_FX ", json)
	if not OS.has_feature("web"):
		get_tree().quit()


## The command line's arguments (after `--`), and in a browser the page's query as well.
func _parse_args() -> Dictionary:
	var parsed := {}
	for raw in OS.get_cmdline_user_args():
		var parts := String(raw).trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval(QUERY))
		for pair in query.split("&", false):
			var parts := pair.split("=", true, 1)
			parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
