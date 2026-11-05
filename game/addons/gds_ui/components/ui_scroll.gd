@tool
class_name UIScroll
extends ScrollContainer
## A vertical scroll area drawn from tokens: the theme styles its bars, a soft shade at the top
## and bottom edge shows there is more to see, and the scroll follows the focus. It does not take
## focus itself unless `keyboard_scroll` is on: then Up, Down, Page Up, Page Down, Home and End
## (and the d-pad) scroll it while it has the focus, for a list of text that has nothing to focus.

## How many lines of body text one Up or Down press scrolls.
const LINES_PER_STEP := 2.0
## The share of the visible height a page scroll moves.
const PAGE_SHARE := 0.85
## The edge shade is this many `space_*` tall: `space_lg` of them.
const SHADE_ALPHA := 0.55

## How far a finger may slip, in the units of the window it is in, before a touch is a scroll and
## not a press: `func(window: Window) -> float`. A game that knows what a finger is (a size in real
## pixels, not units) sets it; empty keeps the engine's deadzone of 0, where the first movement
## scrolls. A button inside the area takes the press and hands the touch to the area (its mouse
## filter passes), and the area ends the press when it starts to scroll, so a deadzone of 0 loses
## the press of every finger that moves a hair: the area uses this one for a touch that starts on
## a button (`take_touch`).
static var slip_units := Callable()

## Whether the area takes the focus and scrolls on the keys (see the class comment).
@export var keyboard_scroll := false:
	set(value):
		keyboard_scroll = value
		focus_mode = Control.FOCUS_ALL if value else Control.FOCUS_NONE

var _tokens := UITokens.active()
var _top: UISpring
var _bottom: UISpring
var _shade: Control


func _init() -> void:
	_top = UISpring.new()
	_bottom = UISpring.new()
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	focus_mode = Control.FOCUS_NONE
	UIScroll.take_touch(self)
	_shade = Control.new()
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.draw.connect(_draw_shade)
	add_child(_shade, false, Node.INTERNAL_MODE_BACK)
	_apply_tokens()


## Reads the active tokens into everything this control caches: spring tuning.
func _apply_tokens() -> void:
	_tokens = UITokens.active()
	for spring in [_top, _bottom]:
		spring.stiffness = _tokens.spring_stiffness
		spring.damping = _tokens.spring_damping
	_shade.queue_redraw()


func _on_tokens_changed(_next: UITokens) -> void:
	_apply_tokens()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	UITokens.active_changed().connect(_on_tokens_changed)
	get_v_scroll_bar().changed.connect(_on_scrolled)
	get_v_scroll_bar().value_changed.connect(_on_scrolled.unbind(1))
	resized.connect(_on_scrolled)
	_update_targets()
	for spring in [_top, _bottom]:
		spring.snap(spring.target)


func _process(delta: float) -> void:
	_update_targets()
	var settled := true
	for spring in [_top, _bottom]:
		if UIMotion.reduced:
			spring.snap(spring.target)
		spring.step(delta)
		settled = settled and spring.is_settled()
	_shade.queue_redraw()
	if settled:
		set_process(false)


## Scrolls by `steps` lines (negative is up) or, with `pages`, by that many pages; stops at
## the ends.
func scroll_by(steps: float, pages := false) -> void:
	var amount := size.y * PAGE_SHARE if pages else _line_height() * LINES_PER_STEP
	scroll_vertical = clampi(scroll_vertical + roundi(steps * amount), 0, int(scroll_end()))


## Where the content ends, in scroll units: the largest `scroll_vertical`.
func scroll_end() -> float:
	return maxf(get_v_scroll_bar().max_value - get_v_scroll_bar().page, 0.0)


## What any ScrollContainer keeps free around its content (the theme's room for a hovered button
## and the focus ring, `UITokens.hover_room` and `scroll_room`), as the width and height it adds to
## the content: a screen that sizes a scroll area from its content adds this to the content's
## height, or its last row scrolls by that much.
static func margins(scroll: ScrollContainer) -> Vector2:
	return scroll.get_theme_stylebox(&"panel").get_minimum_size()


## The width a scroll area takes from its content: the room at both sides and the bar's track. A
## column that must fit a given width is that width less this.
static func side_room(scroll: ScrollContainer) -> float:
	return UIScroll.margins(scroll).x + scroll.get_v_scroll_bar().get_combined_minimum_size().x


## Makes `button` hand a drag that starts on it to the scroll area it sits in, and only then. A
## button stops the pointer (`MOUSE_FILTER_STOP`), so the touch, its drag steps and the lift
## never reach the area behind it; a button that passes them (`MOUSE_FILTER_PASS`) lets the area
## scroll from it, but with nothing that stops the press above it the press goes on to
## `_unhandled_input` too (the player's click that takes the pointer), so it passes only while a
## stopping `ScrollContainer` is above it. Decided each time the button enters the tree, so one that
## is moved into or out of a card is right at once. The call also makes the button go back to its
## resting look after a tap (`UITouchRest`), in a card or not: a lifted finger sends no mouse exit.
static func pass_touch_in_scroll(button: BaseButton) -> void:
	UITouchRest.follow(button)
	if not button.tree_entered.is_connected(_follow_scroll.bind(button)):
		button.tree_entered.connect(_follow_scroll.bind(button))
	if button.is_inside_tree():
		_follow_scroll(button)


