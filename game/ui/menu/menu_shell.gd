class_name MenuShell
extends Control
## The main menu's tab shell: the live stage behind everything, a scrim on the panel's side, the
## tab bar, the account plate, the input hints, and one panel for the tab on show. It owns no
## route: a panel asks through `context.action` and the main menu decides.
##
## Tabs change with a click or a tap on the bar, Q and E, Ctrl+Tab, the bumpers, or by walking
## the bar with the arrows. The camera goes to the tab's pose at once.

signal tab_changed(tab: MenuTab.Id)

const PAD := 64.0
const PAD_COMPACT := 28.0
const TOP := 150.0
const TOP_COMPACT := 104.0
const BOTTOM := 96.0
const BOTTOM_COMPACT := 64.0
## Radians per second of the soldier's turn at full right stick, and per pixel of a drag.
const STICK_SPEED := 3.2
const DRAG_SPEED := 0.011
## Seconds a panel takes to arrive, and the metres... the design units it slides.
const ARRIVE_SECONDS := 0.28
const ARRIVE_SLIDE := 28.0

## Set before the shell enters the tree: -1 follows the window, 0 forces the desktop layout, 1 the
## phone's (a test or a capture).
var phone_mode := -1
## A test or a capture steps the stage itself.
var manual_stage := false
var context := MenuContext.new()
var tab := MenuTab.Id.PLAY
var view: MenuStageView
var tab_bar: MenuTabBar
var plate: MenuPlate
var hints: MenuHints

var _panels := {}
var _host: Control
var _scrim: TextureRect
var _turn_pad: Control
var _compact := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_compact = _is_compact()
	context.compact = _compact
	_apply_scale()
	# Back on top after a night: the phone factor the night set aside comes back.
	visibility_changed.connect(_apply_scale)
	get_window().size_changed.connect(_on_window_resized)
	Settings.changed.connect(_on_setting)
	context.leaving.connect(commit)
	view = MenuStageView.new()
	view.manual = manual_stage
	context.stage = view
	add_child(view)
	_build_scrims()
	_turn_pad = _TurnPad.new(self)
	add_child(_turn_pad)
	_host = Control.new()
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_host)
	_build_chrome()
	for id in MenuTab.ORDER:
		_panels[id] = _make_panel(id)
	show_tab(MenuTab.Id.PLAY, false)


func _exit_tree() -> void:
	commit()
	if Settings.changed.is_connected(_on_setting):
		Settings.changed.disconnect(_on_setting)
	var window := get_window()
	if window != null:
		if window.size_changed.is_connected(_on_window_resized):
			window.size_changed.disconnect(_on_window_resized)
		# The player's own UI scale comes back, whatever the phone factor was.
		window.content_scale_factor = float(Settings.get_value(SettingsService.UI_SCALE))


func _notification(what: int) -> void:
	# A browser has no close request: losing focus is the last chance to write what a panel holds.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		commit()


func _process(delta: float) -> void:
	if tab != MenuTab.Id.LOADOUT:
		return
	var stick := Input.get_axis(&"look_left", &"look_right")
	if absf(stick) > 0.1:
		view.turn(stick * STICK_SPEED * delta)


func _input(event: InputEvent) -> void:
	var step := MenuNav.tab_step(event)
	if step == 0 or not _is_on_top():
		return
	show_tab(MenuTab.neighbour(tab, step))
	_focus_panel()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Back from inside a panel goes to the tab bar; at the bar there is nowhere to go.
	if not event.is_action_pressed(&"ui_cancel"):
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and not tab_bar.is_ancestor_of(focused):
		tab_bar.button(tab).grab_focus()
		get_viewport().set_input_as_handled()


## Shows the panel of a tab and sends the camera to its pose.
func show_tab(to: MenuTab.Id, animate := true) -> void:
	var previous: MenuPanel = _panels.get(tab)
	if previous != null and previous.visible and to != tab:
		previous.visible = false
		previous.on_hide()
	tab = to
	tab_bar.set_tab(to)
	view.set_compact(_compact)
	view.show_tab(to)
	var panel: MenuPanel = _panels[to]
	_place(panel)
	panel.visible = true
	panel.on_show()
	_scrim.flip_h = panel.side() == MenuPanel.Side.LEFT
	_turn_pad.mouse_filter = (
		Control.MOUSE_FILTER_STOP if to == MenuTab.Id.LOADOUT else Control.MOUSE_FILTER_IGNORE
	)
	_link_focus(panel)
	if animate:
		_arrive(panel)
	tab_changed.emit(to)


