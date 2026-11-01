class_name SettingsScreen
extends UIScreen
## The settings screen: video, audio, accessibility and controls, each value bound to the
## `Settings` autoload. A change applies at once (the service does that); this screen only draws
## the controls, keeps them in step with the service and switches tabs.
##
## Route to it with `UIRouter.push("res://ui/screens/settings_screen.tscn")`.

const PANEL_WIDTH := 1200
const MAX_PAGE_ROWS := 4
const PERCENT := "%d%%"

## Each tab: a title and its rows. A row is {key, title, hint, kind} plus, by kind:
## slider: min, max, step, format; option: labels, values; toggle: nothing more.
const TABS := [
	{
		"title": "Video",
		"rows":
		[
			{
				"key": SettingsService.WINDOW_MODE,
				"title": "Window mode",
				"hint": "Ignored in a browser, which owns its window.",
				"kind": "option",
				"labels": ["Windowed", "Fullscreen", "Exclusive fullscreen"],
				"values":
				[
					SettingsService.WindowMode.WINDOWED,
					SettingsService.WindowMode.FULLSCREEN,
					SettingsService.WindowMode.EXCLUSIVE,
				],
			},
			{
				"key": SettingsService.RESOLUTION_SCALE,
				"title": "Resolution scale",
				"hint": "Draws the 3D world smaller; the interface stays sharp.",
				"kind": "slider",
				"min": 50,
				"max": 100,
				"step": 5,
				"format": PERCENT,
			},
			{
				"key": SettingsService.VSYNC,
				"title": "Vertical sync",
				"hint": "Off gives the lowest latency, and may tear.",
				"kind": "toggle",
			},
		],
	},
	{
		"title": "Audio",
		"rows":
		[
			{
				"key": SettingsService.VOLUME_MASTER,
				"title": "Master volume",
				"kind": "slider",
				"min": 0,
				"max": 100,
				"step": 5,
				"format": PERCENT,
			},
			{
				"key": SettingsService.VOLUME_MUSIC,
				"title": "Music",
				"kind": "slider",
				"min": 0,
				"max": 100,
				"step": 5,
				"format": PERCENT,
			},
			{
				"key": SettingsService.VOLUME_EFFECTS,
				"title": "Effects",
				"kind": "slider",
				"min": 0,
				"max": 100,
				"step": 5,
				"format": PERCENT,
			},
			{
				"key": SettingsService.VOLUME_UI,
				"title": "Interface sounds",
				"kind": "slider",
				"min": 0,
				"max": 100,
				"step": 5,
				"format": PERCENT,
			},
		],
	},
	{
		"title": "Accessibility",
		"rows":
		[
			{
				"key": SettingsService.REDUCED_MOTION,
				"title": "Reduced motion",
				"hint": "Screens cut or fade instead of sliding.",
				"kind": "toggle",
			},
			{
				"key": SettingsService.UI_SCALE,
				"title": "Interface size",
				"hint": "Scales every menu and the on-screen display.",
				"kind": "option",
				"labels": ["Small", "Normal", "Large"],
				"values": [0.8, 1.0, 1.25],
			},
		],
	},
	{
		"title": "Controls",
		"rows":
		[
			{
				"key": SettingsService.MOUSE_SENSITIVITY,
				"title": "Mouse sensitivity",
				"kind": "slider",
				"min": 0.1,
				"max": 3.0,
				"step": 0.05,
				"format": "%.2fx",
			},
			{
				"key": SettingsService.INVERT_Y,
				"title": "Invert Y axis",
				"hint": "Push the mouse forward to look down.",
				"kind": "toggle",
			},
		],
	},
]

var _bindings: Array[Dictionary] = []
var _tab_buttons: Array[UIButton] = []
var _pages: Array[VBoxContainer] = []
var _current := -1


func _ready() -> void:
	super._ready()
	_build()
	_sync_all()
	select_tab(0, false)