## The mouse filter of `button` for where it sits: PASS in a scroll area, STOP elsewhere. A button
## whose filter is IGNORE (one that is only drawn) is left alone.
static func _follow_scroll(button: BaseButton) -> void:
	if button.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	button.mouse_filter = (
		Control.MOUSE_FILTER_PASS if _in_scroll(button) else Control.MOUSE_FILTER_STOP
	)


## Whether a scroll area that takes the pointer is above `node`.
static func _in_scroll(node: Node) -> bool:
	var up := node.get_parent()
	while up != null:
		var scroll := up as ScrollContainer
		if scroll != null and scroll.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
		up = up.get_parent()
	return false


## Makes `scroll` (any `ScrollContainer`) the area a button hands a touch to: it stops the pointer
## itself, so a press that went through a button into it goes no further (a plain
## `ScrollContainer` passes the pointer on), and it waits for `slip_units` of movement before a
## touch drag that starts on a button scrolls it, so the press of a finger that moves a hair is not
## given up. A drag that starts anywhere else scrolls at once, as it always did. The size is read
## at each press, so a window that is resized, or a scale that changes, is followed. A `UIScroll`
## does this itself; a plain `ScrollContainer` calls it once, before a button enters it.
static func take_touch(scroll: ScrollContainer) -> void:
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	if not scroll.has_meta(&"ui_slip"):
		scroll.set_meta(&"ui_slip", true)
		scroll.gui_input.connect(_read_slip.bind(scroll))
		scroll.scroll_started.connect(scroll.set_meta.bind(&"ui_scrolled", true))


static func _read_slip(event: InputEvent, scroll: ScrollContainer) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not scroll.is_inside_tree():
		return
	if not touch.pressed:
		# The finger lifts. If this touch scrolled the area, the buttons gave their press up, but the
		# finger is still over one (the content moved with it): it must not stay lit.
		if scroll.get_meta(&"ui_scrolled", false):
			scroll.set_meta(&"ui_scrolled", false)
			_drop_hover(scroll)
		return
	scroll.set_meta(&"ui_scrolled", false)
	var slip := 0.0
	if slip_units.is_valid() and _button_at(scroll, touch.position) != null:
		slip = float(slip_units.call(scroll.get_window()))
	scroll.scroll_deadzone = maxi(roundi(slip), 0)


## Takes the hover off every button of `scroll` that has it. A finger that lifts sends no mouse
## exit, so the engine keeps the button it lifted over hovered (and drawn lit) until the next mouse
## motion; a button that stops being a pointer target for a moment is told the mouse left it.
static func _drop_hover(scroll: ScrollContainer) -> void:
	for node in scroll.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button.is_hovered():
			UITouchRest.drop_hover(button)


## The button under `point` (in `scroll`'s own coordinates) that a press would reach, or null.
static func _button_at(scroll: ScrollContainer, point: Vector2) -> BaseButton:
	var on_canvas := scroll.get_global_transform() * point
	for node in scroll.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button.disabled or button.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if not button.is_visible_in_tree():
			continue
		var local := button.get_global_transform().affine_inverse() * on_canvas
		if Rect2(Vector2.ZERO, button.size).has_point(local):
			return button
	return null


## Whether there is more content above the visible part.
func has_more_above() -> bool:
	return scroll_vertical > 0


## Whether there is more content below the visible part.
func has_more_below() -> bool:
	return float(scroll_vertical) < scroll_end() - 1.0


func _gui_input(event: InputEvent) -> void:
	if not keyboard_scroll:
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
			accept_event()
			return
	if event.is_action_pressed(&"ui_home"):
		scroll_vertical = 0
		accept_event()
	elif event.is_action_pressed(&"ui_end"):
		scroll_vertical = int(scroll_end())
		accept_event()


func _line_height() -> float:
	var font := get_theme_default_font()
	return font.get_height(get_theme_default_font_size()) * 1.5


func _on_scrolled() -> void:
	_update_targets()
	set_process(true)


func _update_targets() -> void:
	_top.target = 1.0 if has_more_above() else 0.0
	_bottom.target = 1.0 if has_more_below() else 0.0


func _draw_shade() -> void:
	var height := float(_tokens.space_lg)
	var shade := Color(_tokens.shadow, SHADE_ALPHA)
	var clear := Color(_tokens.shadow, 0.0)
	var width := _shade.size.x
	if _top.value > 0.01:
		var strong := Color(shade, shade.a * _top.value)
		_shade.draw_polygon(
			PackedVector2Array(
				[Vector2(0, 0), Vector2(width, 0), Vector2(width, height), Vector2(0, height)]
			),
			PackedColorArray([strong, strong, clear, clear])
		)
	if _bottom.value > 0.01:
		var base := _shade.size.y
		var strong := Color(shade, shade.a * _bottom.value)
		_shade.draw_polygon(
			PackedVector2Array(
				[
					Vector2(0, base - height),
					Vector2(width, base - height),
					Vector2(width, base),
					Vector2(0, base)
				]
			),
			PackedColorArray([clear, clear, strong, strong])
		)
