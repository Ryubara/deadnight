class_name PrizeCrane
extends Node3D
## The drive-in's prize crane, built from boxes and spheres so it needs no asset: a red cabinet with
## a glass case, a pile of plush prizes, a claw on a gantry, a marquee, and above the glass a stage
## where weapons cycle and the chosen one floats. A light beam over it says where it stands.
##
## It is drawn only from what the server says (`show_state`): the stage (`CraneState.Stage`), the
## seconds left in it and the prize held out. The claw's dig, the cycling, the lift, the dud and
## the power-down are all functions of those, so a late joiner sees the same crane.
##
## Local space: the front of the glass is +Z, the floor y = 0. Original design, no copied asset.

const WIDTH := 1.8
const DEPTH := 1.4
const GLASS_TOP := 2.0
const STAGE_Y := 3.25
const PRIZE_COLOURS: Array[Color] = [
	Color(0.85, 0.3, 0.35),
	Color(0.95, 0.75, 0.25),
	Color(0.35, 0.65, 0.8),
	Color(0.55, 0.8, 0.45),
	Color(0.8, 0.5, 0.75),
]
const CABINET := Color(0.62, 0.1, 0.1)
const CREAM := Color(0.92, 0.85, 0.66)
const GLASS := Color(0.55, 0.8, 0.9, 0.16)
const BEAM_HEIGHT := 36.0
## The weapon models the crane shows, by shop id; a prize with none is drawn as a plain silhouette
## (`_silhouette`). The tommy gun is the `smg`.
const MODELS := {
	&"weapon_rifle": "res://assets/weapons/lever_rifle/lever_rifle.glb",
	&"weapon_shotgun": "res://assets/weapons/double_shotgun/double_shotgun.glb",
	&"weapon_smg": "res://assets/weapons/tommy_gun/tommy_gun.glb",
	&"weapon_flare_gun": "res://assets/weapons/flare_gun/flare_gun.glb",
	&"weapon_baseball_bat": "res://assets/weapons/baseball_bat/baseball_bat.glb",
	&"weapon_fire_axe": "res://assets/weapons/fire_axe/fire_axe.glb",
	&"weapon_pistol": "res://assets/weapons/revolver/revolver.glb",
	&"weapon_crowbar": "res://assets/weapons/crowbar/crowbar.glb",
	# The revolver again until the pistol model of #786 lands.
	&"weapon_dual_pistols": "res://assets/weapons/revolver/revolver.glb",
}
## How long a model is drawn on the stage, in metres; the others use `MODEL_LENGTH`. The flare gun
## is a pistol and stays small beside the long guns.
const MODEL_LENGTH := 1.5
const MODEL_LENGTHS := {
	&"weapon_flare_gun": 0.8,
	&"weapon_baseball_bat": 1.3,
	&"weapon_fire_axe": 1.3,
	&"weapon_pistol": 0.8,
	&"weapon_crowbar": 1.3,
	&"weapon_dual_pistols": 0.8,
}
## The cycling starts this quick (seconds between weapons) and slows to the slow one.
const CYCLE_FAST := 0.07
const CYCLE_SLOW := 0.46
## Seconds the chosen weapon takes to rise from the claw to the stage.
const RISE_SECONDS := 0.9
## The prize blinks in the last seconds of the grab window.
const BLINK_BELOW := 3.0
const REST_CABLE := 0.25
const DEEP_CABLE := 1.05

var spin_seconds := 4.5
var grab_seconds := 12.0
var leave_seconds := 4.0

var _pool: Array[StringName] = []
var _models: Dictionary = {}
var _stage_node: Node3D
var _dud: Node3D
var _carriage: Node3D
var _cable: MeshInstance3D
var _claw: Node3D
var _prongs: Array[Node3D] = []
var _marquee: MeshInstance3D
var _beam: MeshInstance3D
var _light: OmniLight3D
var _sparks: CPUParticles3D
var _glow_material := StandardMaterial3D.new()
var _beam_material := ShaderMaterial.new()
var _clock := 0.0
var _cycle_left := 0.0
var _cycle_index := 0
var _shown := &""
var _phase := 0
var _lit := 1.0


## `pool` is the shop ids the display cycles through; the times come from `CraneTuning`.
func configure(tuning: CraneTuning, pool: Array[StringName]) -> void:
	spin_seconds = tuning.spin_seconds
	grab_seconds = tuning.grab_seconds
	leave_seconds = tuning.breakdown_seconds
	_pool = pool
	_build()


