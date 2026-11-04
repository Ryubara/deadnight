extends Node
## Reads the view's yaw at the start of the frame's `_process` calls, for `look_lag_probe.gd`.

var yaw_seen := 0.0
var rig: ThirdPersonCamera


func _process(_delta: float) -> void:
	if rig != null:
		yaw_seen = rig.yaw
