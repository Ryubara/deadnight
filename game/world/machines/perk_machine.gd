class_name PerkMachine
extends Node3D
## The lot's perk machines (`docs/design/perks.md`): a 1950s drink cooler with a glass front of
## bottles, a coin slot, a dispense tray and, over it, a lit board with the perk's name and what it
## does in plain words, crowned by an emblem that says the same in a picture. Five of them, one
## look each (`LOOKS`); the sixth perk, the health tonic, is the soda fountain (`SodaFountain`).
## Idle, the board and the emblem breathe and the emblem does its own small thing; a purchase
## (`play`) drops a bottle into the tray, pops its cap and flashes the emblem.
##
## Built from primitives (`MachineParts`), drawn from fixed steps (`advance`). Local space: the
## front is +Z, the floor y = 0. Original design, no copied asset. It adds no light (the
## Compatibility renderer lights a mesh with 8 at most); the glow is emission.

signal poured

## Every perk machine is in this group, so the night finds it (`MachineView`).
const GROUP := &"perk_machines"

const WIDTH := 1.5
const DEPTH := 0.9
const HEIGHT := 2.1
const CHROME := Color(0.78, 0.8, 0.84)
const CREAM := Color(0.93, 0.87, 0.7)
## The pour in seconds: the cap pops, the bottle drops, it lands, and the flash to the end.
const POP := 0.2
const DROP := 0.55
const DURATION := 1.4
const FLASH_DECAY := 2.5
const BOARD_Y := 2.78
const EMBLEM_Y := 3.55
const COLUMNS := 3
const ROWS := 3
## A flat cooler front: where the glass starts and how tall the window is.
const WINDOW_Y := 1.25
const WINDOW_HEIGHT := 0.95

## What each perk is called on its board, what it does, and its colours: the body of the cooler,
## the light of the board and emblem, the drink in the bottles. `item` is the shop item it sells.
const LOOKS := {
	&"double_shot":
	{
		"item": &"tonic_double_shot",
		"word": "DOUBLE SHOT",
		"role": "FASTER FIRE",
		"body": Color(0.72, 0.1, 0.12),
		"glow": Color(1.0, 0.72, 0.2),
		"drink": Color(0.95, 0.3, 0.2),
	},
	&"quick_load":
	{
		"item": &"tonic_quick_load",
		"word": "QUICK LOAD",
		"role": "FASTER RELOAD",
		"body": Color(0.08, 0.5, 0.52),
		"glow": Color(0.5, 1.0, 0.95),
		"drink": Color(0.35, 0.2, 0.1),
	},
	&"third_holster":
	{
		"item": &"tonic_third_holster",
		"word": "THIRD HOLSTER",
		"role": "CARRY A THIRD WEAPON",
		"body": Color(0.42, 0.18, 0.55),
		"glow": Color(1.0, 0.8, 0.35),
		"drink": Color(0.85, 0.65, 0.2),
	},
	&"swift_rescue":
	{
		"item": &"tonic_swift_rescue",
		"word": "SWIFT RESCUE",
		"role": "FASTER REVIVES, ONE UP ALONE",
		"body": Color(0.18, 0.55, 0.28),
		"glow": Color(0.6, 1.0, 0.6),
		"drink": Color(0.8, 0.95, 0.3),
	},
	&"reload_shock":
	{
		"item": &"tonic_reload_shock",
		"word": "RELOAD SHOCK",
		"role": "RELOADING SHOCKS THE DEAD",
		"body": Color(0.9, 0.42, 0.06),
		"glow": Color(0.45, 0.8, 1.0),
		"drink": Color(1.0, 0.55, 0.1),
	},
}

## Which look this machine has (a key of `LOOKS`).
@export var perk: StringName = &"double_shot"

