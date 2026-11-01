class_name HudPart
extends Control
## Base of every HUD part: it reads a `HudState` and nothing else. A part rebuilds from the state
## in `refresh`, which runs when a topic it lists in `topics` changed (and once when it is bound),
## and plays its one-shot treatment in `on_event`.

var state: HudState
var tokens := UITokens.active()

var _watched: Array[StringName] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Connects the part to the state and shows what it already holds.
func bind(source: HudState) -> void:
	state = source
	_watched = topics()
	if not _watched.is_empty():
		state.changed.connect(_on_state_changed)
	state.event_applied.connect(on_event)
	refresh()


## The `HudState` topics `refresh` reads. A part that lists none is never refreshed by a change
## (a part that only plays one-shot treatments).
func topics() -> Array[StringName]:
	return []


func refresh() -> void:
	pass


func on_event(_event: Dictionary) -> void:
	pass


func _on_state_changed() -> void:
	for topic in _watched:
		if state.is_dirty(topic):
			refresh()
			return


## A tween that outlives nothing it should not: owned by this part.
func _tween(kind: UITokens.Ease = UITokens.Ease.STANDARD) -> Tween:
	return UIMotion.apply_ease(create_tween(), kind)
