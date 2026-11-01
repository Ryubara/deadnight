class_name LightFollower
extends Node3D
## Something that glows because a lamp of the lot's circuits does: a sign, the screen, the
## projector's beam. It reads the lamp it follows (`light_path`) and never decides: `level` is the
## lamp's energy over the energy the scene gave it, 0 when `LotLamps` has hidden the light, so a
## circuit switched off, a failing tank and the screen's afterglow all carry over. Subclasses draw
## `level` in `_apply`.
##
## Time here is only the flicker's phase and is advanced by the frame's own delta, so Movie Maker
## (fixed fps) and a test that calls `advance` see the same light.

@export var light_path: NodePath

## 0 (dark) to 1 (burning), the followed lamp's level.
var level := 0.0
## Seconds of flicker phase.
var phase := 0.0

var _light: Light3D
var _base_energy := 1.0


func _ready() -> void:
	_light = get_node_or_null(light_path) as Light3D
	if _light != null:
		_base_energy = maxf(_light.light_energy, 0.001)
	_follow()


func _process(delta: float) -> void:
	advance(delta)


## Moves the flicker on by `delta` seconds and redraws.
func advance(delta: float) -> void:
	phase += delta
	_follow()


func _follow() -> void:
	if _light == null:
		return
	level = (_light.light_energy / _base_energy) if _light.visible else 0.0
	_apply()


## Draws `level` and `phase`; the subclass's.
func _apply() -> void:
	pass
