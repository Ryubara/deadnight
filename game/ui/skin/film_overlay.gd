class_name FilmOverlay
extends ColorRect
## Grain, vignette and projector flicker over everything (the last node of the router's layer,
## #883).

const SHADER := preload("res://ui/skin/film_grain.gdshader")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.WHITE
	var shade := ShaderMaterial.new()
	shade.shader = SHADER
	material = shade
	UIMotion.changed().connect(_apply_motion)
	_apply_motion(UIMotion.reduced)


## Reduced motion keeps the vignette and a still grain, and stops flicker, scratches and
## the changing grain: the shader's clock stands still.
func _apply_motion(reduced: bool) -> void:
	(material as ShaderMaterial).set_shader_parameter(&"motion", 0.0 if reduced else 1.0)
