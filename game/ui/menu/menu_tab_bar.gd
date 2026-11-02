class_name MenuTabBar
extends HBoxContainer
## The tab bar: the five tabs' names in the wide face; the active one is a stub of paper with the
## name in ink, the others are cream on the dark. A tab is a focusable button, so the keyboard and
## the pad can walk the bar as well as press Q and E or the bumpers.

signal selected(tab: MenuTab.Id)

const PADDING := 22.0
## A phone's bar: smaller type (still over the 14 px floor: 28 units is 20 px), tighter stubs.
const COMPACT_SIZE := 28
const COMPACT_PADDING := 12.0

var tab := MenuTab.Id.PLAY

var _buttons := {}


func _init(compact := false) -> void:
	add_theme_constant_override(&"separation", 6 if compact else 12)
	for id in MenuTab.ORDER:
		var button := TabButton.new(id, compact)
		button.pressed.connect(_on_pressed.bind(id))
		add_child(button)
		_buttons[id] = button
	set_tab(MenuTab.Id.PLAY)


## Marks `to` as the active tab (it does not emit).
func set_tab(to: MenuTab.Id) -> void:
	tab = to
	for id: MenuTab.Id in _buttons:
		(_buttons[id] as TabButton).active = id == to


func button(id: MenuTab.Id) -> Button:
	return _buttons[id]


func _on_pressed(id: MenuTab.Id) -> void:
	selected.emit(id)


## One tab: its name, on paper while it is the active one.
class TabButton:
	extends Button
	var id := MenuTab.Id.PLAY
	var type_size := MenuLook.SIZE_TAB
	var padding := MenuTabBar.PADDING
	var active := false:
		set(value):
			active = value
			queue_redraw()

	func _init(tab_id: MenuTab.Id, compact := false) -> void:
		id = tab_id
		if compact:
			type_size = MenuTabBar.COMPACT_SIZE
			padding = MenuTabBar.COMPACT_PADDING
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		accessibility_name = MenuTab.label(tab_id)
		name = MenuTab.label(tab_id)
		var text_size := MenuLook.wide_font().get_string_size(
			MenuTab.label(tab_id).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, type_size
		)
		custom_minimum_size = Vector2(text_size.x + padding * 2.0, 64.0)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var lit := has_focus() or is_hovered()
		if active:
			MenuLook.draw_ticket(self, size, MenuLook.PAPER, MenuLook.PAPER_SHADE, 8.0)
		var colour := (
			MenuLook.PAPER_INK if active else (MenuLook.INK if lit else MenuLook.INK.darkened(0.12))
		)
		draw_string(
			MenuLook.wide_font(),
			Vector2(padding, 42.0),
			MenuTab.label(id).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			type_size,
			colour
		)
		if (has_focus() and not UIInputMode.pointer) or (lit and not active):
			draw_rect(Rect2(Vector2.ZERO, size), Color(MenuLook.AMBER, 0.8), false, 3.0)
