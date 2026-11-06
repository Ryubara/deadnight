class_name TouchField
extends RefCounted
## The size of a text field a finger taps (Deadnight #1183). A plain `LineEdit` is as tall as its
## text, 26 units: 19 px on a phone held sideways, under half of the 44 px a fingertip needs, so a
## tap that misses opens no keyboard. A field is as tall as a button.


## Makes `field` as tall as the tokens' controls.
static func fit(field: LineEdit) -> void:
	field.custom_minimum_size.y = maxf(
		field.custom_minimum_size.y, float(UITokens.active().control_height)
	)
