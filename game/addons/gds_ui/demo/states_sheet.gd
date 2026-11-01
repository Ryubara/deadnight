extends UIScreen
## Every component in every state, side by side: the picture the pull request's contact sheet
## is taken from. Buttons are pinned to a state with `preview_state`.

const STATES := ["Normal", "Hover", "Pressed", "Focus", "Disabled"]
const VARIANT_NAMES := ["Primary", "Secondary", "Ghost"]


func _ready() -> void:
	super._ready()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, _tokens.space_xl)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", _tokens.space_lg)
	margin.add_child(root)
	root.add_child(_label("Component states", UILabel.Style.TITLE))
	root.add_child(_button_grid())
	root.add_child(_samples())


func _button_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = STATES.size() + 1
	grid.add_theme_constant_override(&"h_separation", _tokens.space_lg)
	grid.add_theme_constant_override(&"v_separation", _tokens.space_md)
	grid.add_child(Control.new())
	for state in STATES:
		grid.add_child(_label(state.to_upper(), UILabel.Style.OVERLINE))
	for v in VARIANT_NAMES.size():
		grid.add_child(_label(VARIANT_NAMES[v], UILabel.Style.CAPTION))
		for s in STATES.size():
			var button := UIButton.new()
			button.text = "Button"
			button.variant = v as UIButton.Variant
			button.preview_state = (s + 1) as UIButton.Preview
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.custom_minimum_size.x = 250.0
			grid.add_child(button)
	return grid


func _samples() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", _tokens.space_xl)
	var type_panel := UIPanel.new()
	type_panel.variant = UIPanel.Variant.FLAT
	var type_box := VBoxContainer.new()
	type_box.add_theme_constant_override(&"separation", 0)
	type_panel.add_child(type_box)
	var sample_styles := ["Overline", "Caption", "Body", "Heading", "Title", "Display"]
	for i in sample_styles.size():
		var style := (UILabel.Style.OVERLINE - i) as UILabel.Style
		type_box.add_child(_label(sample_styles[i] if i < 4 else "Aa " + sample_styles[i], style))
	row.add_child(type_panel)
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override(&"separation", _tokens.space_lg)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for v in UIPanel.Variant.size():
		var panel := UIPanel.new()
		panel.variant = v as UIPanel.Variant
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_child(
			_label(["Flat panel", "Raised panel", "Marquee panel"][v], UILabel.Style.HEADING)
		)
		cards.add_child(panel)
	row.add_child(cards)
	return row


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label