var _clock := 0.0
## Seconds into a pour, or -1 when idle.
var _t := -1.0
var _poured := false
var _flash := 0.0
var _glow_material: StandardMaterial3D
var _board_material: StandardMaterial3D
var _bottles: Array[MeshInstance3D] = []
var _dropper: MeshInstance3D
var _flap: Node3D
## The emblem's parts, by what the idle and the pour do with them.
var _emblem: Node3D
var _spinner: Node3D
var _pulsers: Array[Node3D] = []
var _arcs: Array[MeshInstance3D] = []
var _ring: MeshInstance3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)
	_build()


func _physics_process(delta: float) -> void:
	advance(delta)


## The shop item this machine sells.
func item_id() -> StringName:
	return LOOKS[perk]["item"]


## Starts a pour.
func play() -> void:
	_t = 0.0
	_poured = false


func is_playing() -> bool:
	return _t >= 0.0


## The flash of the emblem at the landing: 1, falling to 0.
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


func _look() -> Dictionary:
	return LOOKS[perk]


func _pour(t: float) -> void:
	# The cap pops off the bottle that falls, the flap swings, the bottle lands in the tray.
	_dropper.visible = t < DROP + 0.25
	var fall := smoothstep(POP, DROP, t)
	_dropper.position = Vector3(-0.2, lerpf(WINDOW_Y + 0.5, 0.55, fall * fall), DEPTH / 2.0 + 0.1)
	_flap.rotation.x = (
		deg_to_rad(-50.0) * (smoothstep(POP, DROP, t) - smoothstep(DROP + 0.2, DURATION, t))
	)
	if t >= DROP and not _poured:
		_poured = true
		_flash = 1.0
		poured.emit()


func _rest() -> void:
	_dropper.visible = false
	_flap.rotation.x = 0.0


## The breathing of the board and the emblem, and what the emblem does while it waits.
func _dress() -> void:
	var breathe := 0.5 + 0.5 * sin(_clock * 1.7)
	_board_material.emission_energy_multiplier = 0.9 + 0.3 * breathe + 1.2 * _flash
	_glow_material.emission_energy_multiplier = 0.7 + 0.3 * breathe + 2.5 * _flash
	var busy := 1.0 if _t >= 0.0 else 0.0
	match perk:
		&"double_shot":
			# The two bullets take turns.
			for i in _pulsers.size():
				var turn := 0.5 + 0.5 * sin(_clock * (3.0 + 6.0 * busy) + PI * float(i))
				_pulsers[i].scale = Vector3.ONE * (0.92 + 0.14 * turn + 0.25 * _flash)
		&"quick_load":
			_spinner.rotation.z = _clock * (1.2 + 9.0 * busy) + 8.0 * _flash
		&"third_holster":
			# One, two, three; all three at the landing.
			var lit := int(floor(_clock * (2.0 + 4.0 * busy))) % _pulsers.size()
			for i in _pulsers.size():
				var on := i == lit or _flash > 0.2
				_pulsers[i].scale = Vector3(1.0, 1.0, 1.0 if on else 0.6)
		&"swift_rescue":
			# A heartbeat: two beats and a rest.
			var phase := fmod(_clock * 1.1, 1.0)
			var beat := smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.08, 0.22, phase))
			beat += 0.7 * smoothstep(0.28, 0.36, phase) * (1.0 - smoothstep(0.36, 0.5, phase))
			_emblem.scale = Vector3.ONE * (1.0 + 0.12 * beat + 0.2 * _flash)
			_ring.scale = (
				Vector3.ONE * (1.0 + 1.4 * (1.0 - _flash)) if _flash > 0.0 else Vector3.ONE
			)
		&"reload_shock":
			_crackle(busy)


