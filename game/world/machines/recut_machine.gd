class_name RecutMachine
extends Node3D
## The re-cut: a film-editing bench in the projection booth that re-cuts the weapon you hold
## ([upgrades](docs/design/upgrades.md)). A cast-iron cabinet with two film reels on its tower, a
## strip of sprocketed film running along its front, a cradle under a press with a hot head, and a
## row of ready lamps. Idle, the reels turn slowly and the film creeps. A re-cut (`play`) lays the
## weapon in the cradle, spins the reels up, drops the press, and at the blow throws a flash, a ring
## and sparks in the re-cut's cold blue (`RecutStyle`) while the weapon's skin sweeps on from the
## butt to the muzzle (`RecutSkin`: the look it keeps for as long as it is held); then it is lifted
## and shown, with the lamps chasing.
##
## Built from primitives (`MachineParts`), drawn from fixed steps (`advance`), so a test can step
## it and a late joiner sees an idle machine. Local space: the front is +Z, the floor y = 0.
## Original design, no copied asset.

signal pressed

## Every re-cut machine is in this group, so the night finds it (`MachineView`).
const GROUP := &"recut_machines"

const WIDTH := 3.0
const DEPTH := 2.4
const IRON := Color(0.15, 0.19, 0.2)
const IRON_LIGHT := Color(0.26, 0.32, 0.34)
const BRASS := Color(0.8, 0.6, 0.24)
const CREAM := Color(0.92, 0.85, 0.66)
const AMBER := Color(1.0, 0.68, 0.2)
const HOT := Color(1.0, 0.42, 0.1)
## The light of the blow once the re-cut is struck: the style's cold, lifted toward white.
const COLD_LIGHT := Color(0.45, 0.8, 1.0)
## Seconds the skin takes to sweep over the weapon on the cradle, from the blow.
const SWEEP := 0.55
## The skin's flash over the weapon at the blow (the style's cold, times this).
const SKIN_FLASH := 3.0
## The ring that leaves the blow: it grows from `RING_FROM` to `RING_TO` metres across in
## `RING_SECONDS`.
const RING_FROM := 0.3
const RING_TO := 3.2
const RING_SECONDS := 0.6
## Where the weapon lies, and its length on the cradle.
const CRADLE := Vector3(0.0, 1.22, 0.45)
const WEAPON_LENGTH := 1.45
## The press' head height up and down (its middle), metres above the floor.
const RAM_UP := 2.15
const RAM_DOWN := 1.72
## The re-cut in seconds: the weapon is laid down, the press drops and strikes at `STRIKE`, rises,
## and the weapon is lifted and shown until the end.
const LAY := 0.4
const STRIKE := 0.8
const RISE := 1.0
const DISPLAY := 1.6
const DURATION := 2.4
## Reel turn in radians a second, idle and at the top of a re-cut.
const REEL_IDLE := 0.5
const REEL_FAST := 7.0
## Film creep in strip widths a second, idle and fast.
const FILM_IDLE := 0.04
const FILM_FAST := 0.9
const FLASH_DECAY := 6.0
const LAMP_COUNT := 5

var _clock := 0.0
## Seconds into a re-cut, or -1 when the machine is idle.
var _t := -1.0
var _struck := false
var _flash := 0.0
var _reel_angle := 0.0
var _film_offset := 0.0
var _reels: Array[Node3D] = []
var _ram: Node3D
var _head_material := MachineParts.glow(HOT, 0.6)
var _film_material: StandardMaterial3D
var _lamps: Array[MeshInstance3D] = []
var _lamp_colours: Array[Color] = []
var _lamp_materials: Array[StandardMaterial3D] = []
var _light: OmniLight3D
var _spark_material: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
## Seconds since the blow while the ring grows, or -1 when it is gone.
var _ring_t := -1.0
## How far the blow has turned the machine's light cold, 0 (the booth's amber) to 1.
var _cold := 0.0
var _sparks: CPUParticles3D
var _display: Node3D
var _holders: Dictionary[StringName, Node3D] = {}
var _shown: StringName = &""
## The skin on the weapon lying on the cradle (null when none): it sweeps on at the blow.
var _skin: RecutSkin


func _ready() -> void:
	add_to_group(GROUP)
	_build()


