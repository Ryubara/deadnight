class_name PlayScreen
extends UIScreen
## Before a night on this machine: the match settings (`MatchSettingsPanel`) and a button that
## starts it. Start hands the settings to the night screen (`NightScreen.match_settings`) and opens
## it. Hosting for friends and joining are the lobby's and the Join screen's.
##
## Route to it with `UIRouter.push("res://ui/screens/play_screen.tscn")`.

const NIGHT_SCREEN := "res://ui/screens/night_screen.tscn"
const PANEL_WIDTH := 1000.0
## A canvas this high or lower is a phone held sideways (the phone factor makes it 540 units).
const COMPACT_HEIGHT := 600.0
const MARGIN_SIDES: Array[StringName] = [
	&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"
]

var panel: MatchSettingsPanel
var start_button: UIButton
var back_button: UIButton
var reset_button: UIButton

var _margin: MarginContainer
var _card: UIPanel
var _rules_scroll: UIFitScroll
var _column: VBoxContainer
var _overline: UILabel
var _title: UILabel


func _ready() -> void:
	super._ready()
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var centre := CenterContainer.new()
	_margin.add_child(centre)
	var card := UIPanel.new()
	_card = card
	card.variant = UIPanel.Variant.MARQUEE
	centre.add_child(card)
	var column := VBoxContainer.new()
	_column = column
	column.custom_minimum_size.x = PANEL_WIDTH
	column.add_theme_constant_override(&"separation", _tokens.space_md)
	card.add_child(column)
	_overline = _label("NOW BOARDING", UILabel.Style.OVERLINE)
	column.add_child(_overline)
	_title = _label("The night's rules", UILabel.Style.TITLE)
	column.add_child(_title)
	panel = MatchSettingsPanel.new()
	# The rules scroll in what height the canvas leaves (a Large interface size is 864 units high),
	# and the title above and the buttons below stay where they are (#980).
	_rules_scroll = UIFitScroll.new()
	_rules_scroll.name = "Rules"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules_scroll.add_child(panel)
	column.add_child(_rules_scroll)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", _tokens.space_md)
	column.add_child(footer)
	start_button = _button("Start the night", UIButton.Variant.PRIMARY)
	start_button.pressed.connect(start)
	start_button.name = &"Start"
	footer.add_child(start_button)
	reset_button = _button("Usual rules", UIButton.Variant.SECONDARY)
	reset_button.pressed.connect(panel.set_settings.bind(MatchSettings.new()))
	reset_button.name = &"Reset"
	footer.add_child(reset_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	back_button = _button("Back", UIButton.Variant.GHOST)
	back_button.pressed.connect(UIRouter.pop)
	back_button.name = &"Back"
	footer.add_child(back_button)
	_link_focus()
	initial_focus = get_path_to(start_button)
	resized.connect(_fit_for_fingers)
	_fit_for_fingers()


## The rules on the panel as the web probe reads them: `2x|Auto|20 s`.
func rules_text() -> String:
	return panel.text()


## Opens the night under the panel's settings.
func start() -> void:
	# The level opens the map: a choice the level does not open (a map handed in, a level that fell)
	# is the default map, whatever the panel holds.
	NightScreen.match_settings = panel.settings().fit_host(panel.map_picker.level)
	UIRouter.push(NIGHT_SCREEN, UITransition.Kind.IRIS)


## On a phone held sideways every row and button is a tap target high, and the overline, the title,
## the hints and the margins give their room back (the canvas is 540 units high and the five rows,
## the buttons and the panel's edge already fill most of it, #671).
func _fit_for_fingers() -> void:
	var phone := size.y <= COMPACT_HEIGHT
	panel.set_compact(phone)
	_overline.visible = not phone
	_title.visible = not phone
	_column.add_theme_constant_override(
		&"separation", _tokens.space_sm if phone else _tokens.space_md
	)
	var margin_size := _tokens.space_md if phone else _tokens.space_xl
	for side in MARGIN_SIDES:
		_margin.add_theme_constant_override(side, margin_size)
	if phone:
		# The canvas is only 540 units high: the panel keeps a thin edge above and below.
		_margin.add_theme_constant_override(&"margin_top", _tokens.space_sm)
		_margin.add_theme_constant_override(&"margin_bottom", _tokens.space_sm)
	_rules_scroll.margin = float(_tokens.space_sm if phone else _tokens.space_xl)
	# The column is as wide as the canvas leaves: a phone's narrowest canvas is 960 units wide.
	var around := 2.0 * float(margin_size) + _card.get_theme_stylebox(&"panel").get_minimum_size().x
	_column.custom_minimum_size.x = minf(PANEL_WIDTH, size.x - around)
	for button in [start_button, reset_button, back_button]:
		(button as Control).custom_minimum_size.y = MenuLook.TAP_TARGET if phone else 0.0
	# The phone's map cards sit two to a row: the first row is the one Up leaves from.
	_link_focus()


## The arrow keys and the d-pad reach the buttons from the last row and the first row from them.
func _link_focus() -> void:
	var last := panel.last_control()
	for button in [start_button, reset_button, back_button]:
		button.focus_neighbor_top = button.get_path_to(last)
	last.focus_neighbor_bottom = last.get_path_to(start_button)
	for first in panel.first_controls():
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