## The arc between the two electrodes jumps about: three thin bars, placed again every twelfth of
## a second from a generator seeded by the step, so a capture shows the same arc each time.
func _crackle(busy: float) -> void:
	_rng.seed = int(_clock * 12.0) * 7919
	var span := 0.7
	var strength := 0.05 + 0.1 * busy + 0.25 * _flash
	for i in _arcs.size():
		var a := -span / 2.0 + span * float(i) / float(_arcs.size())
		var b := a + span / float(_arcs.size())
		var ya := _rng.randf_range(-strength, strength)
		var yb := _rng.randf_range(-strength, strength)
		var arc := _arcs[i]
		arc.position = Vector3((a + b) / 2.0, -0.2 + (ya + yb) / 2.0, 0.0)
		var dx := b - a
		arc.rotation.z = atan2(yb - ya, dx)
		arc.scale = Vector3(sqrt(dx * dx + (yb - ya) * (yb - ya)) / 0.2, 1.0 + 2.0 * _flash, 1.0)


# --- Building ---


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_bottles.clear()
	_pulsers.clear()
	_arcs.clear()
	var look := _look()
	_glow_material = MachineParts.glow(look["glow"], 0.9)
	_board_material = MachineParts.glow(look["body"].lightened(0.1), 0.9)
	_cooler(look)
	_window(look)
	_tray()
	_board(look)
	_build_emblem()
	_rest()
	_dress()


func _cooler(look: Dictionary) -> void:
	var body := MachineParts.plain(look["body"], 0.4)
	var chrome := MachineParts.plain(CHROME, 0.2, 0.9)
	var cream := MachineParts.plain(CREAM, 0.5)
	MachineParts.box(
		self, "Base", Vector3(WIDTH, HEIGHT, DEPTH), Vector3(0.0, HEIGHT / 2.0, 0.0), body
	)
	MachineParts.box(
		self, "Kick", Vector3(WIDTH + 0.02, 0.12, DEPTH + 0.02), Vector3(0.0, 0.06, 0.0), chrome
	)
	MachineParts.box(
		self, "Band", Vector3(WIDTH + 0.04, 0.06, DEPTH + 0.04), Vector3(0.0, 0.95, 0.0), chrome
	)
	MachineParts.box(
		self,
		"Top",
		Vector3(WIDTH + 0.1, 0.08, DEPTH + 0.1),
		Vector3(0.0, HEIGHT + 0.04, 0.0),
		cream
	)
	# The side fins of the 1950s: a chrome strip down each front corner.
	for sx in [-1.0, 1.0]:
		MachineParts.box(
			self,
			"Fin",
			Vector3(0.05, HEIGHT - 0.2, 0.05),
			Vector3(sx * (WIDTH / 2.0 + 0.01), HEIGHT / 2.0 + 0.05, DEPTH / 2.0),
			chrome
		)


## The glass front: a dark back panel, three shelves of bottles and the glass over them.
func _window(look: Dictionary) -> void:
	var dark := MachineParts.plain(Color(0.05, 0.05, 0.07), 0.9)
	var chrome := MachineParts.plain(CHROME, 0.2, 0.9)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.9, 0.95, 0.14)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var front := DEPTH / 2.0
	MachineParts.box(
		self,
		"Window",
		Vector3(WIDTH - 0.3, WINDOW_HEIGHT, 0.04),
		Vector3(0.0, WINDOW_Y + WINDOW_HEIGHT / 2.0 - 0.05, front + 0.005),
		dark
	)
	var drink := MachineParts.glow(look["drink"], 0.5)
	for row in ROWS:
		var y := WINDOW_Y + 0.15 + float(row) * 0.3
		MachineParts.box(
			self,
			"Shelf",
			Vector3(WIDTH - 0.34, 0.03, 0.18),
			Vector3(0.0, y - 0.13, front - 0.02),
			chrome
		)
		for column in COLUMNS:
			var x := (float(column) - float(COLUMNS - 1) / 2.0) * 0.34
			var bottle := MachineParts.cylinder(
				self, "Bottle", 0.055, 0.2, Vector3(x, y, front - 0.02), drink
			)
			_bottles.append(bottle)
			MachineParts.cylinder(
				self, "Neck", 0.022, 0.08, Vector3(x, y + 0.14, front - 0.02), drink
			)
	MachineParts.box(
		self,
		"Glass",
		Vector3(WIDTH - 0.3, WINDOW_HEIGHT, 0.02),
		Vector3(0.0, WINDOW_Y + WINDOW_HEIGHT / 2.0 - 0.05, front + 0.04),
		glass
	)


