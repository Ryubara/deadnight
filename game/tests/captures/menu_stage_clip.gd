extends Control
## Clip for #397: the live stage with the dead walking, and the camera gliding from tab to tab.
## Run with Movie Maker through `gds capture frames` (fixed frame rate: every frame is one step):
## `gds capture frames --project game --scene res://tests/captures/menu_stage_clip.tscn
## --seconds 12 --fps 20 --name stage`.

## Seconds the camera stays on a tab before it goes to the next.
const HOLD := 2.2

var view := MenuStageView.new()
var _tab_index := 0
var _since := 0.0


func _ready() -> void:
	view.forced_mode = MenuStageView.MODE_LIVE
	add_child(view)


func _process(delta: float) -> void:
	_since += delta
	if _since >= HOLD:
		_since = 0.0
		_tab_index = (_tab_index + 1) % MenuTab.ORDER.size()
		view.show_tab(MenuTab.ORDER[_tab_index])
