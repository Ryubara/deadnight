class_name MenuStage
extends Node3D
## The lot at night behind the main menu: the movie screen glowing over rows of parked cars, lamps,
## fog, a fence with the dead walking beyond it, and the player's soldier in front, in the saved
## look, holding the showcase weapon. Built from the game's own models and materials, in code, so a
## test can make one without a scene.
##
## It is cheap on purpose (docs/research/main-menu.md): no shadows, no navigation mesh, no physics,
## instanced props, and the dead are a loop of waypoints and a clip. Time is the clock `advance`
## accumulates, not the engine's, so captures and tests repeat.

## Where the movie screen's frame stands, its scale, and its picture's size and height (metres).
const SCREEN_AT := Vector3(0.0, 0.0, -38.0)
const SCREEN_SCALE := 0.72
const SCREEN_FACE := Vector2(23.0, 8.6)
const SCREEN_FACE_Y := 7.2
## The fence the dead walk behind.
const FENCE_Z := -16.5
const FENCE_PIECE := 2.13
const FENCE_HALF_SPAN := 16.0
## The dead: look, metres beyond the fence, the loop's two ends along x, and the pace.
const DEAD := [
	[&"walker", 2.4, -10.0, 4.0, 0.62],
	[&"greaser", 5.0, 14.0, 2.0, 0.55],
	[&"usher", 3.4, 3.0, 15.0, 0.7],
	[&"farmhand", 7.0, 10.0, -8.0, 0.5],
	[&"walker", 4.4, 16.0, 6.0, 0.58],
]
## Seconds between the dead's starts along their loops, so they are not in step.
const DEAD_STAGGER := 6.0
const CAR_PAINTS: Array[String] = ["red", "blue", "green", "yellow", "cream"]
const GLOW_SHADER := preload("res://world/drive_in/glow.gdshader")
const SCREEN_SHADER := preload("res://ui/stage/menu_screen.gdshader")
const SKY_SHADER := preload("res://world/drive_in/night_sky.gdshader")
const GROUND := preload("res://assets/lot/materials/field_ground.tres")
const OUTSKIRTS := preload("res://assets/lot/materials/outskirts.tres")
const LINE_PAINT := preload("res://assets/lot/materials/line_paint.tres")
const FENCE := preload("res://assets/props/fence_long.gltf")
const STREET_LIGHT := preload("res://assets/props/street_light.gltf")
const SCREEN_FRAME := preload("res://assets/drivein/screen_frame.gltf")
const SPEAKER_POST := preload("res://assets/drivein/speaker_post.gltf")
const TICKET_BOOTH := preload("res://assets/drivein/ticket_booth.gltf")
const COUNTER := preload("res://assets/drivein/concession_counter.gltf")

var hero: MenuHero
var camera: Camera3D
var rig: StageCameraRig
var dead: Array[MenuZombie] = []
## Whether the dead walk and the screen's picture drifts (off in a still).
var animated := true
## Extra turn the player gave the soldier by hand (Loadout), on top of the tab's pose, in radians.
var hero_turn := 0.0

var _clock := 0.0
var _screen_material: ShaderMaterial
var _built := false


func _ready() -> void:
	build()


## Builds the lot. Does nothing the second time.
func build() -> void:
	if _built:
		return
	_built = true
	_add_environment()
	_add_ground()
	_add_screen()
	_add_cars()
	_add_fixtures()
	_add_lamps()
	_add_fence_and_dead()
	_add_hero()
	_add_camera()
	rig.step(0.0)


## Seconds of stage time so far.
func clock() -> float:
	return _clock


## Moves the stage `delta` seconds on: the camera, the screen's picture, the idle and the dead.
func advance(delta: float) -> void:
	_clock += delta
	rig.step(delta)
	hero.face(rig.hero_yaw() + hero_turn)
	# The soldier is posed on every step, a still's included (a step of 0 seconds): his arms aim
	# along his front in the world, and the idle clip has to have been applied once.
	hero.advance(delta if animated else 0.0)
	if animated:
		_screen_material.set_shader_parameter(&"phase", _clock)
		for zombie in dead:
			zombie.advance(delta)


## Turns the camera to a tab.
func show_tab(tab: MenuTab.Id, cut := false) -> void:
	rig.go_to(tab, cut)


## Dresses the soldier.
func show_look(look: CharacterLook, weapon_id: StringName) -> void:
	hero.show_look(look, weapon_id)
	hero.face(rig.hero_yaw() + hero_turn)
	hero.advance(0.0)


