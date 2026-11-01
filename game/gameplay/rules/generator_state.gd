class_name GeneratorState
extends RefCounted
## The generator's tank and circuits. Pure state with signals; GameRules ticks it.
##
## A circuit is one lit part of the lot. Lit ground slows the dead, so keeping a circuit on costs
## fuel and buys safety.

signal fuel_changed(fuel: float, delta: float)
signal circuit_changed(circuit_id: StringName, on: bool)
signal fuel_low
signal fuel_empty
signal fuel_restored

var fuel: float = 0.0
var circuits: Dictionary[StringName, bool] = {}

var _tuning: FuelTuning
var _was_low: bool = false


func _init(p_tuning: FuelTuning) -> void:
	_tuning = p_tuning
	fuel = clampf(_tuning.start_fuel, 0.0, _tuning.capacity)
	for circuit_id in _tuning.circuit_drain:
		circuits[circuit_id] = _tuning.start_circuits.has(circuit_id)


func fraction() -> float:
	return fuel / _tuning.capacity


func is_powered() -> bool:
	return fuel > 0.0


## 1 while the tank is healthy, falling to 0 as it runs dry (the lights flicker down).
func power_level() -> float:
	return clampf(fraction() / _tuning.brownout_fraction, 0.0, 1.0)


func is_lit(circuit_id: StringName) -> bool:
	return is_powered() and circuits.get(circuit_id, false)


## Units per second the generator is burning right now.
func drain_per_second(round_number: int, in_break: bool) -> float:
	if not is_powered():
		return 0.0
	var draw := _tuning.idle_drain
	for circuit_id in circuits:
		if circuits[circuit_id]:
			draw += _tuning.circuit_drain[circuit_id]
	draw *= 1.0 + _tuning.round_strain * float(maxi(round_number - 1, 0))
	return draw * _tuning.break_factor if in_break else draw


func tick(delta: float, round_number: int, in_break: bool) -> void:
	if not is_powered():
		return
	_set_fuel(fuel - drain_per_second(round_number, in_break) * delta)


## Adds up to `amount`; returns how much fitted.
func add_fuel(amount: float) -> float:
	var added := minf(amount, _tuning.capacity - fuel)
	if added > 0.0:
		_set_fuel(fuel + added)
	return maxf(added, 0.0)


## False when the circuit does not exist.
func set_circuit(circuit_id: StringName, on: bool) -> bool:
	if not circuits.has(circuit_id):
		return false
	if circuits[circuit_id] != on:
		circuits[circuit_id] = on
		circuit_changed.emit(circuit_id, on)
	return true


func to_dict() -> Dictionary:
	return {"fuel": fuel, "circuits": circuits.duplicate()}


## Puts the tank and circuits back as `to_dict` left them. Emits nothing: a restore is not a change.
func restore(data: Dictionary) -> void:
	fuel = data["fuel"]
	circuits.clear()
	for circuit_id in data["circuits"]:
		circuits[circuit_id] = data["circuits"][circuit_id]
	_was_low = fraction() <= _tuning.low_fraction


## Room left in the tank.
func space() -> float:
	return _tuning.capacity - fuel


func _set_fuel(value: float) -> void:
	var before := fuel
	fuel = clampf(value, 0.0, _tuning.capacity)
	if fuel == before:
		return
	fuel_changed.emit(fuel, fuel - before)
	if before <= 0.0 and fuel > 0.0:
		fuel_restored.emit()
	var low := fraction() <= _tuning.low_fraction
	if low and not _was_low and fuel > 0.0:
		fuel_low.emit()
	_was_low = low
	if fuel <= 0.0 and before > 0.0:
		fuel_empty.emit()
