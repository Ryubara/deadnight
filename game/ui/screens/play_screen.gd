class_name PlayScreen
extends UIScreen
## Before a night on this machine: the match settings (`MatchSettingsPanel`) and a button that
## starts it. Start hands the settings to the night screen (`NightScreen.match_settings`) and opens
## it. Hosting for friends and joining are the lobby's and the Join screen's.
##
## Route to it with `UIRouter.push("res://ui/screens/play_screen.tscn")`.

const NIGHT_SCREEN := "res://ui/screens/night_screen.tscn"
const PANEL_WIDTH := 1000.0

var panel: MatchSettingsPanel
var start_button: UIButton
var back_button: UIButton
var reset_button: UIButton


func _ready() -> void:
	super._ready()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, _tokens.space_xl)
	add_child(margin)
	var centre := CenterContainer.new()
	margin.add_child(centre)
	var card := UIPanel.new()
	card.variant = UIPanel.Variant.MARQUEE
	centre.add_child(card)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = PANEL_WIDTH
	column.add_theme_constant_override(&"separation", _tokens.space_md)
	card.add_child(column)
	column.add_child(_label("NOW BOARDING", UILabel.Style.OVERLINE))
	column.add_child(_label("The night's rules", UILabel.Style.TITLE))
	panel = MatchSettingsPanel.new()
	column.add_child(panel)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", _tokens.space_md)
	column.add_child(footer)
	start_button = _button("Start the night", UIButton.Variant.PRIMARY)
	start_button.pressed.connect(start)
	footer.add_child(start_button)
	reset_button = _button("Usual rules", UIButton.Variant.SECONDARY)
	reset_button.pressed.connect(panel.set_settings.bind(MatchSettings.new()))
	footer.add_child(reset_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	back_button = _button("Back", UIButton.Variant.GHOST)
	back_button.pressed.connect(UIRouter.pop)
	footer.add_child(back_button)
	_link_focus()
	initial_focus = get_path_to(start_button)


## Opens the night under the panel's settings.
func start() -> void:
	NightScreen.match_settings = panel.settings()
	UIRouter.push(NIGHT_SCREEN, UITransition.Kind.IRIS)


## The arrow keys and the d-pad reach the buttons from the last row and the first row from them.
func _link_focus() -> void:
	var last := panel.last_control()
	var first := panel.first_control()
	for button in [start_button, reset_button, back_button]:
		button.focus_neighbor_top = button.get_path_to(last)
	last.focus_neighbor_bottom = last.get_path_to(start_button)
	first.focus_neighbor_top = first.get_path_to(start_button)


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label


func _button(text: String, variant: UIButton.Variant) -> UIButton:
	var button := UIButton.new()
	button.text = text
	button.variant = variant
	return button
