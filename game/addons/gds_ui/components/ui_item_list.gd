@tool
class_name UIItemList
extends Control
## A list of text rows to pick from. Up and Down (or the d-pad) move the choice, accept activates
## it, the wheel scrolls, a click selects and a double click activates. The highlight slides
## between rows on a spring, the hovered row is tinted, and a list longer than `visible_rows`
## scrolls with a thin bar on its right edge. Self-contained: it needs no ScrollContainer.

signal item_selected(index: int)
signal item_activated(index: int)

## Pins the look for the demo sheet and captures: what a real hover or keyboard focus shows.
enum Preview { NONE, HOVER, FOCUS }

## How many rows one turn of the wheel scrolls.
const WHEEL_ROWS := 1.5
## The width of the scroll bar, as a share of the border width times two.
const BAR_WIDTH_BORDERS := 2.0

@export var items := PackedStringArray():
	set(value):
		items = value
		_selected = clampi(_selected, -1, items.size() - 1)
		_apply_tokens()
		_snap_to_selection()
## The rows shown at once; the list scrolls past them. Zero shows them all.
@export var visible_rows := 6:
	set(value):
		visible_rows = maxi(value, 0)
		_apply_tokens()
## The chosen row, or -1 for none.
@export var selected := -1:
	get:
		return _selected
	set(value):
		select(value, false)
@export var preview_state := Preview.NONE:
	set(value):
		preview_state = value
		set_process(true)

var _tokens := UITokens.active()
var _selected := -1
var _hover_row := -1
var _inside := false
var _keys_focus := false
## Row positions in rows (the highlight, the hover tint and the scroll), and how strongly each
## shows.
var _bar_at: UISpring
var _bar_on: UISpring
var _hover_at: UISpring
var _hover_on: UISpring
var _scroll: UISpring
var _focus: UISpring
var _ring: UIFocusRing
var _fill := StyleBoxFlat.new()


func _init() -> void:
	_bar_at = UISpring.new()
	_bar_on = UISpring.new()
	_hover_at = UISpring.new()
	_hover_on = UISpring.new()
	_scroll = UISpring.new()
	_focus = UISpring.new()
	_fill.anti_aliasing = true
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_tokens()


## Reads the active tokens into everything this control caches: spring tuning, shapes and size.
func _apply_tokens() -> void:
	_tokens = UITokens.active()
	for spring in [_bar_at, _scroll]:
		spring.stiffness = _tokens.spring_stiffness * 1.4
		spring.damping = _tokens.spring_damping * 1.1
	for spring in [_bar_on, _hover_on, _hover_at]:
		spring.stiffness = _tokens.spring_stiffness
		spring.damping = _tokens.spring_damping
	_focus.stiffness = _tokens.spring_stiffness * 0.7
	_focus.damping = _tokens.spring_damping * 0.8
	_ring = UIFocusRing.new(_tokens, _tokens.radius_md)
	_fill.set_corner_radius_all(_tokens.radius_md)
	_fill.set_border_width_all(_tokens.border)
	var rows := items.size() if visible_rows == 0 else mini(visible_rows, items.size())
	custom_minimum_size = Vector2(
		_tokens.control_width * 0.5, maxf(rows, 1.0) * row_height() + 2.0 * _tokens.border
	)
	queue_redraw()