func _physics_process(delta: float) -> void:
	advance(delta)


## Starts a re-cut of `weapon_id` (a catalogue id): it shows on the cradle for the length of it.
func play(weapon_id: StringName) -> void:
	_t = 0.0
	_struck = false
	_show(weapon_id)
	_skin = null
	if _holders.has(weapon_id):
		# The weapon lies plain on the cradle, in the skin's own material at no sweep yet.
		_skin = RecutSkin.wear(_holders[weapon_id].get_child(0) as Node3D, 0.0)


func is_playing() -> bool:
	return _t >= 0.0


## The weapon on the cradle now (`&""` for none).
func shown_weapon() -> StringName:
	return _shown


## The press' middle height now, metres above the floor.
func ram_height() -> float:
	return _ram.position.y


## The light of the last blow: 1 at the strike, falling to 0.
func flash() -> float:
	return _flash


## How far the weapon on the cradle has its skin, 0 to 1 (0 when none lies there).
func skin_reveal() -> float:
	return _skin.reveal if _skin != null else 0.0


## How far the blow has turned the machine's light and lamps cold, 0 (amber) to 1.
func coldness() -> float:
	return _cold


## The across of the last blow's ring in metres, or 0 when it is not showing.
func ring_diameter() -> float:
	return _ring.scale.x * RING_FROM if _ring != null and _ring.visible else 0.0


## Moves the machine on by `delta` seconds.
func advance(delta: float) -> void:
	_clock += delta
	var spin := REEL_IDLE
	var creep := FILM_IDLE
	if _t >= 0.0:
		_t += delta
		_stage(_t)
		var ramp := smoothstep(0.0, LAY, _t) * (1.0 - smoothstep(DISPLAY, DURATION, _t))
		spin = lerpf(REEL_IDLE, REEL_FAST, ramp)
		creep = lerpf(FILM_IDLE, FILM_FAST, ramp)
		if _t >= DURATION:
			_t = -1.0
			_show(&"")
	else:
		_rest()
	_flash = maxf(_flash - delta * FLASH_DECAY, 0.0)
	_advance_ring(delta)
	_reel_angle += spin * delta
	_film_offset = fmod(_film_offset + creep * delta, 1.0)
	_dress()


func _stage(t: float) -> void:
	var drop := smoothstep(LAY, STRIKE, t)
	var rise := smoothstep(RISE, RISE + 0.5, t)
	_ram.position.y = (
		lerpf(RAM_UP, RAM_DOWN, drop * drop) if t < RISE else lerpf(RAM_DOWN, RAM_UP, rise)
	)
	if t >= STRIKE and not _struck:
		_struck = true
		_flash = 1.0
		_ring_t = 0.0
		_sparks.restart()
		_sparks.emitting = true
		pressed.emit()
	# The weapon: laid down in the first moments, in its new skin from the blow on, then lifted and
	# turned.
	var laid := smoothstep(0.0, LAY, t)
	var lift := smoothstep(DISPLAY, DURATION, t)
	_display.position = CRADLE + Vector3(0.0, lerpf(-0.25, 0.0, laid) + 0.4 * lift, 0.0)
	_display.rotation.y = 0.9 * lift
	_display.scale = Vector3.ONE * (lerpf(0.7, 1.0, laid) + (0.06 * _flash))
	if _skin != null:
		_skin.reveal = smoothstep(STRIKE, STRIKE + SWEEP, t)
		_skin.boost = SKIN_FLASH * _flash
	# The light turns cold at the blow and stays so while the weapon is shown, then eases back.
	_cold = smoothstep(STRIKE, STRIKE + 0.15, t) * (1.0 - smoothstep(DISPLAY, DURATION, t))


func _rest() -> void:
	_ram.position.y = RAM_UP
	_cold = 0.0


## The ring that leaves the blow: a thin ring of light on the floor of the cradle that opens out
## and fades.
func _advance_ring(delta: float) -> void:
	if _ring_t >= 0.0:
		_ring_t += delta
	var share := _ring_t / RING_SECONDS
	var on := _ring_t >= 0.0 and share < 1.0
	if _ring_t >= 0.0 and not on:
		_ring_t = -1.0
	_ring.visible = on
	if on:
		var grown := lerpf(1.0, RING_TO / RING_FROM, 1.0 - pow(1.0 - share, 3.0))
		_ring.scale = Vector3(grown, 1.0, grown)
		_ring_material.albedo_color.a = 1.0 - share