## Draws one frame of the crane: `crane` is the server frame's `crane` ({stage, left, weapon, ...}),
## `delta` the seconds since the last call.
func show_state(crane: Dictionary, delta: float) -> void:
	_clock += delta
	_phase = int(crane.get("stage", CraneState.Stage.READY))
	var left := float(crane.get("left", 0.0))
	var weapon := StringName(crane.get("weapon", &""))
	match _phase:
		CraneState.Stage.SPIN:
			_spin(1.0 - left / maxf(spin_seconds, 0.01), delta)
		CraneState.Stage.GRAB:
			_grab(weapon, grab_seconds - left, left)
		CraneState.Stage.LEAVING:
			_leave(1.0 - left / maxf(leave_seconds, 0.01))
		_:
			_rest()
	_light.light_energy = 1.1 * _lit
	_glow_material.emission_energy_multiplier = 1.4 * _lit
	_beam.visible = _phase != CraneState.Stage.LEAVING or _lit > 0.05
	_beam_material.set_shader_parameter(&"strength", _lit)


## The weapon on the stage now (`&""` for none), for tests and tools.
func shown_weapon() -> StringName:
	return _shown if _stage_node.visible else &""


func dud_visible() -> bool:
	return _dud.visible


func beam_visible() -> bool:
	return _beam.visible


func _rest() -> void:
	_lit = 1.0
	_sparks.emitting = false
	_dud.visible = false
	_show_weapon(&"")
	_place_claw(0.0, REST_CABLE + 0.03 * sin(_clock * 1.3), 0.7)


## The dig: sweep over the pile, drop, close, lift; the weapons cycle, slowing down.
func _spin(t: float, delta: float) -> void:
	_lit = 1.0
	_sparks.emitting = false
	_dud.visible = false
	var sweep := smoothstep(0.0, 0.3, t)
	var drop := smoothstep(0.25, 0.5, t) - smoothstep(0.65, 0.9, t)
	var closing := smoothstep(0.5, 0.62, t)
	_place_claw(lerpf(-0.45, 0.25, sweep), lerpf(REST_CABLE, DEEP_CABLE, drop), 1.0 - closing * 0.8)
	_cycle_left -= delta
	if _cycle_left <= 0.0 and not _pool.is_empty():
		_cycle_index += 1
		_show_weapon(_pool[_cycle_index % _pool.size()])
		_cycle_left = lerpf(CYCLE_FAST, CYCLE_SLOW, t * t)
	_float(_stage_node, 1.0)


## The claw lifts the prize and it floats on the stage for the window; it blinks as it runs out.
func _grab(weapon: StringName, elapsed: float, left: float) -> void:
	_lit = 1.0
	_sparks.emitting = false
	_dud.visible = false
	_show_weapon(weapon)
	var rise := clampf(elapsed / RISE_SECONDS, 0.0, 1.0)
	_place_claw(lerpf(0.25, 0.0, rise), lerpf(DEEP_CABLE * 0.5, REST_CABLE, rise), 0.2)
	_float(_stage_node, rise)
	_stage_node.visible = left > BLINK_BELOW or int(_clock * 7.0) % 2 == 0


## The dud: a moth-eaten plush on the stage, sparks, a flicker, then the power goes.
func _leave(t: float) -> void:
	_show_weapon(&"")
	_dud.visible = true
	_dud.position = Vector3(0.0, STAGE_Y + 0.1 * sin(_clock * 3.0), 0.0)
	_dud.rotation.y = _clock * 1.1
	_sparks.emitting = t < 0.8
	var flicker := 0.5 + 0.5 * sin(_clock * 37.0) * sin(_clock * 11.0)
	_lit = clampf(1.0 - smoothstep(0.55, 0.95, t), 0.0, 1.0) * (0.45 + 0.55 * flicker)
	_place_claw(0.1, lerpf(0.6, REST_CABLE, t), 1.0)


func _float(node: Node3D, rise: float) -> void:
	var from_pile := (1.0 - rise) * -1.1
	node.position = Vector3(0.0, STAGE_Y + from_pile + 0.08 * sin(_clock * 2.2), 0.0)
	node.rotation.y = _clock * 0.9
	node.visible = true


