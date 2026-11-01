class_name NightSky
extends ColorRect
## The backdrop of every Deadnight screen: the drive-in lot at night, drawn by one shader.
##
## Colours come from the active UITokens, so a restyle reaches the sky too.

const SHADER := preload("res://ui/skin/drive_in_night.gdshader")

var _material := ShaderMaterial.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.WHITE
	var tokens := UITokens.active()
	_material.shader = SHADER
	_material.set_shader_parameter(&"sky_top", tokens.bg)
	_material.set_shader_parameter(&"sky_horizon", tokens.bg_glow)
	_material.set_shader_parameter(&"warm_color", tokens.accent)
	_material.set_shader_parameter(&"tail_color", tokens.hot)
	material = _material
	UIMotion.changed().connect(_apply_motion)
	_apply_motion(UIMotion.reduced)
	resized.connect(_update_aspect)
	_update_aspect()


## Reduced motion stops the sky's flicker, white-outs and twinkle.
func _apply_motion(reduced: bool) -> void:
	_material.set_shader_parameter(&"motion", 0.0 if reduced else 1.0)


func _update_aspect() -> void:
	_material.set_shader_parameter(&"aspect", size.x / maxf(size.y, 1.0))
