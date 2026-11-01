class_name HudPart
extends Control
## Base of every HUD part: it reads a `HudState` and nothing else. A part rebuilds from the state
## in `refresh` (called on every change) and plays its one-shot treatment in `on_event`.

var state: HudState
var tokens := UITokens.active()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Connects the part to the state and shows what it already holds.
func bind(source: HudState) -> void:
	state = source
	state.changed.connect(refresh)
	state.event_applied.connect(on_event)
	refresh()


func refresh() -> void:
	pass


func on_event(_event: Dictionary) -> void:
	pass


## A tween that outlives nothing it should not: owned by this part.
func _tween(kind: UITokens.Ease = UITokens.Ease.STANDARD) -> Tween:
	return UIMotion.apply_ease(create_tween(), kind)