func _place_claw(x: float, cable: float, open: float) -> void:
	_carriage.position = Vector3(x, GLASS_TOP - 0.08, 0.0)
	_cable.scale = Vector3(1.0, cable, 1.0)
	_cable.position = Vector3(0.0, -cable * 0.5, 0.0)
	_claw.position = Vector3(0.0, -cable, 0.0)
	for i in _prongs.size():
		var spread := deg_to_rad(10.0 + 35.0 * open)
		_prongs[i].rotation = Vector3(0.0, TAU * i / _prongs.size(), 0.0)
		(_prongs[i].get_child(0) as Node3D).rotation.z = -spread


## Shows the model of `weapon_id` on the stage (nothing for `&""`).
func _show_weapon(weapon_id: StringName) -> void:
	if weapon_id == _shown:
		return
	_shown = weapon_id
	for id: StringName in _models:
		(_models[id] as Node3D).visible = id == weapon_id
	_stage_node.visible = weapon_id != &""


# --- Building ---


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_prongs.clear()
	_models.clear()
	_cabinet()
	_pile()
	_gantry()
	_stage()
	_dud_plush()
	_effects()
	_cycle_left = 0.0
	_shown = &"?"
	_show_weapon(&"")


func _cabinet() -> void:
	_box("Base", Vector3(WIDTH, 0.9, DEPTH), Vector3(0.0, 0.45, 0.0), CABINET)
	_box("Plinth", Vector3(WIDTH + 0.08, 0.1, DEPTH + 0.08), Vector3(0.0, 0.05, 0.0), CREAM)
	_box("Chute", Vector3(0.5, 0.3, 0.06), Vector3(0.55, 0.45, DEPTH / 2.0 + 0.02), CREAM)
	var roof := _box(
		"Marquee", Vector3(WIDTH + 0.1, 0.55, DEPTH + 0.1), Vector3(0, 2.3, 0), CABINET
	)
	_marquee = roof
	_box("Cornice", Vector3(WIDTH + 0.2, 0.08, DEPTH + 0.2), Vector3(0.0, 2.6, 0.0), CREAM)
	var sign_label := Label3D.new()
	sign_label.text = "PRIZE CRANE"
	sign_label.font_size = 64
	sign_label.pixel_size = 0.0045
	sign_label.modulate = Color(1.0, 0.92, 0.6)
	sign_label.outline_size = 16
	sign_label.outline_modulate = Color(0.25, 0.04, 0.04)
	sign_label.position = Vector3(0.0, 2.3, DEPTH / 2.0 + 0.07)
	add_child(sign_label)
	# Glass: four panes round the case, see-through.
	var pane := StandardMaterial3D.new()
	pane.albedo_color = GLASS
	pane.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pane.cull_mode = BaseMaterial3D.CULL_DISABLED
	var height := GLASS_TOP - 0.9
	for side in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var along_x: bool = absf(side.z) > 0.5
		var size := Vector3(WIDTH if along_x else 0.03, height, 0.03 if along_x else DEPTH)
		var node := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		node.mesh = mesh
		node.material_override = pane
		var offset := Vector3(side.x * WIDTH / 2.0, 0.0, side.z * DEPTH / 2.0)
		node.position = Vector3(offset.x, 0.9 + height / 2.0, offset.z)
		add_child(node)
	# No collision: this is a drawing. The wall is the world's (`CraneBlock`), the same on a server.


## Plush prizes in the case: spheres with ears, in the five colours, from a fixed seed.
func _pile() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1958
	for i in 16:
		var colour := PRIZE_COLOURS[i % PRIZE_COLOURS.size()]
		var at := Vector3(
			rng.randf_range(-WIDTH * 0.38, WIDTH * 0.38),
			0.98 + rng.randf_range(0.0, 0.22),
			rng.randf_range(-DEPTH * 0.32, DEPTH * 0.32)
		)
		var radius := rng.randf_range(0.13, 0.19)
		_sphere("Plush%d" % i, radius, at, colour)
		_sphere("Ear%dA" % i, radius * 0.4, at + Vector3(-radius * 0.6, radius * 0.9, 0), colour)
		_sphere("Ear%dB" % i, radius * 0.4, at + Vector3(radius * 0.6, radius * 0.9, 0), colour)