func _add_environment() -> void:
	var tokens := UITokens.active()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter(&"moon_direction", Vector3(0.3011, 0.6222, -0.7226))
	sky_material.set_shader_parameter(&"zenith_color", Color(0.006, 0.012, 0.045))
	sky_material.set_shader_parameter(&"mid_color", Color(0.012, 0.026, 0.075))
	sky_material.set_shader_parameter(&"horizon_color", Color(0.030, 0.052, 0.125))
	sky_material.set_shader_parameter(&"screen_glow_color", Color(0.07, 0.11, 0.2))
	sky_material.set_shader_parameter(&"ground_color", Color(0.012, 0.024, 0.066))
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.302, 0.361, 0.549)
	environment.ambient_light_energy = 0.34
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.086, 0.133, 0.290)
	environment.fog_density = 0.011
	environment.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.name = "Environment"
	world.environment = environment
	add_child(world)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.616, 0.706, 0.910)
	moon.light_energy = 0.36
	moon.rotation_degrees = Vector3(-38.0, 150.0, 0.0)
	add_child(moon)
	# The key is the sign's warm tube, high and in front; the rim is the screen's cold light behind.
	var key := SpotLight3D.new()
	key.name = "Key"
	key.light_color = tokens.accent_bright
	key.light_energy = 5.0
	key.spot_range = 16.0
	key.spot_angle = 30.0
	key.position = Vector3(2.6, 5.2, 4.4)
	add_child(key)
	key.look_at(Vector3(0.0, 0.9, 0.0))
	var rim := OmniLight3D.new()
	rim.name = "Rim"
	rim.light_color = Color(0.45, 0.62, 1.0)
	rim.light_energy = 2.2
	rim.omni_range = 9.0
	rim.position = Vector3(-2.4, 2.4, -3.2)
	add_child(rim)
	# The screen's light on the lot: one cold lamp in front of it reaches the rows of cars.
	var cold := OmniLight3D.new()
	cold.name = "ScreenLight"
	cold.light_color = Color(0.5, 0.64, 0.95)
	cold.light_energy = 1.6
	cold.omni_range = 34.0
	cold.omni_attenuation = 1.2
	cold.position = Vector3(0.0, 6.0, SCREEN_AT.z + 5.0)
	add_child(cold)


func _add_ground() -> void:
	var near := MeshInstance3D.new()
	near.name = "Lot"
	var plane := PlaneMesh.new()
	plane.size = Vector2(70.0, 90.0)
	plane.material = GROUND
	near.mesh = plane
	near.position = Vector3(0.0, 0.0, -18.0)
	near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(near)
	var far := MeshInstance3D.new()
	far.name = "Outskirts"
	var wide := PlaneMesh.new()
	wide.size = Vector2(320.0, 320.0)
	wide.material = OUTSKIRTS
	far.mesh = wide
	far.position = Vector3(0.0, -0.05, -40.0)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)
	# Parking lines between the car spaces of the two rows.
	var line := BoxMesh.new()
	line.size = Vector3(0.12, 0.02, 5.0)
	line.material = LINE_PAINT
	var spots: Array[Transform3D] = []
	for row_z: float in [-8.0, -13.5]:
		for index in range(-8, 9):
			spots.append(Transform3D(Basis(), Vector3(index * 2.6 - 1.3, 0.012, row_z)))
	var lines := MultiMesh.new()
	lines.transform_format = MultiMesh.TRANSFORM_3D
	lines.mesh = line
	lines.instance_count = spots.size()
	for index in spots.size():
		lines.set_instance_transform(index, spots[index])
	var line_node := MultiMeshInstance3D.new()
	line_node.name = "ParkingLines"
	line_node.multimesh = lines
	line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line_node)


func _add_screen() -> void:
	var frame := SCREEN_FRAME.instantiate() as Node3D
	frame.name = "ScreenFrame"
	frame.position = SCREEN_AT
	frame.scale = Vector3.ONE * SCREEN_SCALE
	add_child(frame)
	_screen_material = ShaderMaterial.new()
	_screen_material.shader = SCREEN_SHADER
	var quad := QuadMesh.new()
	quad.size = SCREEN_FACE
	var face := MeshInstance3D.new()
	face.name = "ScreenFace"
	face.mesh = quad
	face.material_override = _screen_material
	face.position = SCREEN_AT + Vector3(0.0, SCREEN_FACE_Y, 0.9)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(face)
	var spill_at := Vector3(0.0, 0.05, SCREEN_AT.z + 12.0)
	add_child(_glow_pool(spill_at, Vector2(44.0, 24.0), Color(0.45, 0.58, 0.9), 0.55, 1.5))


func _add_cars() -> void:
	# Two rows facing the screen with a gap here and there, so the rows are not a wall, and a pair
	# at the edges of the foreground so the near corners have something in them.
	var index := 0
	for row in 2:
		var z := -8.0 - row * 5.5
		for slot in range(-8, 8):
			# The aisle: a lane through both rows, so the screen and the dead can be seen.
			if (slot * 7 + row * 3) % 5 == 0 or (slot >= 1 and slot <= 3):
				continue
			_add_car(Vector3(slot * 2.6, 0.0, z), 0.0, index)
			index += 1
			if slot % 3 == 0:
				_add_post(Vector3(slot * 2.6 + 1.3, 0.0, z + 2.1))
	_add_car(Vector3(-10.0, 0.0, 1.5), deg_to_rad(64.0), 2)


