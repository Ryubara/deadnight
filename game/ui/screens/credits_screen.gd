class_name CreditsScreen
extends UIScreen
## Credits: reads a CreditsList and lists it, a section at a time, over the night sky.

@export var credits: CreditsList = preload("res://ui/credits.tres")


func _ready() -> void:
	super._ready()
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "List"
	box.add_theme_constant_override(&"separation", _tokens.space_sm)
	panel.add_child(box)
	box.add_child(_label("THE END CREDITS", UILabel.Style.OVERLINE))
	box.add_child(_label("Credits", UILabel.Style.TITLE))
	for section in credits.sections():
		box.add_child(_gap())
		if section["heading"] != "":
			box.add_child(_label(str(section["heading"]).to_upper(), UILabel.Style.OVERLINE))
		for line in section["names"]:
			box.add_child(_label(line, UILabel.Style.BODY))
	box.add_child(_gap())
	var back := UIButton.new()
	back.name = "Back"
	back.text = "Back"
	back.variant = UIButton.Variant.GHOST
	back.custom_minimum_size.x = 560.0
	back.pressed.connect(UIRouter.pop)
	box.add_child(back)
	initial_focus = get_path_to(back)


func _gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = _tokens.space_sm
	return gap


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label