func _gantry() -> void:
	_box("Rail", Vector3(WIDTH - 0.1, 0.05, 0.05), Vector3(0.0, GLASS_TOP - 0.03, 0.0), CREAM)
	_carriage = Node3D.new()
	add_child(_carriage)
	var box := MeshInstance3D.new()
	var carriage_mesh := BoxMesh.new()
	carriage_mesh.size = Vector3(0.22, 0.1, 0.16)
	box.mesh = carriage_mesh
	box.material_override = _plain(CREAM)
	_carriage.add_child(box)
	_cable = MeshInstance3D.new()
	var cable_mesh := CylinderMesh.new()
	cable_mesh.top_radius = 0.012
	cable_mesh.bottom_radius = 0.012
	cable_mesh.height = 1.0
	_cable.mesh = cable_mesh
	_cable.material_override = _plain(Color(0.15, 0.15, 0.17))
	_carriage.add_child(_cable)
	_claw = Node3D.new()
	_carriage.add_child(_claw)
	var hub := MeshInstance3D.new()
	var hub_mesh := SphereMesh.new()
	hub_mesh.radius = 0.06
	hub_mesh.height = 0.12
	hub.mesh = hub_mesh
	hub.material_override = _plain(Color(0.7, 0.7, 0.75))
	_claw.add_child(hub)
	for i in 3:
		var pivot := Node3D.new()
		var arm := Node3D.new()
		var finger := MeshInstance3D.new()
		var finger_mesh := BoxMesh.new()
		finger_mesh.size = Vector3(0.025, 0.22, 0.025)
		finger.mesh = finger_mesh
		finger.position = Vector3(0.0, -0.11, 0.0)
		finger.material_override = _plain(Color(0.7, 0.7, 0.75))
		arm.add_child(finger)
		arm.position = Vector3(0.05, 0.0, 0.0)
		pivot.add_child(arm)
		_claw.add_child(pivot)
		_prongs.append(pivot)


## The stage above the marquee: a dim plinth where the weapons cycle and the prize floats.
func _stage() -> void:
	_stage_node = Node3D.new()
	_stage_node.position = Vector3(0.0, STAGE_Y, 0.0)
	add_child(_stage_node)
	for id in _pool:
		var holder := Node3D.new()
		var scene: PackedScene = load(MODELS[id]) if MODELS.has(id) else null
		if scene != null:
			var model := scene.instantiate() as Node3D
			holder.add_child(model)
			_fit(model, MODEL_LENGTHS.get(id, MODEL_LENGTH))
		else:
			holder.add_child(_silhouette(id))
		holder.visible = false
		_stage_node.add_child(holder)
		_models[id] = holder


## A plain stand-in for a weapon with no model yet: a body, a barrel and a grip, in one colour.
func _silhouette(id: StringName) -> Node3D:
	var node := Node3D.new()
	var small := id == &"weapon_flare_gun"
	var colour := Color(0.95, 0.5, 0.15) if small else Color(0.3, 0.38, 0.3)
	var length := 0.7 if small else 1.3
	_part(node, Vector3(length, 0.12, 0.07), Vector3.ZERO, colour)
	_part(node, Vector3(length * 0.55, 0.05, 0.05), Vector3(length * 0.7, 0.01, 0.0), colour)
	_part(node, Vector3(0.09, 0.2, 0.06), Vector3(-length * 0.3, -0.14, 0.0), colour.darkened(0.2))
	if not small:
		_part(
			node, Vector3(0.08, 0.3, 0.06), Vector3(length * 0.05, -0.2, 0.0), colour.darkened(0.3)
		)
	return node


## The dud prize: a plush bear with moth holes, one ear half off and an eye hanging by a thread.
func _dud_plush() -> void:
	_dud = Node3D.new()
	_dud.visible = false
	add_child(_dud)
	var fur := Color(0.5, 0.4, 0.3)
	_part_sphere(_dud, 0.26, Vector3.ZERO, fur)
	_part_sphere(_dud, 0.19, Vector3(0.0, 0.3, 0.0), fur)
	_part_sphere(_dud, 0.08, Vector3(-0.15, 0.46, 0.0), fur)
	_part_sphere(_dud, 0.08, Vector3(0.2, 0.42, 0.0), fur.darkened(0.2))
	_part_sphere(_dud, 0.035, Vector3(-0.07, 0.33, 0.17), Color(0.05, 0.05, 0.05))
	_part_sphere(_dud, 0.035, Vector3(0.1, 0.27, 0.17), Color(0.05, 0.05, 0.05))
	for hole in [Vector3(0.1, 0.05, 0.24), Vector3(-0.12, -0.08, 0.23), Vector3(0.0, -0.17, 0.2)]:
		_part_sphere(_dud, 0.045, hole, Color(0.04, 0.03, 0.03))
	_part_sphere(_dud, 0.09, Vector3(0.27, -0.05, 0.0), fur.darkened(0.1))


