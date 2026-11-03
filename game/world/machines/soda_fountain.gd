class_name SodaFountain
extends Node3D
## The soda fountain at the concession stand: it pours the hearty health tonic. A red and
## cream 1950s counter with a chrome band, a back bar of bottles under a neon heart, a glass tank of
## fizzing tonic and a tap with a lever. Idle, the heart breathes and bubbles rise in the tank. A
## purchase (`play`) pulls the lever, pops a cork, fills a tumbler, drains it at the gulp and
## flashes the heart and the lamp.
##
## Built from primitives (`MachineParts`), drawn from fixed steps (`advance`). Local space: the
## front is +Z, the floor y = 0. Original design, no copied asset.

signal poured

## Every fountain is in this group, so the night finds it (`MachineView`).
const GROUP := &"soda_fountains"

const WIDTH := 2.4
const DEPTH := 1.0
const RED := Color(0.7, 0.1, 0.13)
const CREAM := Color(0.93, 0.87, 0.7)
const CHROME := Color(0.78, 0.8, 0.84)
const TONIC := Color(0.95, 0.22, 0.3)
const HEART := Color(1.0, 0.25, 0.4)
const TAP := Vector3(0.4, 1.28, 0.18)
const TUMBLER := Vector3(0.4, 1.12, 0.36)
const TANK := Vector3(-0.55, 1.45, 0.05)
const TANK_HEIGHT := 0.72
## The pour in seconds: the lever, the fill, the gulp and the heart's flash, to the end.
const LEVER := 0.15
const FILL := 0.35
const GULP := 0.55
const DURATION := 1.3
const FLASH_DECAY := 3.0
const BUBBLES := 9

## The render layers the machine's glow lights (`Light3D.light_cull_mask`): the default layer and
## its room's, so the glow does not reach through the wall into the next room
## (docs/research/room-lights.md).
@export_flags_3d_render var light_layers := 0xFFFFFFFF

var _clock := 0.0
## Seconds into a pour, or -1 when idle.
var _t := -1.0
var _poured := false
var _flash := 0.0
var _heart_material := MachineParts.glow(HEART, 1.2)
var _tonic_material := MachineParts.glow(TONIC, 0.7)
var _lever: Node3D
var _fill: MeshInstance3D
var _bubbles: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _fizz: CPUParticles3D
var _cork: MeshInstance3D


func _ready() -> void:
	add_to_group(GROUP)
	_build()


func _physics_process(delta: float) -> void:
	advance(delta)


## Starts a pour.
func play() -> void:
	_t = 0.0
	_poured = false


## The meshes of the machine that never move or change, which the map's batch draws with the rest of
## the lot (`LotBatcher`). The lever, the cork, the tumbler's fill and the bubbles are the machine's
## own.
func still_meshes() -> Array[MeshInstance3D]:
	var moving: Array = [_lever, _fill, _cork]
	moving.append_array(_bubbles)
	return MachineParts.meshes_outside(self, moving)


func is_playing() -> bool:
	return _t >= 0.0


## How full the tumbler is, 0 to 1.
func fullness() -> float:
	return _fill.scale.y if _fill.visible else 0.0


## The heart's flash: 1 at the gulp, falling to 0.
func flash() -> float:
	return _flash


## Moves the machine on by `delta` seconds.
func advance(delta: float) -> void:
	_clock += delta
	if _t >= 0.0:
		_t += delta
		_pour(_t)
		if _t >= DURATION:
			_t = -1.0
			_rest()
	_flash = maxf(_flash - delta * FLASH_DECAY, 0.0)
	_dress()


func _pour(t: float) -> void:
	_lever.rotation.x = (
		deg_to_rad(38.0) * (smoothstep(0.0, LEVER, t) - smoothstep(GULP, GULP + 0.3, t))
	)
	var fill := smoothstep(LEVER, FILL, t)
	var drain := smoothstep(FILL + 0.1, GULP, t)
	_fill.visible = t >= LEVER and drain < 1.0
	_fill.scale.y = maxf(fill * (1.0 - drain), 0.001)
	_fill.position.y = TUMBLER.y - 0.075 + 0.07 * _fill.scale.y
	# The cork leaves the tap at the start and falls back.
	_cork.visible = t < 0.45
	_cork.position = TAP + Vector3(0.0, 0.2 + 0.45 * t - 2.2 * t * t, 0.1 * t)
	_fizz.emitting = t >= LEVER and t < GULP
	if t >= GULP and not _poured:
		_poured = true
		_flash = 1.0
		poured.emit()


