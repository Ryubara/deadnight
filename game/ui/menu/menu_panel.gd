class_name MenuPanel
extends Control
## The base of a tab's panel: which side of the picture it takes, how wide it is, and the hooks
## the shell calls. A panel is built from its `MenuContext` (set before it enters the tree)
## and reads only that.

enum Side { LEFT, RIGHT }

var context: MenuContext
## The width the shell gave the panel (the design width, or what the canvas leaves): rows that
## are built from a width read it through `fit_width`. 0 until the shell has placed the panel.
var area_width := 0.0


## Which side of the picture the panel sits on (the soldier stands on the other).
func side() -> MenuPanel.Side:
	return MenuPanel.Side.RIGHT


## The width in design units; `compact` is a phone's.
func width(_compact: bool) -> float:
	return 600.0


## `width(compact)`, or the area the shell gave when that is narrower (a phone's narrowest canvas
## is 960 units wide and the panel takes at most 70 percent of it).
func fit_width(compact: bool) -> float:
	return width(compact) if area_width <= 0.0 else minf(width(compact), area_width)


## Re-reads what the panel shows (the tab was shown again, or the data changed).
func refresh() -> void:
	pass


## Puts the tab's column in a scroll area the size of the panel, so a column taller than the panel
## (a phone held sideways leaves 372 units of height) scrolls instead of running under the footer
## (#980). The area reaches past the panel by the theme's room at the sides, where the content's own
## edge is the panel's edge and the hover and the focus ring have room to grow, and by the track of
## the bar at the right.
func hold(column: Control) -> UIScroll:
	var scroll := UIScroll.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The bar's track is reserved whether the column scrolls or not, so the column is as wide in
	# both and the panel's buttons are the same width on a tall screen and a short one.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	add_child(scroll)
	var room := UIScroll.margins(scroll).x / 2.0
	scroll.offset_left = -room
	scroll.offset_right = room + scroll.get_v_scroll_bar().get_combined_minimum_size().x
	return scroll


## The control that takes the focus when the panel is entered by keyboard or pad.
func first_focus() -> Control:
	return _first_focusable(self)


## The shell shows the panel.
func on_show() -> void:
	refresh()


## The shell hides the panel.
func on_hide() -> void:
	pass


## Writes what the panel holds in memory, once. The shell calls it when the player leaves the tab,
## asks for another screen, or closes the menu; a panel with nothing to keep leaves it empty.
func commit() -> void:
	pass


func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		if control.focus_mode == Control.FOCUS_ALL:
			return control
		var found := _first_focusable(control)
		if found != null:
			return found
	return null
