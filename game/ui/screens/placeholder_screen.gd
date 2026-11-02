class_name PlaceholderScreen
extends UIScreen
## A screen that stands in for one that is not built yet: a card with a title, a note, optional
## actions (which only shake, for now) and a way back.

@export var overline := ""
@export var title := ""
@export_multiline var note := ""
@export var actions := PackedStringArray()

var back_button: UIButton
## The first action, which takes the focus; null when the screen has no actions.
var first_action: UIButton


func _ready() -> void:
	super._ready()
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", _tokens.space_md)
	panel.add_child(box)
	box.add_child(_label(overline, UILabel.Style.OVERLINE))
	box.add_child(_label(title, UILabel.Style.TITLE))
	var body := _label(note, UILabel.Style.BODY)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 620.0
	box.add_child(body)
	for action in actions:
		var button := _button(action, UIButton.Variant.PRIMARY)
		button.pressed.connect(func() -> void: UIMotion.shake(button))
		if first_action == null:
			first_action = button
		box.add_child(button)
	back_button = _button("Back", UIButton.Variant.GHOST)
	back_button.pressed.connect(UIRouter.pop)
	box.add_child(back_button)
	initial_focus = get_path_to(back_button if first_action == null else first_action)


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label


func _button(text: String, variant: UIButton.Variant) -> UIButton:
	var button := UIButton.new()
	button.text = text
	button.variant = variant
	button.custom_minimum_size.x = 620.0
	return button