## Everything that follows the clock and the flash: the lamps, the head's heat, the lamp's light.
func _dress() -> void:
	for reel in _reels:
		reel.rotation.z = _reel_angle
	_film_material.uv1_offset.x = _film_offset
	var cold := RecutStyle.shipped().cold
	_head_material.emission = HOT.lerp(cold, _cold)
	_head_material.albedo_color = _head_material.emission
	_head_material.emission_energy_multiplier = 0.6 + 7.0 * _flash
	_light.light_color = Color(1.0, 0.72, 0.4).lerp(COLD_LIGHT, _cold)
	_light.light_energy = 0.9 + 0.1 * sin(_clock * 1.7) + 6.0 * _flash
	for i in _lamps.size():
		var lit := 0.55 + 0.1 * sin(_clock * 2.0 + float(i))
		if _t >= 0.0:
			# A chase along the row while the re-cut runs.
			var at := fmod(_t * 9.0, float(_lamps.size()))
			lit = 1.0 if absf(float(i) - at) < 1.0 else 0.15
		_lamp_materials[i].emission_energy_multiplier = lit * 2.4
		# Cold after the blow: the lamps the chase lights burn the skin's colour.
		var lamp_colour := _lamp_colours[i].lerp(cold, _cold)
		_lamp_materials[i].albedo_color = lamp_colour
		_lamp_materials[i].emission = lamp_colour


func _show(weapon_id: StringName) -> void:
	_shown = weapon_id
	for id: StringName in _holders:
		_holders[id].visible = id == weapon_id
	_display.visible = weapon_id != &""


# --- Building ---


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_reels.clear()
	_lamps.clear()
	_lamp_materials.clear()
	_lamp_colours.clear()
	_cabinet()
	_tower()
	_press()
	_film_strip()
	_lamp_row()
	_effects()
	_cradle_display()
	_show(&"")
	_stage(0.0)
	_rest()
	_dress()


func _cabinet() -> void:
	var iron := MachineParts.plain(IRON, 0.55, 0.4)
	var light_iron := MachineParts.plain(IRON_LIGHT, 0.5, 0.5)
	var brass := MachineParts.plain(BRASS, 0.35, 0.8)
	MachineParts.box(self, "Base", Vector3(WIDTH, 0.9, DEPTH), Vector3(0.0, 0.45, 0.0), iron)
	MachineParts.box(
		self, "Kick", Vector3(WIDTH + 0.1, 0.1, DEPTH + 0.1), Vector3(0.0, 0.05, 0.0), light_iron
	)
	MachineParts.box(
		self, "Top", Vector3(WIDTH + 0.04, 0.1, DEPTH + 0.04), Vector3(0.0, 0.95, 0.0), light_iron
	)
	MachineParts.box(
		self, "Lip", Vector3(WIDTH + 0.1, 0.04, DEPTH + 0.1), Vector3(0.0, 1.01, 0.0), brass
	)
	# Panel seams on the front, and two brass handles.
	for x in [-0.5, 0.5]:
		MachineParts.box(
			self, "Seam", Vector3(0.03, 0.7, 0.03), Vector3(x, 0.45, DEPTH / 2.0 + 0.01), light_iron
		)
	for x in [-1.0, 1.0]:
		MachineParts.cylinder(
			self, "Handle", 0.025, 0.4, Vector3(x, 0.3, DEPTH / 2.0 + 0.08), brass, Vector3.AXIS_X
		)


