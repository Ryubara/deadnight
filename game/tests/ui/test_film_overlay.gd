# The film over the interface has grain, a vignette and flicker, and no line (#1249). Its scratch
# was a vertical line at a place that changed three times a second; on a phone page it read as a
# seam through every plate it crossed (measured in the web export, tools/web_smoke/column_line.py).
extends GdUnitTestSuite

const SHADER := preload("res://ui/skin/film_grain.gdshader")


func test_the_film_shader_has_no_scratch() -> void:
	var names: Array[String] = []
	for uniform in SHADER.get_shader_uniform_list():
		names.append(String(uniform["name"]))
	assert_array(names).contains_exactly_in_any_order(
		["grain", "grain_px", "vignette", "flicker", "motion"]
	)
