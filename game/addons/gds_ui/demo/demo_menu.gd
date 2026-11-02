extends UIScreen
## Demo menu: one button per transition, a reduced-motion toggle, and the component sheet.

const DETAIL := "res://addons/gds_ui/demo/demo_detail.tscn"
const SHEET := "res://addons/gds_ui/demo/states_sheet.tscn"
const CONTROLS := "res://addons/gds_ui/demo/controls_sheet.tscn"
## Name, transition, and the token whose colour tints the screen it opens (so the change of screen
## shows in any palette).
const ENTRIES := [
	["Fade", UITransition.Kind.FADE, &"accent"],
	["Slide", UITransition.Kind.SLIDE, &"ink_muted"],
	["Film burn", UITransition.Kind.BURN, &"hot"],
	["Iris", UITransition.Kind.IRIS, &"accent_bright"],
]
const TINT_SHARE := 0.35

var _reduced_button: UIButton


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
	box.add_child(_label("UI DEMO", UILabel.Style.OVERLINE))
	box.add_child(_label("Pick a transition", UILabel.Style.TITLE))
	for entry in ENTRIES:
		var button := _button(entry[0], UIButton.Variant.PRIMARY)
		button.pressed.connect(_open_detail.bind(entry[0], entry[1], entry[2]))
		box.add_child(button)
	var sheet := _button("Component sheet", UIButton.Variant.SECONDARY)
	sheet.pressed.connect(func() -> void: UIRouter.push(SHEET, UITransition.Kind.SLIDE))
	box.add_child(sheet)
	var controls := _button("Form controls", UIButton.Variant.SECONDARY)
	controls.pressed.connect(func() -> void: UIRouter.push(CONTROLS, UITransition.Kind.SLIDE))
	box.add_child(controls)
	_reduced_button = _button("", UIButton.Variant.GHOST)
	_reduced_button.pressed.connect(_toggle_reduced)
	box.add_child(_reduced_button)
	_refresh_reduced()
	allow_back = false
	UIMotion.stagger_in(_stagger_targets(box))


func _stagger_targets(box: Control) -> Array[Control]:
	var out: Array[Control] = []
	for child in box.get_children():
		out.append(child as Control)
	return out


func _open_detail(title: String, kind: UITransition.Kind, tint_token: StringName) -> void:
	var tint := _tokens.bg_glow.lerp(_tokens.get(tint_token) as Color, TINT_SHARE)
	UIRouter.push(DETAIL, kind, {"title": title, "tint": tint})


func _toggle_reduced() -> void:
	UIMotion.reduced = not UIMotion.reduced
	_refresh_reduced()


func _refresh_reduced() -> void:
	_reduced_button.text = "Reduced motion: %s" % ("on" if UIMotion.reduced else "off")


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label


func _button(text: String, variant: UIButton.Variant) -> UIButton:
	var button := UIButton.new()
	button.text = text
	button.variant = variant
	button.custom_minimum_size.x = 560.0
	return button
