class_name RulesTuning
extends Resource
## The whole tuning table in one resource. Designers edit `default_tuning.tres`; no code holds a
## game number.

@export var rounds: RoundTuning = RoundTuning.new()
@export var economy: EconomyTuning = EconomyTuning.new()
@export var fuel: FuelTuning = FuelTuning.new()
