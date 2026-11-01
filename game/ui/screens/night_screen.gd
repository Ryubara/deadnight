class_name NightScreen
extends UIScreen
## The night as a screen: the 3D night underneath, a plain readout (until the HUD, #89, lands), a
## pause menu on Esc and a result when the night is over. Both ways out lead back to the menu.
##
## Route to it with `UIRouter.push("res://ui/screens/night_screen.tscn")`; the main menu's Play
## does.

const READOUT_MARGIN := 24
const PANEL_WIDTH := 520.0
const DIM := Color(0.0, 0.0, 0.0, 0.55)

var night: Night

var _readout: Label
var _overlay: Control
var _title: UILabel
var _note: UILabel
var _resume: UIButton
var _quit: UIButton


func _ready() -> void:
	super._ready()
	night = Night.new()
	add_child(night)
	_build_readout()
	_build_overlay()
	night.night_over.connect(_on_night_over)


func screen_enter() -> void:
	await night.start(Night.Mode.HUMAN)


func screen_pause() -> void:
	if night.running:
		_pause()


func screen_resume() -> void:
	pass


## The night is the backdrop; this screen paints none of its own.
func _draw() -> void:
	pass


func _process(_delta: float) -> void:
	if night.state != null and night.state.has_frame():
		_readout.text = NightReadout.text_for(night.state)


func _unhandled_input(event: InputEvent) -> void:
	if night.state == null or night.state.over:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		if night.is_paused():
			_resume_night()
		else:
			_pause()
		get_viewport().set_input_as_handled()


func _pause() -> void:
	night.set_paused(true)
	_show_overlay("Paused", "The dead wait.", true)


func _resume_night() -> void:
	_overlay.hide()
	night.set_paused(false)


func _on_night_over(round_reached: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var points: int = night.state.points_earned
	_show_overlay(
		"You did not make it", "Round %d.  %d points earned." % [round_reached, points], false
	)


func _show_overlay(title: String, note: String, can_resume: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = title
	_note.text = note
	_resume.visible = can_resume
	_overlay.show()
	(_resume if can_resume else _quit).grab_focus()


func _leave() -> void:
	UIRouter.pop()


func _build_readout() -> void:
	_readout = Label.new()
	_readout.position = Vector2(READOUT_MARGIN, READOUT_MARGIN)
	_readout.add_theme_font_size_override(&"font_size", _tokens.font_body)
	_readout.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_readout.add_theme_constant_override(&"outline_size", 8)
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_readout)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.hide()
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(centre)
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.MARQUEE
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = PANEL_WIDTH
	box.add_theme_constant_override(&"separation", _tokens.space_md)
	panel.add_child(box)
	_title = _label(UILabel.Style.TITLE)
	_note = _label(UILabel.Style.BODY)
	box.add_child(_title)
	box.add_child(_note)
	_resume = _button("Resume", UIButton.Variant.PRIMARY)
	_resume.pressed.connect(_resume_night)
	_quit = _button("Back to the menu", UIButton.Variant.SECONDARY)
	_quit.pressed.connect(_leave)
	box.add_child(_resume)
	box.add_child(_quit)


func _label(style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.style = style
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(text: String, variant: UIButton.Variant) -> UIButton:
	var button := UIButton.new()
	button.text = text
	button.variant = variant
	return button
