class_name NfInput
extends BaseNetInput
## A player's input for netfox: netfox calls `_gather` on the owning peer before each tick,
## sends the
## value to the server, and re-feeds it to the simulation when it rolls back.

var dir := Vector2i.ZERO
var sampler: InputSampler


func _get_rollback_input_properties() -> Array:
	return ["dir"]


func _gather() -> void:
	if sampler:
		dir = sampler.sample()