## The panel of a tab.
func panel(id: MenuTab.Id) -> MenuPanel:
	return _panels[id]


## Has the panel on show write what it holds (a panel with nothing to keep does nothing). The
## shell does it by itself when the tab changes, a screen is asked for, the menu closes or leaves.
func commit() -> void:
	var shown: MenuPanel = _panels.get(tab)
	if shown != null and is_instance_valid(shown):
		shown.commit()


## Shows a fresh profile (the plate and the panels that read it).
func set_profile(profile: MenuProfile) -> void:
	context.profile = profile
	plate.show_profile(profile)
	refresh_panels()


## Re-reads what the panel on show holds (the menu is shown again, or the data changed).
func refresh_panels() -> void:
	if _panels.is_empty():
		return
	(_panels[tab] as MenuPanel).refresh()


## Whether the window is a phone's.
func is_compact() -> bool:
	return _compact


## Puts the focus on the tab's first control (after a tab change by bumper or key).
func focus_panel() -> void:
	_focus_panel()


## Whether the shell is what the player is looking at: shown, and not under another screen of the
## router (a menu left below Settings must not answer its bumpers).
func _is_on_top() -> bool:
	if not is_visible_in_tree():
		return false
	var top := UIRouter.top()
	return top == null or top == self or top.is_ancestor_of(self)


func _is_compact() -> bool:
	if phone_mode >= 0:
		return phone_mode == 1
	# A headless run has a 64 pixel window that is nobody's phone.
	if DisplayServer.get_name() == "headless":
		return false
	return MenuScale.is_phone(get_window().size)


## The phone factor is the menu's: it is on while the menu shows, and a screen pushed over it (the
## night) runs on the player's own scale, the one its HUD and touch layer are made for (#606: the
## night at the factor was 540 units high, with half the touch buttons off the top).
func _apply_scale() -> void:
	if not is_visible_in_tree():
		return
	var ui_scale := float(Settings.get_value(SettingsService.UI_SCALE))
	var window := get_window()
	window.content_scale_factor = ui_scale * (MenuScale.PHONE_FACTOR if _compact else 1.0)


func _on_window_resized() -> void:
	var now := _is_compact()
	if now == _compact:
		return
	_compact = now
	context.compact = now
	_apply_scale()


func _on_setting(key: StringName, _value: Variant) -> void:
	# The settings service applies the UI scale to the root itself: put the phone factor back.
	if key == SettingsService.UI_SCALE:
		_apply_scale.call_deferred()