func _tower() -> void:
	var iron := MachineParts.plain(IRON, 0.55, 0.4)
	var brass := MachineParts.plain(BRASS, 0.35, 0.8)
	MachineParts.box(self, "Tower", Vector3(WIDTH, 1.6, 0.5), Vector3(0.0, 1.8, -0.95), iron)
	MachineParts.box(
		self, "Header", Vector3(WIDTH + 0.1, 0.55, 0.72), Vector3(0.0, 2.85, -0.84), iron
	)
	MachineParts.box(
		self, "HeaderTrim", Vector3(WIDTH + 0.14, 0.05, 0.76), Vector3(0.0, 3.14, -0.84), brass
	)
	var sign_label := MachineParts.label(
		self,
		"RE-CUT",
		Vector3(0.0, 2.93, -0.47),
		72,
		Color(1.0, 0.86, 0.45),
		Color(0.2, 0.08, 0.02)
	)
	sign_label.name = "Sign"
	var small := MachineParts.label(
		self,
		"WHILE-U-WAIT",
		Vector3(0.0, 2.64, -0.47),
		40,
		Color(0.92, 0.85, 0.66),
		Color(0.12, 0.08, 0.04)
	)
	small.name = "Subtitle"
	# The reels: brass discs with a hub and three spokes, turning on the tower's face.
	for x in [-0.95, 0.95]:
		var reel := Node3D.new()
		reel.name = "Reel"
		reel.position = Vector3(x, 2.0, -0.62)
		add_child(reel)
		MachineParts.cylinder(reel, "Disc", 0.52, 0.07, Vector3.ZERO, brass, Vector3.AXIS_Z, 28)
		MachineParts.cylinder(
			reel,
			"Rim",
			0.5,
			0.1,
			Vector3.ZERO,
			MachineParts.plain(Color(0.1, 0.09, 0.08)),
			Vector3.AXIS_Z,
			28
		)
		MachineParts.cylinder(reel, "Face", 0.46, 0.12, Vector3.ZERO, brass, Vector3.AXIS_Z, 28)
		for i in 3:
			var spoke := MachineParts.box(
				reel,
				"Spoke",
				Vector3(0.84, 0.1, 0.14),
				Vector3.ZERO,
				MachineParts.plain(Color(0.1, 0.09, 0.08))
			)
			spoke.rotation.z = PI * float(i) / 3.0
		MachineParts.cylinder(
			reel,
			"Hub",
			0.1,
			0.18,
			Vector3.ZERO,
			MachineParts.plain(CREAM, 0.4, 0.3),
			Vector3.AXIS_Z
		)
		_reels.append(reel)
	# The film that runs from reel to reel, in front of the tower.
	MachineParts.box(
		self,
		"FilmRun",
		Vector3(1.36, 0.05, 0.02),
		Vector3(0.0, 1.62, -0.66),
		MachineParts.glow(AMBER, 0.9)
	)


func _press() -> void:
	var brass := MachineParts.plain(BRASS, 0.35, 0.8)
	var iron := MachineParts.plain(IRON_LIGHT, 0.5, 0.5)
	MachineParts.box(
		self,
		"Cradle",
		Vector3(1.75, 0.1, 0.5),
		Vector3(0.0, 1.07, CRADLE.z),
		MachineParts.plain(Color(0.05, 0.05, 0.06))
	)
	for x in [-0.55, 0.55]:
		MachineParts.box(
			self, "Saddle", Vector3(0.14, 0.14, 0.42), Vector3(x, 1.18, CRADLE.z), brass
		)
	for x in [-0.98, 0.98]:
		MachineParts.cylinder(self, "Column", 0.06, 1.2, Vector3(x, 1.65, CRADLE.z), brass)
	_ram = Node3D.new()
	_ram.name = "Ram"
	_ram.position = Vector3(0.0, RAM_UP, CRADLE.z)
	add_child(_ram)
	MachineParts.box(_ram, "Beam", Vector3(2.2, 0.16, 0.3), Vector3(0.0, 0.0, 0.0), iron)
	for x in [-0.98, 0.98]:
		MachineParts.box(_ram, "Collar", Vector3(0.2, 0.22, 0.34), Vector3(x, 0.0, 0.0), brass)
	MachineParts.box(
		_ram, "Head", Vector3(0.7, 0.28, 0.26), Vector3(0.0, -0.22, 0.0), _head_material
	)
	MachineParts.box(_ram, "Shank", Vector3(0.2, 0.2, 0.2), Vector3(0.0, -0.08, 0.0), iron)


