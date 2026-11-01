class_name FilmOverlay
extends ColorRect
## Grain, vignette and projector flicker over everything (it sits on a layer above the router).

const SHADER := preload("res://ui/skin/film_grain.gdshader")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.WHITE
	var shade := ShaderMaterial.new()
	shade.shader = SHADER
	shade.set_shader_parameter(&"motion", 0.0 if UIMotion.reduced else 1.0)
	material = shade
