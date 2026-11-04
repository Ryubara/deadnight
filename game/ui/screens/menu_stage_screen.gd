class_name MenuStageScreen
extends UIScreen
## The menu's live stage on its own, with nothing over it: Left and Right (or the bumpers) walk
## the tabs' cameras. It is what a browser run measures (`index.html?stage`, and `?stage=still`
## for the still, `?stage=live` for the live stage on a software renderer too), and what a capture
## shows, before the tab panels sit on top of it.

var view := MenuStageView.new()
var tab := MenuTab.Id.PLAY


func _ready() -> void:
	super._ready()
	allow_back = false
	stars = false
	# A still asked for by the page address is for this run only: the setting is not written.
	view.forced_mode = MenuStageView.MODE_STILL if params.get("still", false) else -1
	if params.get("live", false):
		view.forced_mode = MenuStageView.MODE_LIVE
	add_child(view)
	view.show_tab(tab)


## Turns the camera to the tab `step` places on, and returns the new tab.
func step_tab(step: int) -> MenuTab.Id:
	tab = MenuTab.neighbour(tab, step)
	view.show_tab(tab)
	return tab


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_right"):
		step_tab(1)
	elif event.is_action_pressed(&"ui_left"):
		step_tab(-1)
	else:
		return
	get_viewport().set_input_as_handled()
