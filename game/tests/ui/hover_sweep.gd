class_name HoverSweep
extends RefCounted
## Hovers every button under a node, one at a time, and reports the ones whose grown look leaves
## the nearest ancestor that clips them (a ScrollContainer, or any control with `clip_contents`):
## the part outside is not drawn, which the maintainer saw as a hovered "Copy the link" with its
## left edge cut off (#628).
##
## Two looks are measured: the hover (the button grown by its scale) and the keyboard focus (the
## same growth, and the focus ring around it on all four sides: the ring above the first row and
## below the last row of a scroll area was cut off, #644). A button in a scroll area is measured
## where a player meets it: with the area at its top, at its end, and with the button in the
## middle.

const TOLERANCE := 0.5


## The nearest ancestor that cuts off what lies outside its rectangle, or null.
static func clipper(node: Control) -> Control:
	var up := node.get_parent()
	while up != null:
		if up is Control and ((up as Control).clip_contents or up is ScrollContainer):
			return up
		up = up.get_parent()
	return null


## The buttons under `root` that a hover can reach and that a clipper holds.
static func buttons(root: Node) -> Array[UIButton]:
	var out: Array[UIButton] = []
	for node in root.find_children("*", "Button", true, false):
		var button := node as UIButton
		if button == null:
			continue
		if button.is_visible_in_tree() and not button.disabled and clipper(button) != null:
			out.append(button)
	return out


## One line for each button that is whole at rest and sticks out of its clipper when hovered
## (`ring` false) or focused with the keyboard (`ring` true).
static func overflows(root: Node, ring: bool) -> Array[String]:
	var found: Array[String] = []
	for button in buttons(root):
		var clip := clipper(button)
		var scroll := clip as ScrollContainer
		var starts: Array = [0] if scroll == null else _scroll_stops(scroll, button)
		var before := 0 if scroll == null else scroll.scroll_vertical
		for stop: int in starts:
			if scroll != null:
				scroll.scroll_vertical = stop
				scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)
			var line := _line(button, clip, ring)
			if line != "":
				found.append(line)
				break
		if scroll != null:
			scroll.scroll_vertical = before
			scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)
	return found


## Walks the keyboard focus onto every button the sweep sees, as a player does with the Down key,
## and reports each one whose ring leaves its clipper once the area has followed the focus: the
## area scrolls the button's own rectangle into view and stops at its edge, so a ring of the first
## or last row visible that way was cut (#644). A coroutine: it waits for the frames the focus and
## the scroll take.
static func walk(root: Node) -> Array[String]:
	var found: Array[String] = []
	var tree := root.get_tree()
	UIInputMode.pointer = false
	for button in buttons(root):
		var clip := clipper(button)
		# Only a scroll area follows the focus; a button that is already focused is not moved to.
		if not clip is ScrollContainer:
			continue
		button.preview_state = UIButton.Preview.NONE
		button.release_focus()
		button.grab_focus()
		for i in 3:
			await tree.process_frame
		button.snap_to_targets()
		var grown := _bounds(button, clip, _ring_reach())
		if not _contains(Rect2(Vector2.ZERO, clip.size), grown):
			found.append(
				(
					"walked to '%s': ring %s leaves its %s %s"
					% [button.text, grown, clip.get_class(), Rect2(Vector2.ZERO, clip.size)]
				)
			)
	return found


## Scrolls the area that holds the button so that the button is in its middle, if it can be.
static func scroll_to_middle(button: Control) -> void:
	var scroll := clipper(button) as ScrollContainer
	if scroll == null:
		return
	scroll.scroll_vertical = _scroll_stops(scroll, button)[2]
	scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)


## Where to scroll to look at the button: the top, the end, and the button in the middle.
static func _scroll_stops(scroll: ScrollContainer, button: Control) -> Array:
	var bar := scroll.get_v_scroll_bar()
	var end := maxi(int(bar.max_value - bar.page), 0)
	# The button's place in the content does not depend on the scroll position.
	var top := scroll.scroll_vertical
	var inside := (
		(scroll.get_global_transform().affine_inverse() * button.get_global_transform()).origin.y
	)
	var middle := top + int(inside + button.size.y * 0.5 - scroll.size.y * 0.5)
	return [0, end, clampi(middle, 0, end)]


static func _line(button: UIButton, clip: Control, ring: bool) -> String:
	var limit := Rect2(Vector2.ZERO, clip.size)
	var reach := _ring_reach() if ring else 0.0
	button.preview_state = UIButton.Preview.NONE
	button.snap_to_targets()
	if not _contains(limit, _bounds(button, clip, 0.0)):
		return ""
	button.preview_state = UIButton.Preview.FOCUS if ring else UIButton.Preview.HOVER
	button.snap_to_targets()
	var grown := _bounds(button, clip, reach)
	button.preview_state = UIButton.Preview.NONE
	button.snap_to_targets()
	if _contains(limit, grown):
		return ""
	return (
		"%s '%s' grown to %s leaves its %s %s"
		% ["focused" if ring else "hovered", button.text, grown, clip.get_class(), limit]
	)


## The button's rectangle as its clipper sees it, scale and pivot included, grown by `reach` in
## the button's own units on every side first (above and below for a scroll area).
static func _bounds(button: Control, clip: Control, reach: float) -> Rect2:
	# Above and below only where an area scrolls: the edge of a screen is its own layout's fit
	# (`solo_settings_tour`), not something a theme margin gives room at.
	var up_down := reach if clip is ScrollContainer else 0.0
	var local := Rect2(Vector2.ZERO, button.size).grow_individual(reach, up_down, reach, up_down)
	var into := clip.get_global_transform().affine_inverse() * button.get_global_transform()
	return into * local


static func _ring_reach() -> float:
	var tokens := UITokens.active()
	return float(tokens.focus_gap + tokens.focus_border)


static func _contains(outer: Rect2, inner: Rect2) -> bool:
	return (
		inner.position.x >= outer.position.x - TOLERANCE
		and inner.end.x <= outer.end.x + TOLERANCE
		and inner.position.y >= outer.position.y - TOLERANCE
		and inner.end.y <= outer.end.y + TOLERANCE
	)
