class_name LotLamps
extends RefCounted
## The lot's lamps (the `powered_light` group under a lot scene) and the circuits they hang on.
## Every lamp takes its circuit from the first node above it with `metadata/circuit`, written by
## tools/world/build_greybox.py. A circuit is one of the generator's (`GeneratorState`), or
##   - `MAINS`: wired to the generator with no switch: lit while the tank has fuel;
##   - `BATTERY`: not the generator's at all (a wreck's headlights): always lit.
##
## Two users, who never share state: the server asks `lit_at` (the rules' generator decides, never
## a node), and the client's view feeds the rules' events to `apply_event` and `refresh`es the
## lights from them. A light that is `visible` is only a drawing.

## The generator's circuits and the lamps' own kinds.
const MAINS := &"mains"
const BATTERY := &"battery"
## Metres within which a lamp lights the ground for the dead's slowdown.
const LAMP_REACH := 6.0
## A failing tank changes a lamp's state every this many ticks (60 a second: about 12 times).
const FLICKER_TICKS := 5
## How much light a lamp keeps when the tank is nearly dry, and in the dropouts of a flicker.
const SAG_FLOOR := 0.35
const DROPOUT := 0.12
## The step of the golden-ratio sequence that spreads each lamp's flicker out of step with the rest.
const _SPREAD := 0.6180339887
const _SLOT_PRIME := 7919.0
const _LAMP_PRIME := 104729.0


## One lamp: its light, the circuit it hangs on and what it needs to be drawn.
class Lamp:
	extends RefCounted
	var light: Light3D
	var circuit: StringName
	var energy: float
	## The fraction of its light it keeps when dark.
	var afterglow: float
	## A lamp post's bulb, which glows with it.
	var post: LampPost
	var position: Vector3
	var level := -1.0


var lamps: Array[Lamp] = []
## Which of the generator's circuits are on (the client's mirror of `circuit_changed`).
var circuits: Dictionary[StringName, bool] = {}
## The tank, as the frames report it; what the lights fail by.
var fuel := 0.0

var _capacity := 100.0
var _brownout := 0.1
var _tick := 0


## Gathers the lamps below `root`.
func _init(root: Node) -> void:
	for node in root.get_tree().get_nodes_in_group(&"powered_light"):
		if node is Light3D and root.is_ancestor_of(node):
			lamps.append(_lamp_of(node as Light3D))


## The client's starting picture of the generator (the rules' tuning): what is on, and how full.
func configure(tuning: FuelTuning) -> void:
	_capacity = tuning.capacity
	_brownout = tuning.brownout_fraction
	fuel = tuning.start_fuel
	circuits.clear()
	for circuit_id in tuning.circuit_drain:
		circuits[circuit_id] = tuning.start_circuits.has(circuit_id)


## The ids of every circuit the lamps hang on, `MAINS` and `BATTERY` included.
func circuit_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for lamp in lamps:
		if not ids.has(lamp.circuit):
			ids.append(lamp.circuit)
	return ids


func lamps_on(circuit: StringName) -> Array[Lamp]:
	return lamps.filter(func(lamp: Lamp) -> bool: return lamp.circuit == circuit)


# --- The server's question ---


## Whether the ground at `point` is lit: a lamp whose circuit the generator has lit is within
## reach. Without a generator everything is lit. This is the rules' word; a node is never asked.
func lit_at(point: Vector3, generator: GeneratorState) -> bool:
	for lamp in lamps:
		if _flat(point, lamp.position) < LAMP_REACH and circuit_is_lit(lamp.circuit, generator):
			return true
	return false


static func circuit_is_lit(circuit: StringName, generator: GeneratorState) -> bool:
	if generator == null or circuit == BATTERY:
		return true
	if circuit == MAINS:
		return generator.is_powered()
	return generator.is_lit(circuit)


# --- The client's drawing ---


## Follows the rules' events: a circuit switched, the tank dry or filled again, and the frame
## (the tank's exact level, and the tick the flicker keeps time by).
func apply_event(event: Dictionary) -> void:
	match event["type"]:
		&"circuit_changed":
			circuits[event["circuit_id"]] = event["on"]
			refresh(_tick)
		&"fuel_changed":
			fuel = event["fuel"]
		&"fuel_empty":
			fuel = 0.0
			refresh(_tick)
		&"fuel_restored":
			refresh(_tick)
		&"frame":
			fuel = event["fuel"]
			refresh(event["tick"])


## How much of the tank's power is left to the lights: 1 while it is healthy, falling to 0 as it
## runs dry (`GeneratorState.power_level`).
func power() -> float:
	return clampf(fuel / _capacity / _brownout, 0.0, 1.0)


## Sets every lamp for `tick`.
func refresh(tick: int) -> void:
	_tick = tick
	for i in lamps.size():
		var lamp := lamps[i]
		var level := maxf(
			brightness(_is_on(lamp.circuit), _power_for(lamp.circuit), tick, i), lamp.afterglow
		)
		if not is_equal_approx(level, lamp.level):
			_show(lamp, level)


## How bright a lamp burns: 0 when its circuit is off or the tank is dry, 1 while the tank is
## healthy, and between them a flicker that is a function of the tick and the lamp's number alone
## (no clock, no random draw), so a recording and a test see the same lights.
static func brightness(on: bool, power_level: float, tick: int, index: int) -> float:
	if not on or power_level <= 0.0:
		return 0.0
	if power_level >= 1.0:
		return 1.0
	var slot := float(floori(float(tick) / FLICKER_TICKS))
	var roll := fposmod((slot * _SLOT_PRIME + float(index) * _LAMP_PRIME) * _SPREAD, 1.0)
	var sag := lerpf(SAG_FLOOR, 1.0, power_level)
	return sag if roll < power_level else sag * DROPOUT


## A battery's lights do not ride the tank.
func _power_for(circuit: StringName) -> float:
	return 1.0 if circuit == BATTERY else power()


func _is_on(circuit: StringName) -> bool:
	if circuit == BATTERY:
		return true
	if circuit == MAINS:
		return fuel > 0.0
	return circuits.get(circuit, false)


func _show(lamp: Lamp, level: float) -> void:
	lamp.level = level
	lamp.light.visible = level > 0.0
	lamp.light.light_energy = lamp.energy * level
	if lamp.post != null:
		lamp.post.set_glow(level)


func _lamp_of(light: Light3D) -> Lamp:
	var lamp := Lamp.new()
	lamp.light = light
	lamp.circuit = _circuit_above(light)
	lamp.energy = light.light_energy
	lamp.afterglow = float(light.get_meta(&"afterglow", 0.0))
	lamp.post = light.get_parent() as LampPost
	lamp.position = light.global_position
	return lamp


## The circuit of the first node at or above `node` that names one; empty when none does.
static func _circuit_above(node: Node) -> StringName:
	var at := node
	while at != null:
		if at.has_meta(&"circuit"):
			return StringName(at.get_meta(&"circuit"))
		at = at.get_parent()
	return &""


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