func _rest() -> void:
	_lever.rotation.x = 0.0
	_fill.visible = false
	_cork.visible = false
	_fizz.emitting = false


func _dress() -> void:
	var breathe := 0.5 + 0.5 * sin(_clock * 1.6)
	_heart_material.emission_energy_multiplier = 1.0 + 0.5 * breathe + 4.0 * _flash
	_tonic_material.emission_energy_multiplier = 0.6 + 0.3 * breathe + 1.5 * _flash
	_light.light_energy = 0.7 + 0.15 * breathe + 3.0 * _flash
	var pace := 1.0 + (3.0 if _t >= 0.0 else 0.0)
	for i in _bubbles.size():
		var rise := fmod(_clock * 0.22 * pace + float(i) * 0.37, 1.0)
		var sway := sin(_clock * 2.0 + float(i) * 1.7) * 0.08
		var bubble := _bubbles[i]
		bubble.position = (
			TANK
			+ Vector3(
				sway + float(i % 3 - 1) * 0.07, -TANK_HEIGHT * 0.45 + rise * TANK_HEIGHT * 0.86, 0.0
			)
		)
		bubble.scale = Vector3.ONE * (0.6 + 0.6 * rise)


# --- Building ---


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_bubbles.clear()
	_counter()
	_back_bar()
	_tank()
	_tap()
	_sign()
	_effects()
	_rest()
	_dress()


func _counter() -> void:
	var red := MachineParts.plain(RED, 0.4)
	var cream := MachineParts.plain(CREAM, 0.5)
	var chrome := MachineParts.plain(CHROME, 0.2, 0.9)
	MachineParts.box(self, "Base", Vector3(WIDTH, 0.95, DEPTH), Vector3(0.0, 0.475, 0.0), red)
	MachineParts.box(
		self, "Band", Vector3(WIDTH + 0.04, 0.07, DEPTH + 0.04), Vector3(0.0, 0.6, 0.0), chrome
	)
	MachineParts.box(
		self, "Kick", Vector3(WIDTH + 0.02, 0.1, DEPTH + 0.02), Vector3(0.0, 0.05, 0.0), chrome
	)
	MachineParts.box(
		self, "Top", Vector3(WIDTH + 0.12, 0.08, DEPTH + 0.12), Vector3(0.0, 0.99, 0.0), cream
	)
	# Three round stool-top studs on the front, a nod to the diner's counter.
	for x in [-0.7, 0.0, 0.7]:
		MachineParts.cylinder(
			self, "Stud", 0.07, 0.03, Vector3(x, 0.32, DEPTH / 2.0 + 0.015), chrome, Vector3.AXIS_Z
		)


func _back_bar() -> void:
	var wood := MachineParts.plain(Color(0.32, 0.12, 0.08), 0.6)
	var cream := MachineParts.plain(CREAM, 0.5)
	MachineParts.box(self, "BackWall", Vector3(WIDTH, 0.95, 0.08), Vector3(0.0, 1.5, -0.46), wood)
	MachineParts.box(
		self, "Shelf", Vector3(WIDTH - 0.1, 0.05, 0.28), Vector3(0.0, 1.55, -0.34), cream
	)
	var colours: Array[Color] = [
		Color(0.9, 0.2, 0.25),
		Color(0.95, 0.75, 0.25),
		Color(0.4, 0.75, 0.55),
		Color(0.9, 0.2, 0.25),
		Color(0.4, 0.65, 0.85)
	]
	for i in colours.size():
		var x := 0.15 + 0.38 * float(i)
		var bottle := MachineParts.glow(colours[i], 0.35)
		MachineParts.cylinder(self, "Bottle", 0.055, 0.26, Vector3(x, 1.71, -0.34), bottle)
		MachineParts.cylinder(self, "Neck", 0.022, 0.1, Vector3(x, 1.89, -0.34), bottle)