func _effects() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.8, 0.5)
	_light.omni_range = 5.0
	_light.position = Vector3(0.0, 1.6, DEPTH / 2.0 + 0.4)
	add_child(_light)
	_glow_material = StandardMaterial3D.new()
	_glow_material.albedo_color = Color(1.0, 0.9, 0.6)
	_glow_material.emission_enabled = true
	_glow_material.emission = Color(1.0, 0.85, 0.5)
	_marquee.material_override = _glow_material
	_sparks = CPUParticles3D.new()
	_sparks.amount = 36
	_sparks.lifetime = 0.6
	_sparks.explosiveness = 0.2
	_sparks.direction = Vector3(0.0, 1.0, 0.4)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 1.5
	_sparks.initial_velocity_max = 3.5
	_sparks.gravity = Vector3(0.0, -7.0, 0.0)
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.0
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.02
	spark_mesh.height = 0.04
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = Color(1.0, 0.85, 0.4)
	spark_mesh.material = spark_material
	_sparks.mesh = spark_mesh
	_sparks.position = Vector3(0.0, 1.9, DEPTH / 2.0)
	_sparks.emitting = false
	add_child(_sparks)
	_beam = _make_beam()
	add_child(_beam)


## The light beam: an open cone, brightest at the foot, fading up, added to the picture.
func _make_beam() -> MeshInstance3D:
	var shader := Shader.new()
	shader.code = (
		"""
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.45, 0.8, 1.0, 0.32);
uniform float strength = 1.0;
varying float up;
void vertex() { up = clamp(0.5 + VERTEX.y / %f, 0.0, 1.0); }
void fragment() {
	float fade = pow(1.0 - up, 1.4);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * fade * strength;
}
"""
		% BEAM_HEIGHT
	)
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = shader
	var cone := CylinderMesh.new()
	cone.top_radius = 0.18
	cone.bottom_radius = 0.95
	cone.height = BEAM_HEIGHT
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var node := MeshInstance3D.new()
	node.mesh = cone
	node.material_override = _beam_material
	node.position = Vector3(0.0, BEAM_HEIGHT / 2.0, 0.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


# --- Small builders ---


func _plain(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.7
	return material


func _box(node_name: String, size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _plain(colour)
	node.position = at
	add_child(node)
	return node


func _sphere(node_name: String, radius: float, at: Vector3, colour: Color) -> void:
	var node := _part_sphere(self, radius, at, colour)
	node.name = node_name


func _part_sphere(parent: Node3D, radius: float, at: Vector3, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	node.mesh = mesh
	node.material_override = _plain(colour)
	node.position = at
	parent.add_child(node)
	return node


func _part(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _plain(colour)
	node.position = at
	parent.add_child(node)


## Scales and centres a model so its longest side is `length` metres, lying along X.
func _fit(model: Node3D, length: float) -> void:
	var box := _bounds(model, Transform3D.IDENTITY)
	if box.size == Vector3.ZERO:
		return
	var turn := box.size.z > box.size.x
	var longest := maxf(box.size.x, box.size.z) if turn else box.size.x
	longest = maxf(longest, box.size.y)
	var factor := length / maxf(longest, 0.001)
	var centre := box.get_center()
	# A gun lies along X; a melee weapon is modelled standing (its head up), so it is laid down
	# with the head toward -X, where a gun's muzzle is.
	var upright := box.size.y > maxf(box.size.x, box.size.z)
	var lay := (
		Basis(Vector3.BACK, PI * 0.5) if upright else Basis(Vector3.UP, PI * 0.5 if turn else 0.0)
	)
	model.basis = lay * Basis.from_scale(Vector3.ONE * factor)
	model.position = -(model.basis * centre)


## The box round every mesh under `node`, in the space of the model's root.
func _bounds(node: Node, to_root: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	if node is MeshInstance3D:
		box = to_root * (node as MeshInstance3D).get_aabb()
		first = false
	for child in node.get_children():
		if child is Node3D:
			var inner := _bounds(child, to_root * (child as Node3D).transform)
			if inner.size != Vector3.ZERO:
				box = inner if first else box.merge(inner)
				first = false
	return box
