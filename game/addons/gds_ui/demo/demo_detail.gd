extends UIScreen
## Demo destination screen: named for the transition that brought it here, tinted so the
## change of screen is easy to see, with a Back button.


func _ready() -> void:
	super._ready()
	glow = params.get("tint", _tokens.bg_glow)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.RAISED
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", _tokens.space_lg)
	panel.add_child(box)
	box.add_child(_label("NOW SHOWING", UILabel.Style.OVERLINE))
	box.add_child(_label(str(params.get("title", "Screen")), UILabel.Style.DISPLAY))
	box.add_child(_label("Esc or the Back button returns the way it came.", UILabel.Style.CAPTION))
	var back := UIButton.new()
	back.text = "Back"
	back.variant = UIButton.Variant.SECONDARY
	back.pressed.connect(func() -> void: UIRouter.pop())
	box.add_child(back)
	initial_focus = back.get_path()


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label
