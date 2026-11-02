extends Control
## Clip for #397: the tab shell on the live stage, the camera and the panel changing tab every
## couple of seconds (the way Q and E do), with sample account and challenge data.
## `gds capture frames --project game --scene res://tests/captures/menu_shell_clip.tscn
## --seconds 13 --fps 20 --name shell`.

const HOLD := 2.4

var shell := MenuShell.new()
var _index := 0
var _since := 0.0


func _ready() -> void:
	shell.context.profile = MenuProfile.from_json(
		MenuProfile.to_json("Ryubara", MenuProfile.xp_at(14) + 212, 485, {"rifle": 900})
	)
	shell.context.board = FakeChallengeBoard.new()
	add_child(shell)


func _process(delta: float) -> void:
	_since += delta
	if _since >= HOLD:
		_since = 0.0
		_index = (_index + 1) % MenuTab.ORDER.size()
		shell.show_tab(MenuTab.ORDER[_index])