## The coin slot, the dispense flap and the tray the bottle lands in.
func _tray() -> void:
	var chrome := MachineParts.plain(CHROME, 0.2, 0.9)
	var dark := MachineParts.plain(Color(0.04, 0.04, 0.05), 0.9)
	var front := DEPTH / 2.0
	MachineParts.box(
		self, "SlotPlate", Vector3(0.22, 0.34, 0.03), Vector3(0.45, 0.78, front + 0.015), chrome
	)
	MachineParts.box(
		self, "Slot", Vector3(0.1, 0.03, 0.035), Vector3(0.45, 0.85, front + 0.02), dark
	)
	MachineParts.box(
		self, "Lamp", Vector3(0.05, 0.05, 0.04), Vector3(0.45, 0.72, front + 0.02), _glow_material
	)
	MachineParts.box(self, "Bay", Vector3(0.5, 0.3, 0.06), Vector3(-0.2, 0.52, front + 0.01), dark)
	_flap = Node3D.new()
	_flap.name = "Flap"
	_flap.position = Vector3(-0.2, 0.67, front + 0.05)
	add_child(_flap)
	MachineParts.box(_flap, "FlapPlate", Vector3(0.5, 0.3, 0.025), Vector3(0.0, -0.15, 0.0), chrome)
	_dropper = MachineParts.cylinder(
		self,
		"Dropped",
		0.055,
		0.2,
		Vector3(-0.2, WINDOW_Y, front + 0.1),
		_bottles[0].material_override
	)


func _board(look: Dictionary) -> void:
	var dark := MachineParts.plain(Color(0.06, 0.05, 0.06), 0.6)
	MachineParts.box(
		self,
		"Pole",
		Vector3(0.12, BOARD_Y - HEIGHT - 0.3, 0.12),
		Vector3(0.0, HEIGHT + 0.15 + (BOARD_Y - HEIGHT - 0.3) / 2.0, -0.2),
		dark
	)
	MachineParts.box(
		self, "Board", Vector3(WIDTH + 0.2, 0.62, 0.1), Vector3(0.0, BOARD_Y, 0.0), _board_material
	)
	MachineParts.box(
		self, "BoardFace", Vector3(WIDTH + 0.08, 0.5, 0.02), Vector3(0.0, BOARD_Y, 0.056), dark
	)
	var word := MachineParts.label(
		self,
		look["word"],
		Vector3(0.0, BOARD_Y + 0.1, 0.07),
		44,
		Color(1.0, 0.95, 0.85),
		look["body"].darkened(0.5)
	)
	word.name = "Word"
	word.pixel_size = 0.0042
	var role := MachineParts.label(
		self,
		look["role"],
		Vector3(0.0, BOARD_Y - 0.14, 0.07),
		24,
		look["glow"],
		Color(0.02, 0.02, 0.03)
	)
	role.name = "Role"
	role.pixel_size = 0.0042


func _build_emblem() -> void:
	_emblem = Node3D.new()
	_emblem.name = "Emblem"
	_emblem.position = Vector3(0.0, EMBLEM_Y + 0.05, 0.0)
	add_child(_emblem)
	match perk:
		&"double_shot":
			_emblem_bullets()
		&"quick_load":
			_emblem_drum()
		&"third_holster":
			_emblem_guns()
		&"swift_rescue":
			_emblem_cross()
		&"reload_shock":
			_emblem_bolt()


## Two bullets side by side, tips up.
func _emblem_bullets() -> void:
	for i in 2:
		var holder := Node3D.new()
		holder.name = "Bullet"
		holder.position = Vector3(-0.2 + 0.4 * float(i), 0.0, 0.0)
		_emblem.add_child(holder)
		MachineParts.cylinder(holder, "Case", 0.11, 0.32, Vector3(0.0, -0.1, 0.0), _glow_material)
		MachineParts.sphere(holder, "Tip", 0.11, Vector3(0.0, 0.08, 0.0), _glow_material)
		MachineParts.cylinder(
			holder,
			"Rim",
			0.13,
			0.04,
			Vector3(0.0, -0.27, 0.0),
			MachineParts.plain(CHROME, 0.2, 0.9)
		)
		_pulsers.append(holder)