## Shows tab `index`; its rows rise in one after another unless `animate` is off.
func select_tab(index: int, animate := true) -> void:
	var target := clampi(index, 0, _pages.size() - 1)
	if target == _current:
		return
	_current = target
	for i in _pages.size():
		_pages[i].visible = i == target
		_tab_buttons[i].variant = (
			UIButton.Variant.PRIMARY if i == target else UIButton.Variant.GHOST
		)
	if animate:
		UIAudio.play(&"press")
	var rows: Array[Control] = []
	for row in _pages[target].get_children():
		if row.visible:
			rows.append(row)
	UIMotion.stagger_in(rows)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_page_down"):
		select_tab(mini(_current + 1, _pages.size() - 1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_page_up"):
		select_tab(maxi(_current - 1, 0))
		get_viewport().set_input_as_handled()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, _tokens.space_xl)
	add_child(margin)
	var centre := CenterContainer.new()
	margin.add_child(centre)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = PANEL_WIDTH
	column.add_theme_constant_override(&"separation", _tokens.space_md)
	centre.add_child(column)
	column.add_child(_label("OPTIONS", UILabel.Style.OVERLINE))
	column.add_child(_label("Settings", UILabel.Style.TITLE))
	column.add_child(_build_tabs())
	column.add_child(_build_panel())
	column.add_child(_build_footer())
	initial_focus = _tab_buttons[0].get_path()


func _build_tabs() -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override(&"separation", _tokens.space_sm)
	for i in TABS.size():
		var button := UIButton.new()
		button.text = TABS[i]["title"]
		button.variant = UIButton.Variant.GHOST
		button.pressed.connect(select_tab.bind(i))
		strip.add_child(button)
		_tab_buttons.append(button)
	return strip


func _build_panel() -> UIPanel:
	var panel := UIPanel.new()
	panel.variant = UIPanel.Variant.RAISED
	var row_height := _tokens.control_height + _tokens.space_md
	panel.custom_minimum_size.y = (MAX_PAGE_ROWS * row_height + 2 * _tokens.space_lg)
	var holder := VBoxContainer.new()
	panel.add_child(holder)
	for tab in TABS:
		var page := VBoxContainer.new()
		page.add_theme_constant_override(&"separation", _tokens.space_md)
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for spec: Dictionary in tab["rows"]:
			page.add_child(_build_row(spec))
		holder.add_child(page)
		_pages.append(page)
	return panel


func _build_row(spec: Dictionary) -> UIRow:
	var row := UIRow.new()
	row.title = spec["title"]
	row.hint = spec.get("hint", "")
	var key: StringName = spec["key"]
	match spec["kind"]:
		"slider":
			var slider := UISlider.new()
			slider.min_value = spec["min"]
			slider.max_value = spec["max"]
			slider.step = spec["step"]
			slider.value_changed.connect(
				func(value: float) -> void:
					Settings.set_value(key, value)
					row.set_value_text(spec["format"] % value)
			)
			row.set_control(slider)
			_bindings.append({"spec": spec, "control": slider, "row": row})
		"toggle":
			var toggle := UIToggle.new()
			toggle.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
			row.set_control(toggle)
			_bindings.append({"spec": spec, "control": toggle, "row": row})
		"option":
			var selector := UIOptionSelector.new()
			selector.options = PackedStringArray(spec["labels"])
			selector.selected_changed.connect(
				func(index: int) -> void: Settings.set_value(key, spec["values"][index])
			)
			row.set_control(selector)
			_bindings.append({"spec": spec, "control": selector, "row": row})
	return row


func _build_footer() -> HBoxContainer:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", _tokens.space_md)
	var reset := UIButton.new()
	reset.text = "Reset to defaults"
	reset.variant = UIButton.Variant.SECONDARY
	reset.pressed.connect(_on_reset)
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var back := UIButton.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: UIRouter.pop())
	footer.add_child(back)
	return footer


func _on_reset() -> void:
	Settings.reset_defaults()
	_sync_all()


## Puts every control at the service's value without firing its change signal.
func _sync_all() -> void:
	for binding in _bindings:
		var spec: Dictionary = binding["spec"]
		var control: Control = binding["control"]
		var value: Variant = Settings.get_value(spec["key"])
		if control is UISlider:
			(control as UISlider).set_value_no_signal(value)
			(binding["row"] as UIRow).set_value_text(spec["format"] % value)
		elif control is UIToggle:
			(control as UIToggle).set_pressed_no_signal(value)
		elif control is UIOptionSelector:
			(control as UIOptionSelector).select(_index_of(spec["values"], value), false)


static func _index_of(values: Array, value: Variant) -> int:
	for i in values.size():
		if is_equal_approx(float(values[i]), float(value)):
			return i
	return 0


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label
