class_name FuelTuning
extends Resource
## The generator: tank size and what drains it. Lights are circuits a player switches on and off,
## each with a draw.

## Units in a full tank.
@export var capacity: float = 100.0
@export var start_fuel: float = 100.0
## Units per second the generator burns with every circuit off.
@export var idle_drain: float = 0.03
## Units per second each circuit adds while it is on. The key is the circuit's id.
@export var circuit_drain: Dictionary[StringName, float] = {
	&"screen_lot": 0.06,
	&"concession": 0.05,
	&"booth": 0.08,
	&"back_lot": 0.07,
}
## The circuits that are on when the night starts.
@export var start_circuits: Array[StringName] = [&"screen_lot"]
## The whole draw grows by this fraction for each round after the first (the generator strains).
@export var round_strain: float = 0.03
## Between rounds the draw is multiplied by this (the lot idles).
@export var break_factor: float = 0.5
## Below this fraction of the tank a warning is raised.
@export var low_fraction: float = 0.25
## Below this fraction the lights start to fail: power level falls from 1 to 0.
@export var brownout_fraction: float = 0.1
