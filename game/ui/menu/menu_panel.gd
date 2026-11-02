class_name MenuPanel
extends Control
## The base of a tab's panel: which side of the picture it takes, how wide it is, and the hooks
## the shell calls. A panel is built from its `MenuContext` (set before it enters the tree)
## and reads only that.

enum Side { LEFT, RIGHT }

var context: MenuContext


## Which side of the picture the panel sits on (the soldier stands on the other).
func side() -> MenuPanel.Side:
	return MenuPanel.Side.RIGHT


## The width in design units; `compact` is a phone's.
func width(_compact: bool) -> float:
	return 600.0


## Re-reads what the panel shows (the tab was shown again, or the data changed).
func refresh() -> void:
	pass


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
