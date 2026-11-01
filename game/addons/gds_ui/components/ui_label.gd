@tool
class_name UILabel
extends Label
## A label with a named style from the token type scale.

enum Style { DISPLAY, TITLE, HEADING, BODY, CAPTION, OVERLINE, MONO }

@export var style := Style.BODY:
	set(value):
		style = value
		theme_type_variation = UIThemeBuilder.LABEL_STYLES[value]


func _init() -> void:
	theme_type_variation = UIThemeBuilder.LABEL_STYLES[style]