## A revolver's drum, end on, with six chambers.
func _emblem_drum() -> void:
	_spinner = Node3D.new()
	_spinner.name = "Drum"
	_emblem.add_child(_spinner)
	MachineParts.cylinder(
		_spinner, "Body", 0.4, 0.14, Vector3.ZERO, _glow_material, Vector3.AXIS_Z, 24
	)
	var hole := MachineParts.plain(Color(0.03, 0.05, 0.06), 0.9)
	for i in 6:
		var angle := TAU * float(i) / 6.0
		MachineParts.cylinder(
			_spinner,
			"Chamber",
			0.075,
			0.16,
			Vector3(cos(angle) * 0.25, sin(angle) * 0.25, 0.0),
			hole,
			Vector3.AXIS_Z
		)
	MachineParts.cylinder(_spinner, "Hub", 0.06, 0.18, Vector3.ZERO, hole, Vector3.AXIS_Z)


## Three guns racked one above the other.
func _emblem_guns() -> void:
	for i in 3:
		var gun := Node3D.new()
		gun.name = "Gun"
		gun.position = Vector3(0.0, 0.26 - 0.26 * float(i), 0.0)
		_emblem.add_child(gun)
		MachineParts.box(gun, "Barrel", Vector3(0.62, 0.08, 0.08), Vector3.ZERO, _glow_material)
		var grip := MachineParts.box(
			gun, "Grip", Vector3(0.1, 0.2, 0.08), Vector3(-0.22, -0.12, 0.0), _glow_material
		)
		grip.rotation.z = 0.25
		_pulsers.append(gun)


## A medical cross in a ring that goes out when the bottle lands.
func _emblem_cross() -> void:
	MachineParts.box(_emblem, "Bar", Vector3(0.52, 0.16, 0.1), Vector3.ZERO, _glow_material)
	MachineParts.box(_emblem, "Post", Vector3(0.16, 0.52, 0.1), Vector3.ZERO, _glow_material)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.38
	ring.outer_radius = 0.42
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = ring
	_ring.material_override = _glow_material
	_ring.rotation.x = PI / 2.0
	_emblem.add_child(_ring)


## A lightning bolt between two electrodes, with a jumping arc.
func _emblem_bolt() -> void:
	var bolt := MachineParts.glow(Color(1.0, 0.95, 0.5), 2.0)
	var upper := MachineParts.box(
		_emblem, "BoltUpper", Vector3(0.12, 0.34, 0.08), Vector3(0.06, 0.2, 0.0), bolt
	)
	upper.rotation.z = deg_to_rad(20.0)
	MachineParts.box(_emblem, "BoltMid", Vector3(0.3, 0.1, 0.08), Vector3(0.0, 0.02, 0.0), bolt)
	var lower := MachineParts.box(
		_emblem, "BoltLower", Vector3(0.12, 0.38, 0.08), Vector3(-0.04, -0.2, 0.0), bolt
	)
	lower.rotation.z = deg_to_rad(20.0)
	var rod := MachineParts.plain(CHROME, 0.2, 0.9)
	for sx in [-1.0, 1.0]:
		MachineParts.cylinder(_emblem, "Electrode", 0.03, 0.4, Vector3(sx * 0.42, -0.4, 0.0), rod)
		MachineParts.sphere(_emblem, "Tip", 0.05, Vector3(sx * 0.42, -0.2, 0.0), _glow_material)
	for i in 4:
		var arc := MachineParts.box(
			_emblem, "Arc", Vector3(0.2, 0.025, 0.025), Vector3(0.0, -0.2, 0.0), _glow_material
		)
		_arcs.append(arc)
