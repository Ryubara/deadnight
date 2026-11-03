class_name UIFocusRing
extends RefCounted
## The focus ring every component shares: it closes in from a wider gap as `amount` goes 0 to 1.
##
## The ring is drawn outside the control's rectangle, so a scroll area that follows the focus
## (`follow_focus` scrolls the control's own rectangle into view, to the edge of the area) cuts it
## off at the first and the last row. `keep_in_view` scrolls the rest of the way.

const LAND_DISTANCE := 10.0

var _tokens: UITokens
var _box := StyleBoxFlat.new()


func _init(tokens: UITokens, radius: int) -> void:
	_tokens = tokens
	_box.anti_aliasing = true
	_box.draw_center = false
	_box.set_border_width_all(tokens.focus_border)
	_box.set_corner_radius_all(radius)


## Draws the ring around `rect` (the thing in focus) on `canvas`. Nothing is drawn at 0.
func draw(canvas: CanvasItem, rect: Rect2, amount: float) -> void:
	if amount <= 0.01:
		return
	var spread := float(_tokens.focus_gap) + (1.0 - amount) * LAND_DISTANCE
	_box.border_color = Color(_tokens.accent_bright, clampf(amount, 0.0, 1.0))
	canvas.draw_style_box(_box, rect.grow(spread))


## Scrolls the area that holds `control` (its nearest `ScrollContainer` that follows the focus) so
## that the control's ring, and the growth of a hovered row, is inside it. `UIRouter` calls it when
## a key or a pad moves the focus, after the area's own follow; a mouse that hovers a button does
## not move the area under itself. The theme's room at the ends of the area (`UITokens.scroll_room`)
## is what makes the first and the last row reachable.
static func keep_in_view(control: Variant) -> void:
	if not is_instance_valid(control) or not (control as Control).is_visible_in_tree():
		return
	var target := control as Control
	var scroll := _scroll_of(target)
	if scroll == null or not scroll.follow_focus:
		return
	var room := float(UITokens.active().scroll_room)
	var seen := (
		scroll.get_global_transform().affine_inverse()
		* target.get_global_transform()
		* Rect2(Vector2.ZERO, target.size).grow(room)
	)
	if seen.size.y > scroll.size.y:
		return
	if seen.position.y < 0.0:
		scroll.scroll_vertical += floori(seen.position.y)
	elif seen.end.y > scroll.size.y:
		scroll.scroll_vertical += ceili(seen.end.y - scroll.size.y)


static func _scroll_of(control: Control) -> ScrollContainer:
	var up := control.get_parent()
	while up != null:
		if up is ScrollContainer:
			return up as ScrollContainer
		up = up.get_parent()
	return null