func _film_strip() -> void:
	_film_material = MachineParts.plain(Color.WHITE, 0.6)
	_film_material.albedo_texture = _film_texture()
	_film_material.emission_enabled = true
	_film_material.emission_texture = _film_material.albedo_texture
	_film_material.emission = Color(1.0, 0.8, 0.5)
	_film_material.emission_energy_multiplier = 0.9
	_film_material.texture_repeat = true
	_film_material.uv1_scale = Vector3(5.0, 1.0, 1.0)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.7, 0.34)
	var strip := MeshInstance3D.new()
	strip.name = "Film"
	strip.mesh = mesh
	strip.material_override = _film_material
	strip.position = Vector3(0.0, 0.58, DEPTH / 2.0 + 0.012)
	add_child(strip)
	MachineParts.box(
		self,
		"FilmFrame",
		Vector3(2.8, 0.44, 0.02),
		Vector3(0.0, 0.58, DEPTH / 2.0 + 0.005),
		MachineParts.plain(Color(0.05, 0.04, 0.03))
	)


## A strip of film: a dark base, sprocket holes along both edges and a frame between them.
func _film_texture() -> ImageTexture:
	var image := Image.create(160, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.07, 0.05))
	for x in 160:
		for y in 32:
			var edge := y < 7 or y >= 25
			var hole := edge and (x % 10) in [3, 4, 5, 6] and (y in [2, 3, 4] or y in [27, 28, 29])
			if hole:
				image.set_pixel(x, y, Color(0.96, 0.82, 0.5))
			elif not edge and (x % 40) in range(3, 37):
				var shade := 0.5 + 0.35 * sin(float(x) * 0.31) * cos(float(y) * 0.5)
				image.set_pixel(x, y, Color(0.9, 0.75, 0.42) * shade + Color(0.05, 0.03, 0.02))
	return ImageTexture.create_from_image(image)


func _lamp_row() -> void:
	for i in LAMP_COUNT:
		var material := MachineParts.glow(
			Color(0.5, 1.0, 0.55) if i == LAMP_COUNT - 1 else AMBER, 1.0
		)
		var x := -0.6 + 1.2 * float(i) / float(LAMP_COUNT - 1)
		var lamp := MachineParts.sphere(
			self, "Lamp", 0.055, Vector3(x, 0.9, DEPTH / 2.0 + 0.06), material
		)
		_lamps.append(lamp)
		_lamp_materials.append(material)
		_lamp_colours.append(material.albedo_color)


func _effects() -> void:
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = Color(1.0, 0.72, 0.4)
	_light.omni_range = 5.5
	_light.position = Vector3(0.0, 1.9, 1.2)
	add_child(_light)
	_sparks = CPUParticles3D.new()
	_sparks.name = "Sparks"
	_sparks.amount = 40
	_sparks.lifetime = 0.7
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.direction = Vector3(0.0, 1.0, 0.3)
	_sparks.spread = 80.0
	_sparks.initial_velocity_min = 1.8
	_sparks.initial_velocity_max = 4.2
	_sparks.gravity = Vector3(0.0, -8.0, 0.0)
	var spark := SphereMesh.new()
	spark.radius = 0.018
	spark.height = 0.036
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# The blow's sparks burn the skin's colour.
	spark_material.albedo_color = RecutStyle.shipped().spark
	spark.material = spark_material
	_spark_material = spark_material
	_sparks.mesh = spark
	_sparks.position = Vector3(0.0, 1.3, CRADLE.z)
	_sparks.emitting = false
	add_child(_sparks)
	# The ring: a flat ring of light on the cradle that the blow sends out. Unshaded and additive, so
	# it
	# takes no light's place and draws only while it shows.
	var torus := TorusMesh.new()
	torus.outer_radius = RING_FROM * 0.5
	torus.inner_radius = RING_FROM * 0.5 - 0.012
	torus.rings = 36
	torus.ring_segments = 4
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_material.albedo_color = Color(RecutStyle.shipped().cold, 1.0)
	torus.material = _ring_material
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = torus
	_ring.position = Vector3(0.0, 1.14, CRADLE.z)
	_ring.visible = false
	add_child(_ring)


## The weapons that can lie on the cradle, one model each, under a node that moves them all.
func _cradle_display() -> void:
	_display = Node3D.new()
	_display.name = "Display"
	_display.position = CRADLE
	add_child(_display)
	for id: StringName in MachineParts.WEAPON_MODELS:
		var holder := MachineParts.weapon_model(id, WEAPON_LENGTH)
		if holder == null:
			continue
		holder.visible = false
		_display.add_child(holder)
		_holders[id] = holder