func _build_scrims() -> void:
	# Solid under the panel, then a fade out over the last part of the width.
	var fade := Gradient.new()
	fade.set_color(0, MenuLook.SCRIM)
	fade.add_point(0.7, MenuLook.SCRIM)
	fade.set_color(2, Color(MenuLook.SCRIM, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = fade
	texture.fill_from = Vector2(1.0, 0.0)
	texture.fill_to = Vector2(0.0, 0.0)
	_scrim = TextureRect.new()
	_scrim.texture = texture
	_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.anchor_bottom = 1.0
	add_child(_scrim)
	for top in [true, false]:
		var strip := ColorRect.new()
		strip.color = Color(MenuLook.SCRIM, 0.55)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.anchor_right = 1.0
		if top:
			strip.offset_bottom = TOP - 30.0 if not _compact else TOP_COMPACT - 24.0
		else:
			strip.anchor_top = 1.0
			strip.anchor_bottom = 1.0
			strip.offset_top = -(BOTTOM if not _compact else BOTTOM_COMPACT)
		add_child(strip)


func _build_chrome() -> void:
	var pad := PAD_COMPACT if _compact else PAD
	tab_bar = MenuTabBar.new(_compact)
	tab_bar.position = Vector2(pad, 26.0)
	tab_bar.selected.connect(_on_tab_pressed)
	add_child(tab_bar)
	plate = MenuPlate.new(_compact)
	plate.anchor_left = 1.0
	plate.anchor_right = 1.0
	var plate_width := MenuPlate.COMPACT_WIDTH if _compact else MenuPlate.SIZE.x
	plate.offset_left = -pad - plate_width
	plate.offset_right = -pad
	plate.offset_top = 22.0
	plate.offset_bottom = 22.0 + MenuPlate.SIZE.y
	add_child(plate)
	plate.show_profile(context.profile)
	context.profile_changed.connect(func() -> void: plate.show_profile(context.profile))
	hints = MenuHints.new()
	hints.anchor_top = 1.0
	hints.anchor_bottom = 1.0
	hints.offset_left = pad
	hints.offset_top = -(BOTTOM_COMPACT if _compact else BOTTOM) + 14.0
	hints.offset_bottom = -10.0
	add_child(hints)


func _make_panel(id: MenuTab.Id) -> MenuPanel:
	var node: MenuPanel
	match id:
		MenuTab.Id.LOADOUT:
			node = LoadoutPanel.new()
		MenuTab.Id.SHOP:
			node = ShopPanel.new()
		MenuTab.Id.CHALLENGES:
			node = ChallengesPanel.new()
		MenuTab.Id.MORE:
			node = MorePanel.new()
		_:
			node = PlayPanel.new()
	node.context = context
	node.name = "%sPanel" % MenuTab.label(id)
	node.visible = false
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(node)
	return node


func _place(panel: MenuPanel) -> void:
	var pad := PAD_COMPACT if _compact else PAD
	var top := TOP_COMPACT if _compact else TOP
	var bottom := BOTTOM_COMPACT if _compact else BOTTOM
	var wide := minf(panel.width(_compact), size.x * 0.7)
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_top = top
	panel.offset_bottom = -bottom
	if panel.side() == MenuPanel.Side.LEFT:
		panel.anchor_left = 0.0
		panel.anchor_right = 0.0
		panel.offset_left = pad
		panel.offset_right = pad + wide
	else:
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.offset_left = -pad - wide
		panel.offset_right = -pad
	var reach := wide + pad * 3.0
	if panel.side() == MenuPanel.Side.LEFT:
		_scrim.anchor_left = 0.0
		_scrim.anchor_right = 0.0
		_scrim.offset_left = 0.0
		_scrim.offset_right = reach
	else:
		_scrim.anchor_left = 1.0
		_scrim.anchor_right = 1.0
		_scrim.offset_left = -reach
		_scrim.offset_right = 0.0


func _arrive(panel: MenuPanel) -> void:
	if UIMotion.reduced:
		panel.modulate.a = 1.0
		return
	var slide := ARRIVE_SLIDE if panel.side() == MenuPanel.Side.RIGHT else -ARRIVE_SLIDE
	panel.modulate.a = 0.0
	var tween := panel.create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, ARRIVE_SECONDS)
	tween.tween_property(panel, "position:x", panel.position.x, ARRIVE_SECONDS).from(
		panel.position.x + slide
	)


func _on_tab_pressed(id: MenuTab.Id) -> void:
	show_tab(id)


func _focus_panel() -> void:
	var target := (_panels[tab] as MenuPanel).first_focus()
	if target != null and target.is_visible_in_tree():
		target.grab_focus()


## Down from the bar enters the panel, Up from the panel's first control returns to the bar.
func _link_focus(panel: MenuPanel) -> void:
	var first := panel.first_focus()
	if first == null:
		return
	for id: MenuTab.Id in MenuTab.ORDER:
		var button := tab_bar.button(id)
		button.focus_neighbor_bottom = button.get_path_to(first)
	first.focus_neighbor_top = first.get_path_to(tab_bar.button(tab))


## A transparent control behind the panels that turns the soldier when it is dragged (Loadout).
class _TurnPad:
	extends Control
	var _shell: MenuShell

	func _init(shell: MenuShell) -> void:
		_shell = shell
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_default_cursor_shape = Control.CURSOR_HSIZE

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var motion := event as InputEventMouseMotion
			if motion.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
				_shell.view.turn(motion.relative.x * MenuShell.DRAG_SPEED)
				accept_event()
