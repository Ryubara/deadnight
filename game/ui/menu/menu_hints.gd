class_name MenuHints
extends HBoxContainer
## The line at the bottom of every tab: what a press does now, for the device in use. A keyboard
## and a mouse see key caps, a pad sees its buttons, a finger sees nothing (a cap on a phone
## points at nothing). It follows `UIInputMode`, which ignores a bumped desk's few pixels.

enum Kind { NONE, KEYS, PAD }

const KEYS := [["Enter", "Select"], ["Esc", "Back"], ["Q E", "Tabs"]]
const PAD := [["A", "Select"], ["B", "Back"], ["LB RB", "Tabs"]]

var kind := Kind.KEYS


func _init() -> void:
	add_theme_constant_override(&"separation", 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild()


func _process(_delta: float) -> void:
	var wanted := kind_for_input()
	if wanted != kind:
		kind = wanted
		_rebuild()


## The hints the last input asks for.
static func kind_for_input() -> Kind:
	if UIInputMode.touch:
		return Kind.NONE
	if UIInputMode.gamepad and not UIInputMode.pointer:
		return Kind.PAD
	return Kind.KEYS


## The pairs on show: [cap, what it does].
func pairs() -> Array:
	match kind:
		Kind.PAD:
			return PAD
		Kind.KEYS:
			return KEYS
	return []


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	visible = kind != Kind.NONE
	for pair: Array in pairs():
		var item := HBoxContainer.new()
		item.add_theme_constant_override(&"separation", 12)
		item.add_child(_cap(pair[0]))
		item.add_child(MenuLook.label(pair[1], MenuLook.SIZE_CAPTION, MenuLook.MUTED))
		add_child(item)


func _cap(text: String) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_border_width_all(2)
	style.border_color = MenuLook.MUTED
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override(&"panel", style)
	panel.add_child(MenuLook.label(text, MenuLook.SIZE_CAPTION, MenuLook.INK, &"wide"))
	return panel
