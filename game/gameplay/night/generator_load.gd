class_name GeneratorLoad
extends RefCounted
## The generator as a listener can know it: how full the tank is and how much the lit circuits
## draw, followed from the rules' events (`fuel_changed`, `circuit_changed`, `fuel_empty`,
## `fuel_restored`) from the night's tuning. The hum's level, pitch and sputter follow these
## numbers. It reads no game object.

var fuel := 0.0
var empty := false

var _tuning: FuelTuning
var _on: Dictionary[StringName, bool] = {}


func configure(tuning: FuelTuning) -> void:
	_tuning = tuning
	fuel = tuning.start_fuel
	empty = fuel <= 0.0
	_on.clear()
	for circuit_id in tuning.circuit_drain:
		_on[circuit_id] = tuning.start_circuits.has(circuit_id)


func apply(event: Dictionary) -> void:
	match event["type"]:
		&"fuel_changed":
			fuel = event["fuel"]
			empty = fuel <= 0.0
		&"fuel_empty":
			fuel = 0.0
			empty = true
		&"fuel_restored":
			empty = false
		&"circuit_changed":
			_on[event["circuit_id"]] = event["on"]


## The tank, 0 to 1.
func fraction() -> float:
	return clampf(fuel / _tuning.capacity, 0.0, 1.0)


## How hard the engine works, 0 (idle, every circuit off) to 1 (every circuit on).
func load_fraction() -> float:
	var most := _tuning.idle_drain
	var now := _tuning.idle_drain
	for circuit_id in _tuning.circuit_drain:
		most += _tuning.circuit_drain[circuit_id]
		if _on.get(circuit_id, false):
			now += _tuning.circuit_drain[circuit_id]
	return now / most


## The warning is up: below the tank's low line but not dry.
func is_low() -> bool:
	return not empty and fraction() < _tuning.low_fraction


## 0 at the low line, 1 when dry: how bad the starving is.
func starving() -> float:
	return clampf(1.0 - fraction() / _tuning.low_fraction, 0.0, 1.0)
