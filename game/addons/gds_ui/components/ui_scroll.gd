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