func _tank() -> void:
	var chrome := MachineParts.plain(CHROME, 0.2, 0.9)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.9, 0.95, 0.16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tonic_material.albedo_color = Color(TONIC, 0.55)
	_tonic_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	MachineParts.cylinder(
		self, "TankBase", 0.32, 0.08, TANK + Vector3(0.0, -TANK_HEIGHT / 2.0 - 0.04, 0.0), chrome
	)
	MachineParts.cylinder(
		self, "TankCap", 0.32, 0.08, TANK + Vector3(0.0, TANK_HEIGHT / 2.0 + 0.04, 0.0), chrome
	)
	MachineParts.cylinder(
		self, "Liquid", 0.26, TANK_HEIGHT - 0.1, TANK, _tonic_material, Vector3.AXIS_Y, 24
	)
	MachineParts.cylinder(self, "Glass", 0.29, TANK_HEIGHT, TANK, glass, Vector3.AXIS_Y, 24)
	var bubble_material := MachineParts.glow(Color(1.0, 0.85, 0.88), 1.2)
	for i in BUBBLES:
		_bubbles.append(MachineParts.sphere(self, "Bubble", 0.022, TANK, bubble_material))


func _tap() -> void:
	var chrome := MachineParts.plain(CHROME, 0.2, 0.9)
	MachineParts.cylinder(self, "Tower", 0.06, 0.46, TAP + Vector3(0.0, -0.15, -0.08), chrome)
	MachineParts.box(
		self, "Spout", Vector3(0.07, 0.07, 0.24), TAP + Vector3(0.0, 0.05, 0.05), chrome
	)
	_lever = Node3D.new()
	_lever.name = "Lever"
	_lever.position = TAP + Vector3(0.0, 0.1, -0.08)
	add_child(_lever)
	MachineParts.box(_lever, "Arm", Vector3(0.04, 0.04, 0.3), Vector3(0.0, 0.0, 0.14), chrome)
	MachineParts.sphere(_lever, "Knob", 0.05, Vector3(0.0, 0.0, 0.3), MachineParts.plain(RED, 0.3))
	# The tumbler on the counter under the spout, a cork over the spout, the tonic in the glass.
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.95, 1.0, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	MachineParts.cylinder(self, "Tumbler", 0.075, 0.16, TUMBLER, glass)
	_fill = MachineParts.cylinder(self, "Fill", 0.065, 0.14, TUMBLER, _tonic_material)
	_cork = MachineParts.sphere(self, "Cork", 0.03, TAP, MachineParts.plain(Color(0.7, 0.5, 0.3)))


func _sign() -> void:
	# A neon heart over the back bar (two lobes and a point), and a board with the word under it,
	# above the bottles and the tank.
	MachineParts.box(
		self,
		"Board",
		Vector3(1.4, 0.3, 0.06),
		Vector3(0.0, 2.2, -0.43),
		MachineParts.plain(Color(0.2, 0.05, 0.06), 0.5)
	)
	MachineParts.sphere(self, "HeartL", 0.13, Vector3(-0.1, 2.78, -0.4), _heart_material)
	MachineParts.sphere(self, "HeartR", 0.13, Vector3(0.1, 2.78, -0.4), _heart_material)
	var point := MachineParts.box(
		self, "HeartPoint", Vector3(0.24, 0.24, 0.18), Vector3(0.0, 2.69, -0.4), _heart_material
	)
	point.rotation.z = PI / 4.0
	var word := MachineParts.label(
		self,
		"HEARTY HEALTH",
		Vector3(0.0, 2.2, -0.39),
		48,
		Color(1.0, 0.86, 0.9),
		Color(0.25, 0.02, 0.06)
	)
	word.name = "Sign"


func _effects() -> void:
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_cull_mask = light_layers
	_light.light_color = Color(1.0, 0.55, 0.55)
	_light.omni_range = 4.5
	_light.position = Vector3(0.0, 1.8, 0.8)
	add_child(_light)
	_fizz = CPUParticles3D.new()
	_fizz.name = "Fizz"
	_fizz.amount = 24
	_fizz.lifetime = 0.5
	_fizz.direction = Vector3.UP
	_fizz.spread = 30.0
	_fizz.initial_velocity_min = 0.3
	_fizz.initial_velocity_max = 0.7
	_fizz.gravity = Vector3(0.0, -0.4, 0.0)
	var bit := SphereMesh.new()
	bit.radius = 0.01
	bit.height = 0.02
	var bit_material := StandardMaterial3D.new()
	bit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bit_material.albedo_color = Color(1.0, 0.8, 0.85)
	bit.material = bit_material
	_fizz.mesh = bit
	_fizz.position = TUMBLER + Vector3(0.0, 0.05, 0.0)
	_fizz.emitting = false
	add_child(_fizz)
