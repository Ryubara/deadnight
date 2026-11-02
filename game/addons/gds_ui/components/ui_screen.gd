class_name UIScreen
extends Control
## Base for a screen the router shows: backdrop, initial focus, back rule and lifecycle hooks.
##
## A screen scene also runs on its own (as a main scene): when its parent is not a Control it
## applies the theme and fills the window itself.

## The node that takes focus when the screen appears.
@export var initial_focus: NodePath
## Whether Esc / gamepad B pops this screen.
@export var allow_back := true
## Whether this screen draws the token stars (`UITokens.star_count`); turn it off for a screen that
## covers the sky, or leave the count at 0 in the tokens for a game with none.
@export var stars := true:
	set(value):
		stars = value
		_build_stars()
## Overrides the bottom colour of the backdrop gradient (transparent keeps the token).
@export var glow := Color.TRANSPARENT

## What the pusher passed to the router.
var params := {}

var _tokens := UITokens.active()
var _remembered: Control
var _stars := PackedVector3Array()


func _ready() -> void:
	if not get_parent() is Control:
		theme = UIThemeBuilder.build(_tokens)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_stars()
	resized.connect(_build_stars)
	UITokens.active_changed().connect(_on_tokens_changed)


## How many stars the backdrop draws now: `UITokens.star_count`, or none when `stars` is off.
func star_count() -> int:
	return _stars.size()


## Whether the first focus key (an arrow or accept) with nothing focused is spent giving this screen
## its focus, as a menu wants. A screen that is a live game says no: its keys must reach the game,
## and a key that is also `ui_accept` (a gamepad's Start, which is `pause` too) would be eaten.
func wants_focus_key() -> bool:
	return true


## Called when the screen has become the visible top of the stack.
func screen_enter() -> void:
	focus_initial()


## Called when another screen is pushed over this one.
func screen_pause() -> void:
	pass


## Called when the screen above this one has been popped.
func screen_resume() -> void:
	focus_initial()


## Notes which control has focus, so coming back returns to it. The router calls this just
## before another screen covers this one.
func remember_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	_remembered = focused if focused != null and is_ancestor_of(focused) else null


func focus_initial() -> void:
	var target := _remembered
	if target == null or not target.is_visible_in_tree():
		target = get_node_or_null(initial_focus) as Control
	if target == null:
		target = _first_focusable(self)
	if target != null:
		target.grab_focus()


func _on_tokens_changed(_next: UITokens) -> void:
	_tokens = UITokens.active()
	if theme != null and not get_parent() is Control:
		theme = UIThemeBuilder.build(_tokens)
	_build_stars()


func _draw() -> void:
	var bottom := glow if glow.a > 0.0 else _tokens.bg_glow
	var top := _tokens.bg
	var corners := PackedVector2Array(
		[Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]
	)
	draw_polygon(corners, PackedColorArray([top, top, bottom, bottom]))
	for star in _stars:
		draw_circle(Vector2(star.x, star.y), star.z, Color(_tokens.ink, 0.12 + star.z * 0.1))


func _build_stars() -> void:
	_stars.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = _tokens.star_seed
	for i in _tokens.star_count if stars else 0:
		var at := Vector2(rng.randf() * size.x, rng.randf() * size.y * _tokens.star_band)
		_stars.append(Vector3(at.x, at.y, 1.0 + rng.randf() * 1.6))
	queue_redraw()


static func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		var control := child as Control
		if (
			control != null
			and control.focus_mode == Control.FOCUS_ALL
			and control.is_visible_in_tree()
		):
			if not (control is BaseButton and (control as BaseButton).disabled):
				return control
		var found := _first_focusable(child)
		if found != null:
			return found
	return null