func _on_tokens_changed(_next: UITokens) -> void:
	_apply_tokens()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	UITokens.active_changed().connect(_on_tokens_changed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	resized.connect(_keep_selection_in_view)
	_update_targets()
	_snap_to_selection()


## The height of one row, in pixels.
func row_height() -> float:
	return float(_tokens.control_height) * 0.85


## Chooses a row (clamped; -1 for none). Emits `item_selected` if it changed and `emit` is set.
func select(index: int, emit := true) -> void:
	var clamped := clampi(index, -1, items.size() - 1)
	if clamped == _selected:
		return
	_selected = clamped
	_keep_selection_in_view()
	set_process(true)
	if emit:
		UIAudio.play(&"tick", self)
		item_selected.emit(_selected)


## Activates the chosen row: emits `item_activated`. Does nothing with no choice.
func activate() -> void:
	if _selected < 0:
		return
	UIAudio.play(&"press", self)
	item_activated.emit(_selected)


## How many rows fit in the list at its size now (at least one).
func rows_shown() -> int:
	return maxi(int((size.y - 2.0 * _tokens.border) / row_height()), 1)


## The row at the top of the list, as a fraction while it scrolls.
func top_row() -> float:
	return _scroll.value


## The row under a point in the control's own coordinates, or -1 when it is on none.
func row_at(point: Vector2) -> int:
	var row := int(floorf((point.y - _tokens.border) / row_height() + _scroll.target))
	return row if row >= 0 and row < items.size() and point.y >= 0.0 else -1


func _process(delta: float) -> void:
	_update_targets()
	var settled := true
	for spring in [_bar_at, _bar_on, _hover_at, _hover_on, _scroll, _focus]:
		if UIMotion.reduced:
			spring.snap(spring.target)
		spring.step(delta)
		settled = settled and spring.is_settled()
	queue_redraw()
	if settled:
		set_process(false)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT]:
		set_process(true)
	elif what == NOTIFICATION_DRAW and not is_processing():
		_update_targets()
		var springs := [_bar_at, _bar_on, _hover_at, _hover_on, _scroll, _focus]
		if not springs.all(func(spring: UISpring) -> bool: return spring.is_settled()):
			set_process(true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_row = row_at((event as InputEventMouseMotion).position)
		set_process(true)
	elif event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event.is_action_pressed(&"ui_down", true):
		select(maxi(_selected + 1, 0))
		accept_event()
	elif event.is_action_pressed(&"ui_up", true):
		select(maxi(_selected - 1, 0))
		accept_event()
	elif event.is_action_pressed(&"ui_page_down", true):
		select(mini(maxi(_selected, 0) + rows_shown(), items.size() - 1))
		accept_event()
	elif event.is_action_pressed(&"ui_page_up", true):
		select(maxi(maxi(_selected, 0) - rows_shown(), 0))
		accept_event()
	elif event.is_action_pressed(&"ui_home"):
		select(0)
		accept_event()
	elif event.is_action_pressed(&"ui_end"):
		select(items.size() - 1)
		accept_event()
	elif event.is_action_pressed(&"ui_accept"):
		activate()
		accept_event()


func _mouse_button(click: InputEventMouseButton) -> void:
	if not click.pressed:
		return
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			var row := row_at(click.position)
			if row < 0:
				return
			select(row)
			if click.double_click:
				activate()
			accept_event()
		MOUSE_BUTTON_WHEEL_UP:
			_scroll_rows(-WHEEL_ROWS)
			accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_rows(WHEEL_ROWS)
			accept_event()


func _scroll_rows(rows: float) -> void:
	_scroll.target = clampf(_scroll.target + rows, 0.0, _last_top())
	_hover_row = row_at(get_local_mouse_position())
	set_process(true)


## The highest row the list can scroll to the top.
func _last_top() -> float:
	return maxf(float(items.size() - rows_shown()), 0.0)


## Scrolls just far enough that the chosen row is in view.
func _keep_selection_in_view() -> void:
	if _selected < 0:
		return
	var first := _scroll.target
	if float(_selected) < first:
		_scroll.target = float(_selected)
	elif float(_selected + 1) > first + rows_shown():
		_scroll.target = float(_selected + 1 - rows_shown())
	_scroll.target = clampf(_scroll.target, 0.0, _last_top())


func _snap_to_selection() -> void:
	_keep_selection_in_view()
	_scroll.snap(_scroll.target)
	_bar_at.snap(float(maxi(_selected, 0)))
	_bar_on.snap(1.0 if _selected >= 0 else 0.0)


func _update_targets() -> void:
	_bar_at.target = float(maxi(_selected, 0))
	_bar_on.target = 1.0 if _selected >= 0 else 0.0
	var pointed := _inside and _hover_row >= 0
	var lit_row := _hover_row if pointed else -1
	if preview_state == Preview.HOVER:
		lit_row = mini(1, items.size() - 1) if _selected != 1 else mini(2, items.size() - 1)
	if lit_row >= 0:
		_hover_at.target = float(lit_row)
		if _hover_on.value < 0.05:
			_hover_at.snap(float(lit_row))
	_hover_on.target = 1.0 if lit_row >= 0 else 0.0
	var ringed := (has_focus() and _keys_focus) or preview_state == Preview.FOCUS
	_focus.target = 1.0 if ringed else 0.0


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var lit := maxf(_focus.value, _hover_on.value * 0.5)
	_fill.bg_color = _tokens.surface_raised
	_fill.border_color = _tokens.outline.lerp(_tokens.accent, lit)
	draw_style_box(_fill, rect)
	var inset := float(_tokens.border)
	var row_h := row_height()
	var top := _scroll.value
	var width := size.x - 2.0 * inset
	var font := get_theme_font(&"font", &"UIItemList")
	var font_size := get_theme_font_size(&"font_size", &"UIItemList")
	if _hover_on.value > 0.01:
		var at := Vector2(inset, inset + (_hover_at.value - top) * row_h)
		var tint := Color(_tokens.ink, _tokens.tint_hover * 0.5 * _hover_on.value)
		draw_rect(Rect2(at, Vector2(width, row_h)), tint)
	var bar_rect := Rect2(
		Vector2(inset, inset + (_bar_at.value - top) * row_h), Vector2(width, row_h)
	)
	if _bar_on.value > 0.01:
		var bar := StyleBoxFlat.new()
		bar.anti_aliasing = true
		bar.set_corner_radius_all(maxi(_tokens.radius_md - _tokens.border, 0))
		bar.bg_color = Color(
			_tokens.accent.lerp(_tokens.accent_bright, _hover_on.value * 0.5), _bar_on.value
		)
		draw_style_box(bar, bar_rect)
	var first := maxi(int(floorf(top)), 0)
	var last := mini(int(ceilf(top + rows_shown())), items.size() - 1)
	var text_x := inset + float(_tokens.space_md)
	for row in range(first, last + 1):
		var y := inset + (float(row) - top) * row_h
		var weight := clampf(1.0 - absf(float(row) - _bar_at.value), 0.0, 1.0) * _bar_on.value
		var colour := _tokens.ink.lerp(_tokens.ink_on_accent, weight)
		var baseline := y + (row_h + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		draw_string(
			font,
			Vector2(text_x, baseline),
			items[row],
			HORIZONTAL_ALIGNMENT_LEFT,
			width - 2.0 * float(_tokens.space_md),
			font_size,
			colour
		)
	_draw_scroll_bar(rect, inset)
	_ring.draw(self, rect, _focus.value)


func _draw_scroll_bar(rect: Rect2, inset: float) -> void:
	var shown := float(rows_shown())
	if float(items.size()) <= shown:
		return
	var track := rect.size.y - 2.0 * inset - 2.0 * float(_tokens.space_xs)
	var thumb := maxf(track * shown / float(items.size()), float(_tokens.space_md))
	var span := track - thumb
	var at := span * clampf(_scroll.value / maxf(_last_top(), 1.0), 0.0, 1.0)
	var bar_width := float(_tokens.border) * BAR_WIDTH_BORDERS
	var x := rect.size.x - inset - float(_tokens.space_xs) - bar_width
	var pill := StyleBoxFlat.new()
	pill.anti_aliasing = true
	pill.set_corner_radius_all(int(bar_width))
	pill.bg_color = Color(_tokens.ink_muted, 0.35 + 0.4 * _hover_on.value)
	draw_style_box(
		pill, Rect2(Vector2(x, inset + float(_tokens.space_xs) + at), Vector2(bar_width, thumb))
	)


func ui_sound_role() -> StringName:
	return &"list"


func _on_focus_entered() -> void:
	_keys_focus = not UIInputMode.pointer
	UIAudio.play(&"focus", self)


func _on_mouse_entered() -> void:
	_inside = true
	UIAudio.play(&"hover", self)
	set_process(true)


func _on_mouse_exited() -> void:
	_inside = false
	_hover_row = -1
	set_process(true)
