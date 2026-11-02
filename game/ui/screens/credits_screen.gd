class_name CreditsScreen
extends UIScreen
## Credits: reads a CreditsList and lists it, a section at a time, over the night sky.
##
## The card is as tall as the window allows: the title on top, Back below, and the list between
## them scrolls, so a long list never pushes Back off the screen. Up and Down (and a gamepad's
## D-pad) scroll it while Back keeps the focus; the mouse wheel scrolls it too.

## Width of the card.
const CARD_WIDTH := 640.0
## How far one Up or Down press scrolls the list, in lines of caption text.
const SCROLL_LINES := 2.0
## Pixels the list scrolls for a page.
const PAGE_FRACTION := 0.85

@export var credits: CreditsList = preload("res://ui/credits.tres")

var scroll: ScrollContainer
var back_button: UIButton


func _ready() -> void:
	super._ready()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, _tokens.space_lg)
	add_child(margin)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	panel.custom_minimum_size.x = CARD_WIDTH
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(panel)
	var card := VBoxContainer.new()
	card.add_theme_constant_override(&"separation", _tokens.space_sm)
	panel.add_child(card)
	card.add_child(_label("THE END CREDITS", UILabel.Style.OVERLINE))
	card.add_child(_label("Credits", UILabel.Style.TITLE))
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(scroll)
	var box := VBoxContainer.new()
	box.name = "List"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", _tokens.space_sm)
	scroll.add_child(box)
	for section in credits.sections():
		box.add_child(_gap())
		if section["heading"] != "":
			box.add_child(_label(str(section["heading"]).to_upper(), UILabel.Style.OVERLINE))
		for line in section["names"]:
			var name_label := _label(line, UILabel.Style.CAPTION)
			# The full ink keeps the long list readable.
			name_label.add_theme_color_override(&"font_color", _tokens.ink)
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(name_label)
	back_button = UIButton.new()
	back_button.name = "Back"
	back_button.text = "Back"
	back_button.variant = UIButton.Variant.GHOST
	back_button.pressed.connect(UIRouter.pop)
	card.add_child(back_button)
	initial_focus = get_path_to(back_button)


## Scrolls the list one step (negative is up) or a page (`pages`), and clamps to its ends.
func scroll_by(steps: float, pages := false) -> void:
	var step := scroll.size.y * PAGE_FRACTION if pages else _line_height() * SCROLL_LINES
	scroll.scroll_vertical = clampi(
		scroll.scroll_vertical + roundi(steps * step), 0, int(_scroll_end())
	)


## Where the list ends, in scroll units.
func _scroll_end() -> float:
	return maxf(scroll.get_v_scroll_bar().max_value - scroll.size.y, 0.0)


func _line_height() -> float:
	return scroll.get_theme_default_font().get_height(scroll.get_theme_default_font_size()) * 1.5


## Up and Down scroll the list: Back is the only control that takes focus, so there is no
## neighbour for the focus to move to.
func _input(event: InputEvent) -> void:
	if UIRouter.top() != self or UIRouter.busy:
		return
	var moves := {
		&"ui_up": [-1.0, false],
		&"ui_down": [1.0, false],
		&"ui_page_up": [-1.0, true],
		&"ui_page_down": [1.0, true],
	}
	for action: StringName in moves:
		if event.is_action_pressed(action, true):
			scroll_by(moves[action][0], moves[action][1])
			get_viewport().set_input_as_handled()
			return


func _gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = _tokens.space_sm
	return gap


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label