func _add_car(at: Vector3, yaw: float, paint: int) -> void:
	var path := "res://assets/props/car_%s.gltf" % CAR_PAINTS[posmod(paint, CAR_PAINTS.size())]
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.position = at
	model.rotation.y = yaw
	add_child(model)


func _add_post(at: Vector3) -> void:
	var post := SPEAKER_POST.instantiate() as Node3D
	post.position = at
	add_child(post)


## The booth at the left and the counter at the right: what the Shop and the
## Challenges camera turn to.
func _add_fixtures() -> void:
	var booth := TICKET_BOOTH.instantiate() as Node3D
	booth.name = "TicketBooth"
	booth.position = Vector3(-7.4, 0.0, -4.5)
	booth.rotation.y = deg_to_rad(28.0)
	add_child(booth)
	var counter := COUNTER.instantiate() as Node3D
	counter.name = "Counter"
	counter.position = Vector3(8.6, 0.0, -5.0)
	counter.rotation.y = deg_to_rad(-24.0)
	counter.scale = Vector3.ONE * 0.7
	add_child(counter)


func _add_lamps() -> void:
	_add_lamp(Vector3(-5.6, 0.0, -2.4), 90.0)
	_add_lamp(Vector3(6.2, 0.0, -9.5), -90.0)


func _add_lamp(at: Vector3, yaw: float) -> void:
	var post := STREET_LIGHT.instantiate() as Node3D
	post.position = at
	post.rotation_degrees.y = yaw
	add_child(post)
	var warm := Color(1.0, 0.72, 0.4)
	var head := at + Vector3(0.0, 4.3, 0.0)
	var light := OmniLight3D.new()
	light.light_color = warm
	light.light_energy = 2.4
	light.omni_range = 11.0
	light.omni_attenuation = 1.4
	light.position = head
	add_child(light)
	var halo := _glow_pool(head, Vector2(2.6, 2.6), Color(1.0, 0.68, 0.3), 0.9, 2.5)
	(halo.material_override as ShaderMaterial).set_shader_parameter(&"billboard", true)
	(halo.mesh as QuadMesh).orientation = PlaneMesh.FACE_Z
	add_child(halo)
	add_child(_glow_pool(at + Vector3(0.0, 0.04, 0.0), Vector2(15.0, 15.0), warm, 0.5, 1.6))


## An additive quad that fakes a pool of light (the lot's own `glow.gdshader`).
func _glow_pool(
	at: Vector3, size: Vector2, tint: Color, energy: float, falloff: float
) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.render_priority = 1
	material.set_shader_parameter(&"tint", tint)
	material.set_shader_parameter(&"energy", energy)
	material.set_shader_parameter(&"falloff", falloff)
	var quad := QuadMesh.new()
	quad.size = size
	quad.orientation = PlaneMesh.FACE_Y
	var pool := MeshInstance3D.new()
	pool.mesh = quad
	pool.material_override = material
	pool.position = at
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return pool


func _add_fence_and_dead() -> void:
	var count := int(ceil(FENCE_HALF_SPAN * 2.0 / FENCE_PIECE))
	for index in count:
		var piece := FENCE.instantiate() as Node3D
		piece.position = Vector3(-FENCE_HALF_SPAN + index * FENCE_PIECE, 0.0, FENCE_Z)
		add_child(piece)
	var index := 0
	for entry: Array in DEAD:
		var row_z: float = FENCE_Z - float(entry[1])
		var loop: Array[Vector3] = [
			Vector3(float(entry[2]), 0.0, row_z), Vector3(float(entry[3]), 0.0, row_z - 1.4)
		]
		var zombie := MenuZombie.make(entry[0], loop, float(entry[4]), DEAD_STAGGER * index)
		add_child(zombie)
		dead.append(zombie)
		index += 1


func _add_hero() -> void:
	hero = MenuHero.new()
	hero.name = "Hero"
	add_child(hero)
	var shade := QuadMesh.new()
	shade.size = Vector2(1.5, 1.5)
	shade.orientation = PlaneMesh.FACE_Y
	var shade_material := StandardMaterial3D.new()
	shade_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var fade := Gradient.new()
	fade.set_color(0, Color(0, 0, 0, 0.55))
	fade.set_color(1, Color(0, 0, 0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = fade
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	shade_material.albedo_texture = texture
	var contact := MeshInstance3D.new()
	contact.name = "ContactShade"
	contact.mesh = shade
	contact.material_override = shade_material
	contact.position = Vector3(0.0, 0.02, 0.0)
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(contact)


func _add_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.far = 260.0
	camera.near = 0.1
	add_child(camera)
	camera.current = true
	rig = StageCameraRig.new(camera)
	rig.set_reduced(UIMotion.reduced)
	rig.go_to(MenuTab.Id.PLAY, true)
